package in.marketbrain.marketdata.upstox;

import org.springframework.stereotype.Component;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

@Component
public class UpstoxCandleBatchNormalizer {

    private static final ZoneId INDIA = ZoneId.of("Asia/Kolkata");
    private static final BigDecimal ONE_PAISA = new BigDecimal("0.01");

    public Result normalize(UpstoxHistoricalRequest request, List<UpstoxCandle> validCandles) {
        if (!"days:1".equals(request.intervalCode())) {
            return new Result(validCandles.stream()
                    .map(candle -> new NormalizedCandle(candle, candle.openedAt()))
                    .toList(), 0, List.of());
        }

        Map<LocalDate, DailyCandleGroup> candlesByTradingDate = new LinkedHashMap<>();
        List<LocalDate> conflictingTradingDates = new ArrayList<>();
        int collapsedDuplicates = 0;

        for (UpstoxCandle providerCandle : validCandles) {
            LocalDate tradingDate = providerCandle.openedAt().atZone(INDIA).toLocalDate();
            NormalizedCandle candidate = new NormalizedCandle(
                    new UpstoxCandle(
                            tradingDate.atStartOfDay(INDIA).toInstant(),
                            providerCandle.open(),
                            providerCandle.high(),
                            providerCandle.low(),
                            providerCandle.close(),
                            providerCandle.volume()
                    ),
                    providerCandle.openedAt()
            );
            DailyCandleGroup existing = candlesByTradingDate.get(tradingDate);
            if (existing == null) {
                candlesByTradingDate.put(tradingDate, new DailyCandleGroup(candidate));
            } else if (existing.canMerge(candidate)) {
                collapsedDuplicates++;
                existing.merge(candidate);
            } else if (!conflictingTradingDates.contains(tradingDate)) {
                conflictingTradingDates.add(tradingDate);
            }
        }

        return new Result(candlesByTradingDate.values().stream()
                .map(DailyCandleGroup::normalizedCandle)
                .toList(), collapsedDuplicates,
                List.copyOf(conflictingTradingDates));
    }

    private boolean sameNumber(BigDecimal first, BigDecimal second) {
        if (first == null || second == null) {
            return first == second;
        }
        return first.compareTo(second) == 0;
    }

    private final class DailyCandleGroup {

        private NormalizedCandle normalizedCandle;
        private BigDecimal minimumProviderHigh;
        private BigDecimal maximumProviderHigh;
        private BigDecimal minimumProviderLow;
        private BigDecimal maximumProviderLow;

        private DailyCandleGroup(NormalizedCandle candle) {
            this.normalizedCandle = candle;
            this.minimumProviderHigh = candle.candle().high();
            this.maximumProviderHigh = candle.candle().high();
            this.minimumProviderLow = candle.candle().low();
            this.maximumProviderLow = candle.candle().low();
        }

        private boolean canMerge(NormalizedCandle candidate) {
            UpstoxCandle current = normalizedCandle.candle();
            UpstoxCandle next = candidate.candle();
            BigDecimal nextMinimumHigh = minimumProviderHigh.min(next.high());
            BigDecimal nextMaximumHigh = maximumProviderHigh.max(next.high());
            BigDecimal nextMinimumLow = minimumProviderLow.min(next.low());
            BigDecimal nextMaximumLow = maximumProviderLow.max(next.low());
            return sameNumber(current.open(), next.open())
                    && sameNumber(current.close(), next.close())
                    && sameNumber(current.volume(), next.volume())
                    && nextMaximumHigh.subtract(nextMinimumHigh).compareTo(ONE_PAISA) <= 0
                    && nextMaximumLow.subtract(nextMinimumLow).compareTo(ONE_PAISA) <= 0;
        }

        private void merge(NormalizedCandle candidate) {
            UpstoxCandle current = normalizedCandle.candle();
            UpstoxCandle next = candidate.candle();
            minimumProviderHigh = minimumProviderHigh.min(next.high());
            maximumProviderHigh = maximumProviderHigh.max(next.high());
            minimumProviderLow = minimumProviderLow.min(next.low());
            maximumProviderLow = maximumProviderLow.max(next.low());
            Instant providerOpenedAt = normalizedCandle.providerOpenedAt().isBefore(candidate.providerOpenedAt())
                    ? normalizedCandle.providerOpenedAt() : candidate.providerOpenedAt();
            normalizedCandle = new NormalizedCandle(
                    new UpstoxCandle(
                            current.openedAt(), current.open(), maximumProviderHigh, minimumProviderLow,
                            current.close(), current.volume()
                    ),
                    providerOpenedAt
            );
        }

        private NormalizedCandle normalizedCandle() {
            return normalizedCandle;
        }
    }

    public record NormalizedCandle(UpstoxCandle candle, Instant providerOpenedAt) {
    }

    public record Result(
            List<NormalizedCandle> candles,
            int collapsedDuplicates,
            List<LocalDate> conflictingTradingDates
    ) {
        public boolean hasConflicts() {
            return !conflictingTradingDates.isEmpty();
        }
    }
}
