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

    public Result normalize(UpstoxHistoricalRequest request, List<UpstoxCandle> validCandles) {
        if (!"days:1".equals(request.intervalCode())) {
            return new Result(validCandles.stream()
                    .map(candle -> new NormalizedCandle(candle, candle.openedAt()))
                    .toList(), 0, List.of());
        }

        Map<LocalDate, NormalizedCandle> candlesByTradingDate = new LinkedHashMap<>();
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
            NormalizedCandle existing = candlesByTradingDate.get(tradingDate);
            if (existing == null) {
                candlesByTradingDate.put(tradingDate, candidate);
            } else if (sameMarketValues(existing.candle(), candidate.candle())) {
                collapsedDuplicates++;
                if (candidate.providerOpenedAt().isBefore(existing.providerOpenedAt())) {
                    candlesByTradingDate.put(tradingDate, candidate);
                }
            } else if (!conflictingTradingDates.contains(tradingDate)) {
                conflictingTradingDates.add(tradingDate);
            }
        }

        return new Result(List.copyOf(candlesByTradingDate.values()), collapsedDuplicates,
                List.copyOf(conflictingTradingDates));
    }

    private boolean sameMarketValues(UpstoxCandle first, UpstoxCandle second) {
        return sameNumber(first.open(), second.open())
                && sameNumber(first.high(), second.high())
                && sameNumber(first.low(), second.low())
                && sameNumber(first.close(), second.close())
                && sameNumber(first.volume(), second.volume());
    }

    private boolean sameNumber(BigDecimal first, BigDecimal second) {
        if (first == null || second == null) {
            return first == second;
        }
        return first.compareTo(second) == 0;
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
