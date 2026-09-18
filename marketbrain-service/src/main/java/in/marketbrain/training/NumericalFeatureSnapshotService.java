package in.marketbrain.training;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Isolation;
import org.springframework.transaction.annotation.Transactional;

import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.sql.Timestamp;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.HexFormat;
import java.util.List;
import java.util.UUID;

@Service
public class NumericalFeatureSnapshotService {
    static final String ITEMS_SQL = """
            SELECT instrument_id, symbol FROM prototype_swing_training_dataset_item
            WHERE run_id = ? ORDER BY instrument_id LIMIT ? OFFSET ?
            """;
    static final String BARS_SQL = """
            WITH exclusions AS MATERIALIZED (
                SELECT DISTINCT exclusion_from, exclusion_to FROM market_data_feature_exclusion
                WHERE instrument_id = ? AND exclusion_from <= ? AND exclusion_to >= ?
            )
            SELECT c.id, (c.opened_at AT TIME ZONE 'Asia/Kolkata')::date AS trading_date,
                   source.code AS source_code, c.received_at,
                   c.open_price, c.high_price, c.low_price, c.close_price, c.volume,
                   EXISTS (SELECT 1 FROM exclusions e WHERE
                       (c.opened_at AT TIME ZONE 'Asia/Kolkata')::date
                       BETWEEN e.exclusion_from AND e.exclusion_to) AS excluded
            FROM market_candle c JOIN market_data_source source ON source.id = c.source_id
            WHERE c.instrument_id = ? AND c.interval_code = 'days:1' AND c.is_complete = TRUE
              AND source.code IN ('NSE_BHAVCOPY','UPSTOX') AND c.opened_at >= ? AND c.opened_at < ?
            ORDER BY c.opened_at DESC, c.source_id, c.received_at DESC, c.id DESC LIMIT 2001
            """;
    private final JdbcTemplate jdbc;
    private final ObjectMapper mapper;
    public NumericalFeatureSnapshotService(JdbcTemplate jdbc, ObjectMapper mapper) {
        this.jdbc = jdbc; this.mapper = mapper;
    }

    @Transactional(readOnly = true, timeout = 30, isolation = Isolation.REPEATABLE_READ)
    public Snapshot inspect(UUID runId, int offset, int limit) {
        if (runId == null || runId.equals(new UUID(0,0)) || offset < 0 || offset > 499 || limit < 1 || limit > 4) {
            throw new IllegalArgumentException("Explicit run required; offset 0..499 and limit 1..4.");
        }
        var runs = jdbc.query(NumericalHistoryCoverageService.RUN_SQL, s -> {
            s.setObject(1,runId); s.setQueryTimeout(5);
        }, (rs,n) -> new NumericalHistoryCoverageService.Run(rs.getObject("as_of",LocalDate.class),
                rs.getString("dataset_manifest_hash"),rs.getInt("instrument_count")));
        if (runs.size() != 1) throw new IllegalArgumentException("Completed run not found.");
        var run = runs.getFirst();
        if (run.count() < 1 || run.count() > 500 || offset >= run.count() || run.asOf() == null
                || run.manifest() == null || run.manifest().isBlank()) throw new IllegalStateException("Invalid run metadata/scope.");
        var items = jdbc.query(ITEMS_SQL, s -> {
            s.setObject(1,runId); s.setInt(2,limit); s.setInt(3,offset); s.setQueryTimeout(5);
        }, (rs,n) -> new Item(rs.getLong("instrument_id"),rs.getString("symbol")));
        if (items.size() != Math.min(limit,run.count()-offset)
                || items.stream().map(Item::id).distinct().count() != items.size()) {
            throw new IllegalStateException("Item scope mismatch.");
        }
        var from = run.asOf().minusDays(729);
        // Fixed calendar-week offsets, chosen before looking at prices/outcomes; never shift missing dates.
        var dates = List.of(run.asOf().minusWeeks(8),run.asOf().minusWeeks(4),run.asOf());
        var calculator = new NumericalFeatureSnapshot();
        var instruments = new ArrayList<Instrument>();
        for (var item : items) {
            var raw = jdbc.query(BARS_SQL, s -> {
                s.setLong(1,item.id()); s.setObject(2,run.asOf()); s.setObject(3,from); s.setLong(4,item.id());
                s.setTimestamp(5,Timestamp.from(from.atStartOfDay(ZoneId.of("Asia/Kolkata")).toInstant()));
                s.setTimestamp(6,Timestamp.from(run.asOf().plusDays(1).atStartOfDay(ZoneId.of("Asia/Kolkata")).toInstant()));
                s.setFetchSize(500); s.setQueryTimeout(5);
            }, (rs,n) -> {
                Timestamp received = rs.getTimestamp("received_at");
                return new NumericalFeatureSnapshot.SourceBar(rs.getLong("id"),rs.getObject("trading_date",LocalDate.class),
                        rs.getString("source_code"),received == null ? null : received.toInstant(),rs.getBigDecimal("open_price"),
                        rs.getBigDecimal("high_price"),rs.getBigDecimal("low_price"),rs.getBigDecimal("close_price"),
                        rs.getBigDecimal("volume"),rs.getBoolean("excluded"));
            });
            boolean truncated = raw.size() > 2000;
            var canonical = calculator.canonicalize(raw);
            instruments.add(new Instrument(item.id(),item.symbol(),raw.size(),truncated,canonical,
                    dates.stream().map(d -> calculator.calculate(d,canonical,truncated)).toList()));
        }
        var payload = new Payload(NumericalFeatureSnapshot.VERSION,runId,run.manifest(),run.asOf(),from,offset,limit,
                dates,List.copyOf(instruments),
                "NSE_FIRST_THEN_RECEIVED_DESC_ID_DESC_V1; current exclusions; stored prices, adjustment not certified",
                "252 observed bars; first-close EMA seed; Wilder RSI/ATR; sample SD log volatility; "
                        + "volumeRatio20 excludes current bar from denominator; rangePosition252 uses CLOSE extrema, flat=50");
        try {
            var hash = HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(mapper.writeValueAsBytes(payload)));
            return new Snapshot("FEATURE_SNAPSHOT_REVIEW_REQUIRED",payload,hash,
                    instruments.stream().anyMatch(Instrument::truncated),false,false,0,0,0,
                    "Features only, no targets/splits/fitting. Calendar gaps not certified: 252 observations are not guaranteed "
                            + "252 exchange sessions. Backfilled/current revised prices and current universe/exclusions, not as-known replay. "
                            + "Prior quality job membership and original 10-stock pilot final evidence remain unlinked. "
                            + "Input SHA256 covers Jackson serialization of payload, not whole response or client reserialization.");
        } catch (JsonProcessingException | NoSuchAlgorithmException e) { throw new IllegalStateException("Cannot hash snapshot.",e); }
    }
    record Item(long id, String symbol) { }
    public record Instrument(long instrumentId, String symbol, int rawRowCount, boolean truncated,
            List<NumericalFeatureSnapshot.SourceBar> canonicalBars, List<NumericalFeatureSnapshot.Row> rows) { }
    public record Payload(String version, UUID datasetRunId, String datasetManifestHash, LocalDate asOf,
            LocalDate windowFrom, int offset, int limit, List<LocalDate> decisionDates, List<Instrument> instruments,
            String sourcePolicy, String featurePolicy) { }
    public record Snapshot(String status, Payload payload, String payloadSha256, boolean partial,
            boolean trainingAuthorized, boolean databaseWritesPerformed, int modelCallCount,
            int providerCallCount, int ordersCreated, String limitations) { }
}
