package in.marketbrain.training;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowCallbackHandler;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.sql.Date;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;

@Service
public class TradableEquityTrainingUniversePreviewService {

    public static final String CONTRACT_VERSION = "TRADEABLE_EQUITY_TRAINING_UNIVERSE_V1";
    public static final String UNIVERSE_CODE = "AVAILABLE_NSE_EQUITY_DATA";
    private static final Logger LOGGER =
            LoggerFactory.getLogger(TradableEquityTrainingUniversePreviewService.class);
    private static final int DEFAULT_MINIMUM_OBSERVATIONS = 252;
    private static final int MAXIMUM_MINIMUM_OBSERVATIONS = 5_000;
    private static final List<String> ALLOWED_SOURCE_CODES = List.of("NSE_BHAVCOPY", "UPSTOX");
    private static final String PROVIDER_PREFERENCE = "NSE_BHAVCOPY_THEN_UPSTOX";

    private static final String TOTAL_INSTRUMENT_COUNT_SQL = """
            SELECT COUNT(*)
            FROM instrument
            """;

    private static final String CANDIDATE_UNIVERSE_SQL = """
            WITH active_instrument AS (
                SELECT id AS instrument_id, symbol, isin, display_name
                FROM instrument
                WHERE exchange = 'NSE'
                  AND active = TRUE
            ), ranked AS (
                SELECT active_instrument.instrument_id,
                       active_instrument.symbol,
                       active_instrument.isin,
                       active_instrument.display_name,
                       (candle.opened_at AT TIME ZONE 'Asia/Kolkata')::date AS trading_date,
                       source.code AS source_code,
                       EXISTS (
                           SELECT 1
                           FROM market_data_feature_exclusion exclusion
                           WHERE exclusion.instrument_id = active_instrument.instrument_id
                             AND (candle.opened_at AT TIME ZONE 'Asia/Kolkata')::date
                                 BETWEEN exclusion.exclusion_from AND exclusion.exclusion_to
                       ) AS excluded,
                       ROW_NUMBER() OVER (
                           PARTITION BY active_instrument.instrument_id,
                                        (candle.opened_at AT TIME ZONE 'Asia/Kolkata')::date
                           ORDER BY CASE source.code
                               WHEN 'NSE_BHAVCOPY' THEN 1
                               WHEN 'UPSTOX' THEN 2
                               ELSE 3
                           END,
                           candle.received_at DESC,
                           candle.id DESC
                       ) AS source_rank
                FROM active_instrument
                LEFT JOIN market_candle candle
                  ON candle.instrument_id = active_instrument.instrument_id
                 AND candle.interval_code = 'days:1'
                 AND candle.is_complete = TRUE
                 AND (candle.opened_at AT TIME ZONE 'Asia/Kolkata')::date <= ?
                 AND candle.source_id IN (
                     SELECT id
                     FROM market_data_source
                     WHERE code IN ('NSE_BHAVCOPY', 'UPSTOX')
                 )
                LEFT JOIN market_data_source source ON source.id = candle.source_id
            ), canonical AS (
                SELECT instrument_id, symbol, isin, display_name, trading_date, source_code, excluded
                FROM ranked
                WHERE source_rank = 1
            ), classified AS (
                SELECT instrument_id,
                       symbol,
                       isin,
                       display_name,
                       MIN(trading_date) AS first_candle_date,
                       MAX(trading_date) AS latest_candle_date,
                       COUNT(trading_date)::integer AS canonical_observation_count,
                       COALESCE(SUM(CASE WHEN trading_date IS NOT NULL AND excluded = FALSE
                           THEN 1 ELSE 0 END), 0)::integer AS eligible_observation_count,
                       COALESCE(SUM(CASE WHEN trading_date IS NOT NULL AND excluded = TRUE
                           THEN 1 ELSE 0 END), 0)::integer AS excluded_observation_count,
                       (ARRAY_AGG(source_code ORDER BY trading_date DESC)
                           FILTER (WHERE trading_date IS NOT NULL))[1] AS latest_source
                FROM canonical
                GROUP BY instrument_id, symbol, isin, display_name
            )
            SELECT instrument_id,
                   symbol,
                   isin,
                   display_name,
                   CASE
                       WHEN canonical_observation_count = 0 THEN 'NO_ELIGIBLE_DATA'
                       WHEN latest_candle_date < ? THEN 'STALE'
                       WHEN eligible_observation_count < ? THEN 'INSUFFICIENT_HISTORY'
                       ELSE 'ELIGIBLE'
                   END AS status,
                   first_candle_date,
                   latest_candle_date,
                   canonical_observation_count,
                   eligible_observation_count,
                   excluded_observation_count,
                   latest_source
            FROM classified
            ORDER BY symbol
            """;

