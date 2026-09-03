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
                    .toList(), 0, List.of(), List.of());
        }

        Map<LocalDate, DailyCandleGroup> candlesByTradingDate = new LinkedHashMap<>();
        List<LocalDate> normalizedTradingDates = new ArrayList<>();
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
                if (!normalizedTradingDates.contains(tradingDate)) {
                    normalizedTradingDates.add(tradingDate);
                }
            } else if (!conflictingTradingDates.contains(tradingDate)) {
                conflictingTradingDates.add(tradingDate);
            }
        }

        return new Result(candlesByTradingDate.values().stream()
                .map(DailyCandleGroup::normalizedCandle)
                .toList(), collapsedDuplicates, List.copyOf(normalizedTradingDates),
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
        private BigDecimal minimumProviderOpen;
        private BigDecimal maximumProviderOpen;
        private BigDecimal minimumProviderHigh;
        private BigDecimal maximumProviderHigh;
        private BigDecimal minimumProviderLow;
        private BigDecimal maximumProviderLow;
        private BigDecimal minimumProviderClose;
        private BigDecimal maximumProviderClose;

        private DailyCandleGroup(NormalizedCandle candle) {
            this.normalizedCandle = candle;
            this.minimumProviderOpen = candle.candle().open();
            this.maximumProviderOpen = candle.candle().open();
            this.minimumProviderHigh = candle.candle().high();
            this.maximumProviderHigh = candle.candle().high();
            this.minimumProviderLow = candle.candle().low();
            this.maximumProviderLow = candle.candle().low();
            this.minimumProviderClose = candle.candle().close();
            this.maximumProviderClose = candle.candle().close();
        }

        private boolean canMerge(NormalizedCandle candidate) {
            UpstoxCandle current = normalizedCandle.candle();
            UpstoxCandle next = candidate.candle();
            return sameNumber(current.volume(), next.volume())
                    && withinOnePaisa(minimumProviderOpen, maximumProviderOpen, next.open())
                    && withinOnePaisa(minimumProviderHigh, maximumProviderHigh, next.high())
                    && withinOnePaisa(minimumProviderLow, maximumProviderLow, next.low())
                    && withinOnePaisa(minimumProviderClose, maximumProviderClose, next.close());
        }

        private void merge(NormalizedCandle candidate) {
            UpstoxCandle current = normalizedCandle.candle();
            UpstoxCandle next = candidate.candle();
            minimumProviderOpen = minimumProviderOpen.min(next.open());
            maximumProviderOpen = maximumProviderOpen.max(next.open());
            minimumProviderHigh = minimumProviderHigh.min(next.high());
            maximumProviderHigh = maximumProviderHigh.max(next.high());
            minimumProviderLow = minimumProviderLow.min(next.low());
            maximumProviderLow = maximumProviderLow.max(next.low());
            minimumProviderClose = minimumProviderClose.min(next.close());
            maximumProviderClose = maximumProviderClose.max(next.close());
            NormalizedCandle preferred = normalizedCandle.providerOpenedAt().isAfter(candidate.providerOpenedAt())
                    ? normalizedCandle : candidate;
            normalizedCandle = new NormalizedCandle(
                    new UpstoxCandle(
                            current.openedAt(), preferred.candle().open(), maximumProviderHigh, minimumProviderLow,
                            preferred.candle().close(), current.volume()
                    ),
                    preferred.providerOpenedAt()
            );
        }

        private boolean withinOnePaisa(BigDecimal minimum, BigDecimal maximum, BigDecimal candidate) {
            BigDecimal nextMinimum = minimum.min(candidate);
            BigDecimal nextMaximum = maximum.max(candidate);
            return nextMaximum.subtract(nextMinimum).compareTo(ONE_PAISA) <= 0;
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
            List<LocalDate> normalizedTradingDates,
            List<LocalDate> conflictingTradingDates
    ) {
        public boolean hasConflicts() {
            return !conflictingTradingDates.isEmpty();
        }
    }
}
