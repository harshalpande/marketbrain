package in.marketbrain.feature;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowCallbackHandler;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.sql.Date;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;

@Service
public class FeatureUniversePreviewService {

    private static final String CANONICAL_UNIVERSE_CANDLES_SQL = """
            WITH members AS (
                SELECT member.instrument_id, member.source_symbol
                FROM universe_snapshot_member member
                WHERE member.snapshot_id = ?
                  AND member.match_status = 'MATCHED'
            ), ranked AS (
                SELECT member.source_symbol,
                       (candle.opened_at AT TIME ZONE 'Asia/Kolkata')::date AS trading_date,
                       source.code AS source_code,
                       candle.open_price,
                       candle.high_price,
                       candle.low_price,
                       candle.close_price,
                       candle.volume,
                       EXISTS (
                           SELECT 1
                           FROM market_data_feature_exclusion exclusion
                           WHERE exclusion.instrument_id = candle.instrument_id
                             AND (candle.opened_at AT TIME ZONE 'Asia/Kolkata')::date
                                 BETWEEN exclusion.exclusion_from AND exclusion.exclusion_to
                       ) AS excluded,
                       ROW_NUMBER() OVER (
                           PARTITION BY candle.instrument_id,
                                        (candle.opened_at AT TIME ZONE 'Asia/Kolkata')::date
                           ORDER BY CASE source.code
                               WHEN 'NSE_BHAVCOPY' THEN 1
                               WHEN 'UPSTOX' THEN 2
                               ELSE 3
                           END,
                           candle.received_at DESC,
                           candle.id DESC
                       ) AS source_rank
                FROM members member
                JOIN market_candle candle ON candle.instrument_id = member.instrument_id
                JOIN market_data_source source ON source.id = candle.source_id
                WHERE candle.interval_code = 'days:1'
                  AND candle.is_complete = TRUE
                  AND source.code IN ('UPSTOX', 'NSE_BHAVCOPY')
                  AND (candle.opened_at AT TIME ZONE 'Asia/Kolkata')::date <= ?
            )
            SELECT source_symbol, trading_date, source_code, open_price, high_price,
                   low_price, close_price, volume, excluded
            FROM ranked
            WHERE source_rank = 1
            ORDER BY source_symbol, trading_date
            """;

    private final JdbcTemplate jdbcTemplate;
    private final FeaturePreviewService previewService;
    private final FeatureUniverseManifestHasher manifestHasher;

    public FeatureUniversePreviewService(
            JdbcTemplate jdbcTemplate,
            FeaturePreviewService previewService,
            FeatureUniverseManifestHasher manifestHasher
    ) {
        this.jdbcTemplate = jdbcTemplate;
        this.previewService = previewService;
        this.manifestHasher = manifestHasher;
    }

    @Transactional(readOnly = true)
    public FeatureUniversePreview preview(LocalDate asOf) {
        UniverseSnapshot snapshot = currentSnapshot();
        List<String> members = currentMembers(snapshot.id());
        FeatureAccumulator accumulator = new FeatureAccumulator(asOf);

        jdbcTemplate.query(connection -> {
            var statement = connection.prepareStatement(CANONICAL_UNIVERSE_CANDLES_SQL);
            statement.setObject(1, snapshot.id());
            statement.setDate(2, Date.valueOf(asOf));
            statement.setFetchSize(1_000);
            return statement;
        }, (RowCallbackHandler) resultSet -> accumulator.accept(
                resultSet.getString("source_symbol"),
                new FeatureCandle(
                        resultSet.getObject("trading_date", LocalDate.class),
                        resultSet.getString("source_code"),
                        resultSet.getBigDecimal("open_price"),
                        resultSet.getBigDecimal("high_price"),
                        resultSet.getBigDecimal("low_price"),
                        resultSet.getBigDecimal("close_price"),
                        resultSet.getBigDecimal("volume"),
                        resultSet.getBoolean("excluded"))));

        List<FeaturePreview> previews = accumulator.finish(members);
        int eligible = count(previews, "ELIGIBLE");
        int stale = count(previews, "STALE");
        int insufficient = count(previews, "INSUFFICIENT_HISTORY");
        int noData = count(previews, "NO_ELIGIBLE_DATA");
        if (eligible + stale + insufficient + noData != previews.size()) {
            throw new IllegalStateException("The feature universe contains an unsupported status.");
        }

        return new FeatureUniversePreview(
                "REVIEW_REQUIRED",
                FeaturePreviewService.FEATURE_SET_VERSION,
                asOf,
                snapshot.id(),
                snapshot.observedOn(),
                previews.size(),
                eligible,
                stale,
                insufficient,
                noData,
                eligible + stale,
                previews.stream().mapToLong(FeaturePreview::canonicalObservationCount).sum(),
                previews.stream().mapToLong(FeaturePreview::eligibleObservationCount).sum(),
                previews.stream().mapToLong(FeaturePreview::excludedObservationCount).sum(),
                manifestHasher.hash(snapshot.id(), asOf, previews),
                true,
                false,
                previews,
                "All matched instruments in the latest NIFTY 500 snapshot were classified without writing data."
        );
    }