    private final JdbcTemplate jdbcTemplate;
    private final TradableEquityTrainingUniverseManifestHasher manifestHasher;

    public TradableEquityTrainingUniversePreviewService(
            JdbcTemplate jdbcTemplate,
            TradableEquityTrainingUniverseManifestHasher manifestHasher
    ) {
        this.jdbcTemplate = jdbcTemplate;
        this.manifestHasher = manifestHasher;
    }

    @Transactional(readOnly = true, timeout = 1_800)
    public TradableEquityTrainingUniversePreview preview(LocalDate asOf) {
        return preview(asOf, DEFAULT_MINIMUM_OBSERVATIONS);
    }

    @Transactional(readOnly = true, timeout = 1_800)
    public TradableEquityTrainingUniversePreview preview(
            LocalDate asOf,
            int minimumEligibleObservations
    ) {
        validateRequest(asOf, minimumEligibleObservations);
        long startedAt = System.nanoTime();
        Integer totalInstrumentCount = jdbcTemplate.queryForObject(
                TOTAL_INSTRUMENT_COUNT_SQL, Integer.class);
        List<TradableEquityTrainingUniverseItem> instruments =
                loadCandidateUniverse(asOf, minimumEligibleObservations);
        if (instruments.isEmpty()) {
            throw new IllegalStateException("No active NSE instruments are available.");
        }

        int eligible = count(instruments, "ELIGIBLE");
        int insufficient = count(instruments, "INSUFFICIENT_HISTORY");
        int stale = count(instruments, "STALE");
        int noData = count(instruments, "NO_ELIGIBLE_DATA");
        if (eligible + insufficient + stale + noData != instruments.size()) {
            throw new IllegalStateException("The candidate universe contains an unsupported status.");
        }

        int canonicalObservations = instruments.stream()
                .mapToInt(TradableEquityTrainingUniverseItem::canonicalObservationCount).sum();
        int eligibleObservations = instruments.stream()
                .mapToInt(TradableEquityTrainingUniverseItem::eligibleObservationCount).sum();
        int excludedObservations = instruments.stream()
                .mapToInt(TradableEquityTrainingUniverseItem::excludedObservationCount).sum();
        LocalDate earliestObservation = instruments.stream()
                .map(TradableEquityTrainingUniverseItem::firstCandleDate)
                .filter(value -> value != null)
                .min(LocalDate::compareTo)
                .orElse(null);
        LocalDate latestObservation = instruments.stream()
                .map(TradableEquityTrainingUniverseItem::latestCandleDate)
                .filter(value -> value != null)
                .max(LocalDate::compareTo)
                .orElse(null);
        List<String> failedCheckpoints = failedCheckpoints(eligible, latestObservation, asOf);
        String manifestHash = manifestHasher.hash(
                CONTRACT_VERSION, asOf, minimumEligibleObservations, instruments);
        long elapsedSeconds = (System.nanoTime() - startedAt) / 1_000_000_000L;
        LOGGER.info("Tradable equity training universe preview completed: asOf={}, instruments={}, "
                        + "eligible={}, insufficientHistory={}, stale={}, noData={}, elapsedSeconds={}",
                asOf, instruments.size(), eligible, insufficient, stale, noData, elapsedSeconds);

        return new TradableEquityTrainingUniversePreview(
                failedCheckpoints.isEmpty() ? "REVIEW_REQUIRED" : "SOURCE_REVIEW_REQUIRED",
                CONTRACT_VERSION,
                UNIVERSE_CODE,
                "Currently active NSE equity instruments with persisted governed daily candles.",
                asOf,
                minimumEligibleObservations,
                ALLOWED_SOURCE_CODES,
                PROVIDER_PREFERENCE,
                totalInstrumentCount == null ? 0 : totalInstrumentCount,
                instruments.size(),
                eligible,
                insufficient,
                stale,
                noData,
                canonicalObservations,
                eligibleObservations,
                excludedObservations,
                earliestObservation,
                latestObservation,
                true,
                false,
                true,
                eligible > 0,
                false,
                true,
                false,
                0,
                0,
                0,
                manifestHash,
                failedCheckpoints,
                instruments,
                "This is a governed fallback candidate universe. It can support prototype training work, "
                        + "but it is not historical NIFTY 500 membership and still carries current-universe "
                        + "survivorship risk until delisted historical equities are added."
        );
    }

