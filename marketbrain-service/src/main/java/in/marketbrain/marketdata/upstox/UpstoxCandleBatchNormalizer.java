package in.marketbrain.marketdata.upstox;

import org.springframework.stereotype.Component;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalTime;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

@Component
public class UpstoxCandleBatchNormalizer {

    private static final ZoneId INDIA = ZoneId.of("Asia/Kolkata");
    private static final BigDecimal ONE_PAISA = new BigDecimal("0.01");
    private static final BigDecimal MAXIMUM_TRANSITION_VOLUME_DIFFERENCE = new BigDecimal("100");
    private static final BigDecimal RELATIVE_VOLUME_DENOMINATOR = new BigDecimal("10000");
    private static final LocalTime MARKET_OPEN = LocalTime.of(9, 15);

    public Result normalize(UpstoxHistoricalRequest request, List<UpstoxCandle> validCandles) {
        if (!"days:1".equals(request.intervalCode())) {
            return new Result(validCandles.stream()
                    .map(candle -> new NormalizedCandle(candle, candle.openedAt()))
                    .toList(), 0, List.of(), List.of(), List.of());
        }

        Map<LocalDate, DailyCandleGroup> candlesByTradingDate = new LinkedHashMap<>();
        List<LocalDate> normalizedTradingDates = new ArrayList<>();
        List<String> normalizationDetails = new ArrayList<>();
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
                normalizationDetails.add(existing.merge(tradingDate, candidate));
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
                List.copyOf(normalizationDetails),
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
            boolean ohlcWithinOnePaisa = withinOnePaisa(minimumProviderOpen, maximumProviderOpen, next.open())
                    && withinOnePaisa(minimumProviderHigh, maximumProviderHigh, next.high())
                    && withinOnePaisa(minimumProviderLow, maximumProviderLow, next.low())
                    && withinOnePaisa(minimumProviderClose, maximumProviderClose, next.close());
            if (sameNumber(current.volume(), next.volume())) {
                return ohlcWithinOnePaisa;
            }
            return exactOhlc(current, next)
                    && isMidnightMarketOpenTransition(normalizedCandle.providerOpenedAt(), candidate.providerOpenedAt())
                    && volumeDifferenceWithinTransitionLimit(current.volume(), next.volume());
        }

        private String merge(LocalDate tradingDate, NormalizedCandle candidate) {
            NormalizedCandle previous = normalizedCandle;
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
                            preferred.candle().close(), preferred.candle().volume()
                    ),
                    preferred.providerOpenedAt()
            );
            NormalizedCandle discarded = preferred == previous ? candidate : previous;
            String reason = sameNumber(previous.candle().volume(), candidate.candle().volume())
                    ? "SAME_VOLUME_OHLC_ROUNDING"
                    : "MIDNIGHT_MARKET_OPEN_VOLUME_VARIANCE";
            return "date=" + tradingDate
                    + ", reason=" + reason
                    + ", retainedTimestamp=" + preferred.providerOpenedAt()
                    + ", retainedVolume=" + preferred.candle().volume()
                    + ", discardedTimestamp=" + discarded.providerOpenedAt()
                    + ", discardedVolume=" + discarded.candle().volume();
        }

        private boolean withinOnePaisa(BigDecimal minimum, BigDecimal maximum, BigDecimal candidate) {
            BigDecimal nextMinimum = minimum.min(candidate);
            BigDecimal nextMaximum = maximum.max(candidate);
            return nextMaximum.subtract(nextMinimum).compareTo(ONE_PAISA) <= 0;
        }

        private boolean exactOhlc(UpstoxCandle first, UpstoxCandle second) {
            return sameNumber(first.open(), second.open())
                    && sameNumber(first.high(), second.high())
                    && sameNumber(first.low(), second.low())
                    && sameNumber(first.close(), second.close());
        }

        private boolean isMidnightMarketOpenTransition(Instant first, Instant second) {
            LocalTime firstTime = first.atZone(INDIA).toLocalTime();
            LocalTime secondTime = second.atZone(INDIA).toLocalTime();
            return (LocalTime.MIDNIGHT.equals(firstTime) && MARKET_OPEN.equals(secondTime))
                    || (MARKET_OPEN.equals(firstTime) && LocalTime.MIDNIGHT.equals(secondTime));
        }

        private boolean volumeDifferenceWithinTransitionLimit(BigDecimal first, BigDecimal second) {
            if (first == null || second == null) {
                return false;
            }
            BigDecimal difference = first.subtract(second).abs();
            BigDecimal maximum = first.abs().max(second.abs());
            return difference.compareTo(MAXIMUM_TRANSITION_VOLUME_DIFFERENCE) <= 0
                    && difference.multiply(RELATIVE_VOLUME_DENOMINATOR).compareTo(maximum) <= 0;
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
            List<String> normalizationDetails,
            List<LocalDate> conflictingTradingDates
    ) {
        public boolean hasConflicts() {
            return !conflictingTradingDates.isEmpty();
        }
    }
}