    private UniverseSnapshot currentSnapshot() {
        List<UniverseSnapshot> snapshots = jdbcTemplate.query("""
                SELECT id, observed_on
                FROM universe_snapshot
                WHERE universe_code = 'NIFTY_500'
                ORDER BY observed_on DESC, received_at DESC
                LIMIT 1
                """, (resultSet, row) -> new UniverseSnapshot(
                        resultSet.getObject("id", UUID.class),
                        resultSet.getObject("observed_on", LocalDate.class)));
        if (snapshots.isEmpty()) {
            throw new IllegalStateException("No NIFTY 500 universe snapshot is available.");
        }
        return snapshots.getFirst();
    }

    private List<String> currentMembers(UUID snapshotId) {
        List<String> members = jdbcTemplate.query("""
                SELECT source_symbol
                FROM universe_snapshot_member
                WHERE snapshot_id = ? AND match_status = 'MATCHED'
                ORDER BY source_symbol
                """, (resultSet, row) -> resultSet.getString("source_symbol"), snapshotId);
        if (members.isEmpty()) {
            throw new IllegalStateException("The latest NIFTY 500 snapshot has no matched instruments.");
        }
        if (new HashSet<>(members).size() != members.size()) {
            throw new IllegalStateException("The latest NIFTY 500 snapshot contains duplicate symbols.");
        }
        return members;
    }

    private int count(List<FeaturePreview> previews, String status) {
        return (int) previews.stream().filter(item -> status.equals(item.status())).count();
    }

    private record UniverseSnapshot(UUID id, LocalDate observedOn) {
    }

    private final class FeatureAccumulator {
        private final LocalDate asOf;
        private final List<FeaturePreview> previews = new ArrayList<>();
        private final Set<String> seenSymbols = new HashSet<>();
        private final List<FeatureCandle> currentCandles = new ArrayList<>();
        private String currentSymbol;

        private FeatureAccumulator(LocalDate asOf) {
            this.asOf = asOf;
        }

        private void accept(String symbol, FeatureCandle candle) {
            if (currentSymbol != null && !currentSymbol.equals(symbol)) {
                flush();
                if (seenSymbols.contains(symbol)) {
                    throw new IllegalStateException("Canonical candle rows are not grouped by symbol.");
                }
            }
            currentSymbol = symbol;
            currentCandles.add(candle);
        }

        private List<FeaturePreview> finish(List<String> members) {
            flush();
            for (String symbol : members) {
                if (!seenSymbols.contains(symbol)) {
                    previews.add(previewService.previewFromCanonical(symbol, asOf, List.of()));
                }
            }
            previews.sort(Comparator.comparing(FeaturePreview::symbol));
            if (previews.size() != members.size()) {
                throw new IllegalStateException("The feature universe did not produce exactly one result per member.");
            }
            return List.copyOf(previews);
        }

        private void flush() {
            if (currentSymbol == null) {
                return;
            }
            previews.add(previewService.previewFromCanonical(
                    currentSymbol, asOf, List.copyOf(currentCandles)));
            seenSymbols.add(currentSymbol);
            currentCandles.clear();
        }
    }
}
