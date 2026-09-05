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
    private static final String REVIEWED_BEML_INSTRUMENT_KEY = "NSE_EQ|INE258A01024";
    private static final LocalDate REVIEWED_BEML_TRADING_DATE = LocalDate.of(2015, 12, 31);
    private static final BigDecimal REVIEWED_BEML_OPEN = new BigDecimal("640.60");
    private static final BigDecimal REVIEWED_BEML_HIGH = new BigDecimal("645.50");
    private static final BigDecimal REVIEWED_BEML_LOW = new BigDecimal("633.00");
    private static final BigDecimal REVIEWED_BEML_MIDNIGHT_CLOSE = new BigDecimal("640.50");
    private static final BigDecimal REVIEWED_BEML_MARKET_OPEN_CLOSE = new BigDecimal("640.60");
    private static final BigDecimal REVIEWED_BEML_VOLUME = new BigDecimal("392016");
    private static final String REVIEWED_BEML_BHAVCOPY_URL =
            "https://archives.nseindia.com/content/historical/EQUITIES/2015/DEC/cm31DEC2015bhav.csv.zip";
    private static final String REVIEWED_BEML_SPLIT_URL =
            "https://nsearchives.nseindia.com/corporate/BEML_29092025163552_RECORDDATESIGNED29092025.pdf";
    private static final String REVIEWED_LALPATHLAB_INSTRUMENT_KEY = "NSE_EQ|INE600L01024";
    private static final LocalDate REVIEWED_LALPATHLAB_TRADING_DATE = LocalDate.of(2015, 12, 31);
    private static final BigDecimal REVIEWED_LALPATHLAB_OPEN = new BigDecimal("405.00");
    private static final BigDecimal REVIEWED_LALPATHLAB_MIDNIGHT_HIGH = new BigDecimal("409.80");
    private static final BigDecimal REVIEWED_LALPATHLAB_MIDNIGHT_LOW = new BigDecimal("392.50");
    private static final BigDecimal REVIEWED_LALPATHLAB_MARKET_OPEN_HIGH = new BigDecimal("409.60");
    private static final BigDecimal REVIEWED_LALPATHLAB_MARKET_OPEN_LOW = new BigDecimal("393.60");
    private static final BigDecimal REVIEWED_LALPATHLAB_CLOSE = new BigDecimal("402.20");
    private static final BigDecimal REVIEWED_LALPATHLAB_MIDNIGHT_VOLUME = new BigDecimal("2823182");
    private static final BigDecimal REVIEWED_LALPATHLAB_MARKET_OPEN_VOLUME = new BigDecimal("2823162");
    private static final String REVIEWED_LALPATHLAB_BHAVCOPY_URL =
            "https://archives.nseindia.com/content/historical/EQUITIES/2015/DEC/cm31DEC2015bhav.csv.zip";
    private static final String REVIEWED_LALPATHLAB_BONUS_URL =
            "https://nsearchives.nseindia.com/corporate/LALPATHLAB_22122025091806_IntimationAllotment.pdf";

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
            } else if (existing.canMerge(request, tradingDate, candidate)) {
                collapsedDuplicates++;
                normalizationDetails.add(existing.merge(request, tradingDate, candidate));
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

        private boolean canMerge(
                UpstoxHistoricalRequest request,
                LocalDate tradingDate,
                NormalizedCandle candidate
        ) {
            UpstoxCandle current = normalizedCandle.candle();
            UpstoxCandle next = candidate.candle();
            boolean ohlcWithinOnePaisa = withinOnePaisa(minimumProviderOpen, maximumProviderOpen, next.open())
                    && withinOnePaisa(minimumProviderHigh, maximumProviderHigh, next.high())
                    && withinOnePaisa(minimumProviderLow, maximumProviderLow, next.low())
                    && withinOnePaisa(minimumProviderClose, maximumProviderClose, next.close());
            if (isReviewedLalPathLabBonusAdjustedVariance(request, tradingDate, candidate)) {
                return true;
            }
            if (sameNumber(current.volume(), next.volume())) {
                return ohlcWithinOnePaisa
                        || isReviewedBemlSplitAdjustmentRounding(request, tradingDate, candidate);
            }
            return exactOhlc(current, next)
                    && isMidnightMarketOpenTransition(normalizedCandle.providerOpenedAt(), candidate.providerOpenedAt())
                    && volumeDifferenceWithinTransitionLimit(current.volume(), next.volume());
        }

        private String merge(
                UpstoxHistoricalRequest request,
                LocalDate tradingDate,
                NormalizedCandle candidate
        ) {
            NormalizedCandle previous = normalizedCandle;
            UpstoxCandle current = normalizedCandle.candle();
            UpstoxCandle next = candidate.candle();
            boolean reviewedBemlRounding = isReviewedBemlSplitAdjustmentRounding(
                    request, tradingDate, candidate);
            boolean reviewedLalPathLabVariance = isReviewedLalPathLabBonusAdjustedVariance(
                    request, tradingDate, candidate);
            minimumProviderOpen = minimumProviderOpen.min(next.open());
            maximumProviderOpen = maximumProviderOpen.max(next.open());
            minimumProviderHigh = minimumProviderHigh.min(next.high());
            maximumProviderHigh = maximumProviderHigh.max(next.high());
            minimumProviderLow = minimumProviderLow.min(next.low());
            maximumProviderLow = maximumProviderLow.max(next.low());
            minimumProviderClose = minimumProviderClose.min(next.close());
            maximumProviderClose = maximumProviderClose.max(next.close());
            NormalizedCandle preferred = reviewedLalPathLabVariance
                    ? reviewedLalPathLabMidnight(normalizedCandle, candidate)
                    : normalizedCandle.providerOpenedAt().isAfter(candidate.providerOpenedAt())
                    ? normalizedCandle : candidate;
            normalizedCandle = new NormalizedCandle(
                    new UpstoxCandle(
                            current.openedAt(), preferred.candle().open(), maximumProviderHigh, minimumProviderLow,
                            preferred.candle().close(), preferred.candle().volume()
                    ),
                    preferred.providerOpenedAt()
            );
            NormalizedCandle discarded = preferred == previous ? candidate : previous;
            String reason = reviewedBemlRounding
                    ? "REVIEWED_SPLIT_ADJUSTMENT_CLOSE_ROUNDING"
                    : reviewedLalPathLabVariance
                    ? "REVIEWED_BONUS_ADJUSTED_OHLC_VARIANCE"
                    : sameNumber(previous.candle().volume(), candidate.candle().volume())
                    ? "SAME_VOLUME_OHLC_ROUNDING"
                    : "MIDNIGHT_MARKET_OPEN_VOLUME_VARIANCE";
            return "date=" + tradingDate
                    + ", reason=" + reason
                    + ", retainedTimestamp=" + preferred.providerOpenedAt()
                    + ", retainedOhlcv=" + ohlcv(preferred.candle())
                    + ", discardedTimestamp=" + discarded.providerOpenedAt()
                    + ", discardedOhlcv=" + ohlcv(discarded.candle())
                    + (reviewedBemlRounding
                    ? ", officialBhavcopyUrl=" + REVIEWED_BEML_BHAVCOPY_URL
                    + ", corporateActionUrl=" + REVIEWED_BEML_SPLIT_URL
                    + ", officialRawOhlcv=[1281.15,1290.95,1266.1,1281.1,196008]"
                    + ", reviewedAdjustment=1:2"
                    : reviewedLalPathLabVariance
                    ? ", officialBhavcopyUrl=" + REVIEWED_LALPATHLAB_BHAVCOPY_URL
                    + ", corporateActionUrl=" + REVIEWED_LALPATHLAB_BONUS_URL
                    + ", officialRawOhlcv=[810,819.7,785,804.45,1411591]"
                    + ", officialAdjustedOhlcv=[405,409.85,392.5,402.225,2823182]"
                    + ", reviewedBonus=1:1, priceDivisor=2, volumeMultiplier=2"
                    + ", providerVolumeDifference=20"
                    : "");
        }

        private boolean isReviewedLalPathLabBonusAdjustedVariance(
                UpstoxHistoricalRequest request,
                LocalDate tradingDate,
                NormalizedCandle candidate
        ) {
            if (!REVIEWED_LALPATHLAB_INSTRUMENT_KEY.equals(request.instrumentKey())
                    || !REVIEWED_LALPATHLAB_TRADING_DATE.equals(tradingDate)
                    || !isMidnightMarketOpenTransition(normalizedCandle.providerOpenedAt(), candidate.providerOpenedAt())) {
                return false;
            }
            return (isReviewedLalPathLabMidnight(normalizedCandle)
                    && isReviewedLalPathLabMarketOpen(candidate))
                    || (isReviewedLalPathLabMidnight(candidate)
                    && isReviewedLalPathLabMarketOpen(normalizedCandle));
        }

        private boolean isReviewedLalPathLabMidnight(NormalizedCandle candidate) {
            UpstoxCandle candle = candidate.candle();
            return LocalTime.MIDNIGHT.equals(candidate.providerOpenedAt().atZone(INDIA).toLocalTime())
                    && sameNumber(candle.open(), REVIEWED_LALPATHLAB_OPEN)
                    && sameNumber(candle.high(), REVIEWED_LALPATHLAB_MIDNIGHT_HIGH)
                    && sameNumber(candle.low(), REVIEWED_LALPATHLAB_MIDNIGHT_LOW)
                    && sameNumber(candle.close(), REVIEWED_LALPATHLAB_CLOSE)
                    && sameNumber(candle.volume(), REVIEWED_LALPATHLAB_MIDNIGHT_VOLUME);
        }

        private boolean isReviewedLalPathLabMarketOpen(NormalizedCandle candidate) {
            UpstoxCandle candle = candidate.candle();
            return MARKET_OPEN.equals(candidate.providerOpenedAt().atZone(INDIA).toLocalTime())
                    && sameNumber(candle.open(), REVIEWED_LALPATHLAB_OPEN)
                    && sameNumber(candle.high(), REVIEWED_LALPATHLAB_MARKET_OPEN_HIGH)
                    && sameNumber(candle.low(), REVIEWED_LALPATHLAB_MARKET_OPEN_LOW)
                    && sameNumber(candle.close(), REVIEWED_LALPATHLAB_CLOSE)
                    && sameNumber(candle.volume(), REVIEWED_LALPATHLAB_MARKET_OPEN_VOLUME);
        }

        private NormalizedCandle reviewedLalPathLabMidnight(
                NormalizedCandle first,
                NormalizedCandle second
        ) {
            return isReviewedLalPathLabMidnight(first) ? first : second;
        }

        private boolean isReviewedBemlSplitAdjustmentRounding(
                UpstoxHistoricalRequest request,
                LocalDate tradingDate,
                NormalizedCandle candidate
        ) {
            UpstoxCandle current = normalizedCandle.candle();
            UpstoxCandle next = candidate.candle();
            if (!REVIEWED_BEML_INSTRUMENT_KEY.equals(request.instrumentKey())
                    || !REVIEWED_BEML_TRADING_DATE.equals(tradingDate)
                    || !isMidnightMarketOpenTransition(normalizedCandle.providerOpenedAt(), candidate.providerOpenedAt())
                    || !sameNumber(current.open(), REVIEWED_BEML_OPEN)
                    || !sameNumber(next.open(), REVIEWED_BEML_OPEN)
                    || !sameNumber(current.high(), REVIEWED_BEML_HIGH)
                    || !sameNumber(next.high(), REVIEWED_BEML_HIGH)
                    || !sameNumber(current.low(), REVIEWED_BEML_LOW)
                    || !sameNumber(next.low(), REVIEWED_BEML_LOW)
                    || !sameNumber(current.volume(), REVIEWED_BEML_VOLUME)
                    || !sameNumber(next.volume(), REVIEWED_BEML_VOLUME)) {
                return false;
            }
            return (sameNumber(current.close(), REVIEWED_BEML_MIDNIGHT_CLOSE)
                    && sameNumber(next.close(), REVIEWED_BEML_MARKET_OPEN_CLOSE))
                    || (sameNumber(next.close(), REVIEWED_BEML_MIDNIGHT_CLOSE)
                    && sameNumber(current.close(), REVIEWED_BEML_MARKET_OPEN_CLOSE));
        }

        private String ohlcv(UpstoxCandle candle) {
            return "[" + candle.open() + "," + candle.high() + "," + candle.low() + ","
                    + candle.close() + "," + candle.volume() + "]";
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
