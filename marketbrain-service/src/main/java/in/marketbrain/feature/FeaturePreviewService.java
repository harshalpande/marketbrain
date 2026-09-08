package in.marketbrain.feature;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.sql.Date;
import java.time.LocalDate;
import java.util.List;

@Service
public class FeaturePreviewService {

    private static final int MINIMUM_OBSERVATIONS = 252;
    private static final String FEATURE_SET_VERSION = "TECHNICAL_V1";

    private final JdbcTemplate jdbcTemplate;
    private final TechnicalFeatureCalculator calculator;

    public FeaturePreviewService(JdbcTemplate jdbcTemplate, TechnicalFeatureCalculator calculator) {
        this.jdbcTemplate = jdbcTemplate;
        this.calculator = calculator;
    }

    @Transactional(readOnly = true)
    public FeaturePreview preview(String requestedSymbol, LocalDate asOf) {
        String symbol = normalizeSymbol(requestedSymbol);
        InstrumentMember member = findCurrentMember(symbol);
        List<FeatureCandle> canonical = loadCanonicalCandles(member.instrumentId(), asOf);
        List<FeatureCandle> eligible = canonical.stream().filter(candle -> !candle.excluded()).toList();
        int excluded = canonical.size() - eligible.size();

        if (eligible.isEmpty()) {
            return response("NO_ELIGIBLE_DATA", symbol, asOf, canonical.size(), excluded, null, null,
                    "No governed daily candle is available on or before the requested as-of date.");
        }

        FeatureCandle latest = eligible.getLast();
        if (eligible.size() < MINIMUM_OBSERVATIONS) {
            return response("INSUFFICIENT_HISTORY", symbol, asOf, canonical.size(), excluded, latest, null,
                    "At least 252 eligible daily observations are required; found " + eligible.size() + ".");
        }

        return response("ELIGIBLE", symbol, asOf, canonical.size(), excluded, latest,
                calculator.calculate(eligible),
                "All indicators were computed from governed daily data available at the requested as-of date.");
    }

    private FeaturePreview response(
            String status,
            String symbol,
            LocalDate asOf,
            int canonicalCount,
            int excludedCount,
            FeatureCandle latest,
            FeatureValues values,
            String detail
    ) {
        return new FeaturePreview(
                status,
                symbol,
                FEATURE_SET_VERSION,
                asOf,
                latest == null ? null : latest.tradingDate(),
                canonicalCount,
                canonicalCount - excludedCount,
                excludedCount,
                latest == null ? null : new FeaturePreview.LatestCandle(
                        latest.source(), latest.open(), latest.high(), latest.low(), latest.close(), latest.volume()),
                values,
                true,
                false,
                detail
        );
    }

    private InstrumentMember findCurrentMember(String symbol) {
        List<InstrumentMember> matches = jdbcTemplate.query("""
                WITH latest_snapshot AS (
                    SELECT id
                    FROM universe_snapshot
                    WHERE universe_code = 'NIFTY_500'
                    ORDER BY observed_on DESC, received_at DESC
                    LIMIT 1
                )
                SELECT member.instrument_id, member.source_symbol
                FROM universe_snapshot_member member
                JOIN latest_snapshot snapshot ON snapshot.id = member.snapshot_id
                WHERE member.match_status = 'MATCHED'
                  AND UPPER(member.source_symbol) = ?
                """, (rs, row) -> new InstrumentMember(
                        rs.getLong("instrument_id"), rs.getString("source_symbol")), symbol);
        if (matches.isEmpty()) {
            throw new IllegalArgumentException(
                    "Symbol " + symbol + " is not a matched member of the latest NIFTY 500 snapshot.");
        }
        return matches.getFirst();
    }

    private List<FeatureCandle> loadCanonicalCandles(long instrumentId, LocalDate asOf) {
        return jdbcTemplate.query("""
                WITH ranked AS (
                    SELECT (candle.opened_at AT TIME ZONE 'Asia/Kolkata')::date AS trading_date,
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
                               PARTITION BY (candle.opened_at AT TIME ZONE 'Asia/Kolkata')::date
                               ORDER BY CASE source.code
                                   WHEN 'NSE_BHAVCOPY' THEN 1
                                   WHEN 'UPSTOX' THEN 2
                                   ELSE 3
                               END,
                               candle.received_at DESC,
                               candle.id DESC
                           ) AS source_rank
                    FROM market_candle candle
                    JOIN market_data_source source ON source.id = candle.source_id
                    WHERE candle.instrument_id = ?
                      AND candle.interval_code = 'days:1'
                      AND candle.is_complete = TRUE
                      AND source.code IN ('UPSTOX', 'NSE_BHAVCOPY')
                      AND (candle.opened_at AT TIME ZONE 'Asia/Kolkata')::date <= ?
                )
                SELECT trading_date, source_code, open_price, high_price, low_price,
                       close_price, volume, excluded
                FROM ranked
                WHERE source_rank = 1
                ORDER BY trading_date
                """, (rs, row) -> new FeatureCandle(
                        rs.getObject("trading_date", LocalDate.class),
                        rs.getString("source_code"),
                        rs.getBigDecimal("open_price"),
                        rs.getBigDecimal("high_price"),
                        rs.getBigDecimal("low_price"),
                        rs.getBigDecimal("close_price"),
                        rs.getBigDecimal("volume"),
                        rs.getBoolean("excluded")),
                instrumentId, Date.valueOf(asOf));
    }

    private String normalizeSymbol(String symbol) {
        if (symbol == null || symbol.isBlank()) {
            throw new IllegalArgumentException("A NIFTY 500 symbol is required.");
        }
        String normalized = symbol.trim().toUpperCase();
        if (!normalized.matches("[A-Z0-9&-]{1,64}")) {
            throw new IllegalArgumentException("The symbol contains unsupported characters.");
        }
        return normalized;
    }

    private record InstrumentMember(long instrumentId, String symbol) {
    }
}
