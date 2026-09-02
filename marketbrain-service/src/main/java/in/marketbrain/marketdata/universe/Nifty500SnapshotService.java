package in.marketbrain.marketdata.universe;

import in.marketbrain.configuration.HistoricalBackfillProperties;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionTemplate;

import java.io.IOException;
import java.io.StringReader;
import java.nio.charset.StandardCharsets;
import java.sql.Date;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

@Service
public class Nifty500SnapshotService {

    private static final String UNIVERSE_CODE = "NIFTY_500";
    private static final String SOURCE_NAME = "NSE_INDICES_CURRENT_CONSTITUENTS";

    private final CurrentNifty500Client client;
    private final CurrentNifty500CsvParser parser;
    private final HistoricalBackfillProperties properties;
    private final JdbcTemplate jdbcTemplate;
    private final TransactionTemplate transactionTemplate;

    public Nifty500SnapshotService(
            CurrentNifty500Client client,
            CurrentNifty500CsvParser parser,
            HistoricalBackfillProperties properties,
            JdbcTemplate jdbcTemplate,
            TransactionTemplate transactionTemplate
    ) {
        this.client = client;
        this.parser = parser;
        this.properties = properties;
        this.jdbcTemplate = jdbcTemplate;
        this.transactionTemplate = transactionTemplate;
    }

    public Nifty500SnapshotImportResult importCurrent(LocalDate observedOn) {
        Nifty500SourceResult source = client.fetch();
        if (!source.succeeded()) {
            return failure(source.status(), observedOn, source.detail());
        }
        try {
            List<CurrentNifty500Constituent> constituents = parser.parse(new StringReader(
                    new String(source.payload(), StandardCharsets.UTF_8)));
            return transactionTemplate.execute(status -> persist(observedOn, source.sha256(), constituents));
        } catch (IOException | IllegalArgumentException exception) {
            return failure("INVALID_SOURCE", observedOn,
                    "Current NIFTY 500 source failed validation: " + exception.getMessage());
        }
    }

    private Nifty500SnapshotImportResult persist(
            LocalDate observedOn,
            String sourceSha256,
            List<CurrentNifty500Constituent> constituents
    ) {
        List<UUID> existing = jdbcTemplate.query("""
                SELECT id FROM universe_snapshot
                WHERE universe_code = ? AND observed_on = ? AND source_sha256 = ?
                """, (rs, row) -> rs.getObject(1, UUID.class), UNIVERSE_CODE, Date.valueOf(observedOn), sourceSha256);
        if (!existing.isEmpty()) {
            return resultForExisting(existing.getFirst(), observedOn,
                    "This exact current NIFTY 500 snapshot was already imported.");
        }

        UUID snapshotId = UUID.randomUUID();
        List<String> unmatched = new ArrayList<>();
        int matched = 0;
        jdbcTemplate.update("""
                INSERT INTO universe_snapshot
                    (id, universe_code, observed_on, source_name, source_url, source_sha256,
                     source_member_count, matched_member_count)
                VALUES (?, ?, ?, ?, ?, ?, ?, 0)
                """, snapshotId, UNIVERSE_CODE, Date.valueOf(observedOn), SOURCE_NAME,
                properties.currentNifty500Url(), sourceSha256, constituents.size());

        for (CurrentNifty500Constituent item : constituents) {
            List<MatchedInstrument> matches = jdbcTemplate.query("""
                    SELECT instrument.id, mapping.provider_instrument_key
                    FROM instrument
                    JOIN provider_instrument mapping ON mapping.instrument_id = instrument.id AND mapping.active = TRUE
                    JOIN market_data_source source ON source.id = mapping.source_id AND source.code = 'UPSTOX'
                    WHERE instrument.exchange = 'NSE' AND instrument.symbol = ? AND instrument.isin = ?
                    """, (rs, row) -> new MatchedInstrument(rs.getLong(1), rs.getString(2)),
                    item.symbol(), item.isin());
            MatchedInstrument match = matches.isEmpty() ? null : matches.getFirst();
            if (match == null) {
                unmatched.add(item.symbol());
            } else {
                matched++;
            }
            jdbcTemplate.update("""
                    INSERT INTO universe_snapshot_member
                        (snapshot_id, source_symbol, source_isin, source_company_name, source_industry,
                         instrument_id, provider_instrument_key, match_status)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """, snapshotId, item.symbol(), item.isin(), item.companyName(), item.industry(),
                    match == null ? null : match.instrumentId(),
                    match == null ? null : match.providerInstrumentKey(),
                    match == null ? "UNMATCHED" : "MATCHED");
        }
        jdbcTemplate.update("UPDATE universe_snapshot SET matched_member_count = ? WHERE id = ?", matched, snapshotId);
        return new Nifty500SnapshotImportResult(
                "SUCCESS", snapshotId, observedOn, constituents.size(), matched, unmatched.size(),
                unmatched.stream().limit(20).toList(),
                unmatched.isEmpty()
                        ? "Current NIFTY 500 snapshot matched completely to Upstox instruments."
                        : "Snapshot stored; unmatched symbols are excluded from backfill until mapped."
        );
    }

    private Nifty500SnapshotImportResult resultForExisting(UUID snapshotId, LocalDate observedOn, String detail) {
        int[] counts = jdbcTemplate.queryForObject("""
                SELECT source_member_count, matched_member_count FROM universe_snapshot WHERE id = ?
                """, (rs, row) -> new int[]{rs.getInt(1), rs.getInt(2)}, snapshotId);
        List<String> unmatched = jdbcTemplate.query("""
                SELECT source_symbol FROM universe_snapshot_member
                WHERE snapshot_id = ? AND match_status = 'UNMATCHED' ORDER BY source_symbol LIMIT 20
                """, (rs, row) -> rs.getString(1), snapshotId);
        return new Nifty500SnapshotImportResult("ALREADY_IMPORTED", snapshotId, observedOn,
                counts[0], counts[1], counts[0] - counts[1], unmatched, detail);
    }

    private Nifty500SnapshotImportResult failure(String status, LocalDate observedOn, String detail) {
        return new Nifty500SnapshotImportResult(status, null, observedOn, 0, 0, 0, List.of(), detail);
    }

    private record MatchedInstrument(long instrumentId, String providerInstrumentKey) {
    }
}
