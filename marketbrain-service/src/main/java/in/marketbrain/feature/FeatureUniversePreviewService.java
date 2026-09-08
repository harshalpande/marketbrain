package in.marketbrain.feature;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowCallbackHandler;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.sql.Date;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

@Service
public class FeatureUniversePreviewService {

    private static final Logger LOGGER = LoggerFactory.getLogger(FeatureUniversePreviewService.class);

    private static final String CANONICAL_UNIVERSE_CANDLES_SQL = """
            WITH members AS (
                SELECT member.instrument_id, member.source_symbol
                FROM universe_snapshot_member member
                WHERE member.snapshot_id = ?
                  AND member.match_status = 'MATCHED'
            ), ranked AS (
                SELECT member.source_symbol,
                       member.instrument_id,
                       (candle.opened_at AT TIME ZONE 'Asia/Kolkata')::date AS trading_date,
                       source.code AS source_code,
                       candle.open_price,
                       candle.high_price,
                       candle.low_price,
                       candle.close_price,
                       candle.volume,
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
            SELECT source_symbol, instrument_id, trading_date, source_code, open_price, high_price,
                   low_price, close_price, volume
            FROM ranked
            WHERE source_rank = 1
            ORDER BY instrument_id, trading_date
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
        long startedAt = System.nanoTime();
        UniverseSnapshot snapshot = currentSnapshot();
        List<UniverseMember> members = currentMembers(snapshot.id());
        LOGGER.info("Feature universe preview started: asOf={}, instruments={}", asOf, members.size());
        Map<Long, List<ExclusionRange>> exclusions = featureExclusions(snapshot.id(), asOf);
        FeatureAccumulator accumulator = new FeatureAccumulator(asOf, members.size());
        LOGGER.info("Feature universe exclusions loaded: asOf={}, exclusionInstruments={}",
                asOf, exclusions.size());

        jdbcTemplate.query(connection -> {
            var statement = connection.prepareStatement(CANONICAL_UNIVERSE_CANDLES_SQL);
            statement.setObject(1, snapshot.id());
            statement.setDate(2, Date.valueOf(asOf));
            statement.setFetchSize(1_000);
            statement.setQueryTimeout(600);
            return statement;
        }, (RowCallbackHandler) resultSet -> {
            long instrumentId = resultSet.getLong("instrument_id");
            LocalDate tradingDate = resultSet.getObject("trading_date", LocalDate.class);
            accumulator.accept(
                instrumentId,
                resultSet.getString("source_symbol"),
                new FeatureCandle(
                        tradingDate,
                        resultSet.getString("source_code"),
                        resultSet.getBigDecimal("open_price"),
                        resultSet.getBigDecimal("high_price"),
                        resultSet.getBigDecimal("low_price"),
                        resultSet.getBigDecimal("close_price"),
                        resultSet.getBigDecimal("volume"),
                        isExcluded(exclusions.get(instrumentId), tradingDate)));
        });

        List<FeaturePreview> previews = accumulator.finish(members);
        int eligible = count(previews, "ELIGIBLE");
        int stale = count(previews, "STALE");
        int insufficient = count(previews, "INSUFFICIENT_HISTORY");
        int noData = count(previews, "NO_ELIGIBLE_DATA");
        if (eligible + stale + insufficient + noData != previews.size()) {
            throw new IllegalStateException("The feature universe contains an unsupported status.");
        }
        long elapsedSeconds = (System.nanoTime() - startedAt) / 1_000_000_000L;
        LOGGER.info("Feature universe preview completed: asOf={}, instruments={}, eligible={}, stale={}, "
                        + "insufficientHistory={}, noData={}, elapsedSeconds={}",
                asOf, previews.size(), eligible, stale, insufficient, noData, elapsedSeconds);

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

    private List<UniverseMember> currentMembers(UUID snapshotId) {
        List<UniverseMember> members = jdbcTemplate.query("""
                SELECT instrument_id, source_symbol
                FROM universe_snapshot_member
                WHERE snapshot_id = ? AND match_status = 'MATCHED'
                ORDER BY instrument_id
                """, (resultSet, row) -> new UniverseMember(
                        resultSet.getLong("instrument_id"),
                        resultSet.getString("source_symbol")), snapshotId);
        if (members.isEmpty()) {
            throw new IllegalStateException("The latest NIFTY 500 snapshot has no matched instruments.");
        }
        Set<String> symbols = new HashSet<>();
        Set<Long> instrumentIds = new HashSet<>();
        for (UniverseMember member : members) {
            symbols.add(member.symbol());
            instrumentIds.add(member.instrumentId());
        }
        if (symbols.size() != members.size() || instrumentIds.size() != members.size()) {
            throw new IllegalStateException("The latest NIFTY 500 snapshot contains duplicate symbols.");
        }
        return members;
    }

    private Map<Long, List<ExclusionRange>> featureExclusions(UUID snapshotId, LocalDate asOf) {
        Map<Long, List<ExclusionRange>> exclusions = new HashMap<>();
        jdbcTemplate.query("""
                SELECT DISTINCT exclusion.instrument_id,
                       exclusion.exclusion_from, exclusion.exclusion_to
                FROM market_data_feature_exclusion exclusion
                JOIN universe_snapshot_member member
                  ON member.instrument_id = exclusion.instrument_id
                 AND member.snapshot_id = ?
                 AND member.match_status = 'MATCHED'
                WHERE exclusion.exclusion_from <= ?
                ORDER BY exclusion.instrument_id, exclusion.exclusion_from, exclusion.exclusion_to
                """, (RowCallbackHandler) resultSet -> exclusions.computeIfAbsent(
                        resultSet.getLong("instrument_id"), ignored -> new ArrayList<>()).add(
                                new ExclusionRange(
                                        resultSet.getObject("exclusion_from", LocalDate.class),
                                        resultSet.getObject("exclusion_to", LocalDate.class))),
                snapshotId, Date.valueOf(asOf));
        return exclusions;
    }

    private boolean isExcluded(List<ExclusionRange> exclusions, LocalDate date) {
        if (exclusions == null) {
            return false;
        }
        return exclusions.stream().anyMatch(range -> !date.isBefore(range.from()) && !date.isAfter(range.to()));
    }

    private int count(List<FeaturePreview> previews, String status) {
        return (int) previews.stream().filter(item -> status.equals(item.status())).count();
    }

    private record UniverseSnapshot(UUID id, LocalDate observedOn) {
    }

    private record UniverseMember(long instrumentId, String symbol) {
    }

    private record ExclusionRange(LocalDate from, LocalDate to) {
    }

    private final class FeatureAccumulator {
        private final LocalDate asOf;
        private final int memberCount;
        private final List<FeaturePreview> previews = new ArrayList<>();
        private final Set<Long> seenInstrumentIds = new HashSet<>();
        private final List<FeatureCandle> currentCandles = new ArrayList<>();
        private long currentInstrumentId = -1;
        private String currentSymbol;

        private FeatureAccumulator(LocalDate asOf, int memberCount) {
            this.asOf = asOf;
            this.memberCount = memberCount;
        }

        private void accept(long instrumentId, String symbol, FeatureCandle candle) {
            if (currentInstrumentId != -1 && currentInstrumentId != instrumentId) {
                flush();
                if (seenInstrumentIds.contains(instrumentId)) {
                    throw new IllegalStateException("Canonical candle rows are not grouped by instrument.");
                }
            }
            currentInstrumentId = instrumentId;
            currentSymbol = symbol;
            currentCandles.add(candle);
        }

        private List<FeaturePreview> finish(List<UniverseMember> members) {
            flush();
            for (UniverseMember member : members) {
                if (!seenInstrumentIds.contains(member.instrumentId())) {
                    previews.add(previewService.previewFromCanonical(member.symbol(), asOf, List.of()));
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
            seenInstrumentIds.add(currentInstrumentId);
            currentCandles.clear();
            if (previews.size() % 50 == 0 || previews.size() == memberCount) {
                LOGGER.info("Feature universe preview progress: {}/{} instruments", previews.size(), memberCount);
            }
        }
    }
}