    private List<TradableEquityTrainingUniverseItem> loadCandidateUniverse(
            LocalDate asOf,
            int minimumEligibleObservations
    ) {
        List<TradableEquityTrainingUniverseItem> instruments = new ArrayList<>();
        jdbcTemplate.query(connection -> {
            var statement = connection.prepareStatement(CANDIDATE_UNIVERSE_SQL);
            statement.setDate(1, Date.valueOf(asOf));
            statement.setDate(2, Date.valueOf(asOf));
            statement.setInt(3, minimumEligibleObservations);
            statement.setFetchSize(1_000);
            statement.setQueryTimeout(600);
            return statement;
        }, (RowCallbackHandler) resultSet -> {
            String status = resultSet.getString("status");
            instruments.add(new TradableEquityTrainingUniverseItem(
                    resultSet.getLong("instrument_id"),
                    resultSet.getString("symbol"),
                    resultSet.getString("isin"),
                    resultSet.getString("display_name"),
                    status,
                    resultSet.getObject("first_candle_date", LocalDate.class),
                    resultSet.getObject("latest_candle_date", LocalDate.class),
                    resultSet.getInt("canonical_observation_count"),
                    resultSet.getInt("eligible_observation_count"),
                    resultSet.getInt("excluded_observation_count"),
                    resultSet.getString("latest_source"),
                    detail(status, minimumEligibleObservations)
            ));
        });
        return List.copyOf(instruments);
    }

    private void validateRequest(LocalDate asOf, int minimumEligibleObservations) {
        if (asOf == null) {
            throw new IllegalArgumentException("asOf is required.");
        }
        if (minimumEligibleObservations < 1
                || minimumEligibleObservations > MAXIMUM_MINIMUM_OBSERVATIONS) {
            throw new IllegalArgumentException(
                    "minimumEligibleObservations must be between 1 and 5000.");
        }
    }

    private int count(List<TradableEquityTrainingUniverseItem> instruments, String status) {
        return (int) instruments.stream()
                .filter(instrument -> status.equals(instrument.status()))
                .count();
    }

    private List<String> failedCheckpoints(int eligible, LocalDate latestObservation, LocalDate asOf) {
        List<String> failed = new ArrayList<>();
        if (eligible == 0) {
            failed.add("NO_ELIGIBLE_INSTRUMENTS");
        }
        if (latestObservation == null || latestObservation.isBefore(asOf)) {
            failed.add("TARGET_DATE_COVERAGE");
        }
        return List.copyOf(failed);
    }

    private String detail(String status, int minimumEligibleObservations) {
        return switch (status) {
            case "ELIGIBLE" -> "The instrument has a target-date candle and enough non-excluded history.";
            case "INSUFFICIENT_HISTORY" ->
                    "The instrument has fewer than " + minimumEligibleObservations
                            + " non-excluded daily observations.";
            case "STALE" -> "The latest governed candle is older than the requested as-of date.";
            case "NO_ELIGIBLE_DATA" -> "No governed daily candle is available for this instrument.";
            default -> "The instrument status is unsupported.";
        };
    }
}
