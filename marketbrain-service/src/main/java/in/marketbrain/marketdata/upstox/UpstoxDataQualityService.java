package in.marketbrain.marketdata.upstox;

import in.marketbrain.configuration.MarketBrainProperties;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;

@Service
public class UpstoxDataQualityService {

    private static final Duration FUTURE_TOLERANCE = Duration.ofMinutes(5);

    private final Clock clock;
    private final int maximumDataAgeSeconds;

    @Autowired
    public UpstoxDataQualityService(MarketBrainProperties properties) {
        this(properties, Clock.systemUTC());
    }

    UpstoxDataQualityService(MarketBrainProperties properties, Clock clock) {
        this.clock = clock;
        this.maximumDataAgeSeconds = properties.signal().maximumDataAgeSeconds();
    }

    public MarketDataQuality assess(UpstoxQuote quote) {
        if (quote == null || quote.lastPrice() == null || quote.lastPrice().signum() <= 0) {
            return new MarketDataQuality("INVALID", -1, "Last price is missing or non-positive.");
        }
        Instant sourceTime = quote.lastTradeAt() != null ? quote.lastTradeAt() : quote.providerPublishedAt();
        if (sourceTime == null) {
            return new MarketDataQuality("INVALID", -1, "Provider timestamp is absent.");
        }
        Instant now = clock.instant();
        if (sourceTime.isAfter(now.plus(FUTURE_TOLERANCE))) {
            return new MarketDataQuality("INVALID", -1, "Provider timestamp is implausibly in the future.");
        }
        long ageSeconds = Math.max(0, Duration.between(sourceTime, now).toSeconds());
        if (ageSeconds > maximumDataAgeSeconds) {
            return new MarketDataQuality("STALE", ageSeconds,
                    "Quote is retained for audit but cannot drive an actionable signal.");
        }
        return new MarketDataQuality("FRESH", ageSeconds, "Quote is inside the configured freshness window.");
    }

    public boolean validCandle(UpstoxCandle candle) {
        if (candle == null || candle.openedAt() == null || candle.open() == null || candle.high() == null
                || candle.low() == null || candle.close() == null) {
            return false;
        }
        if (candle.open().signum() <= 0 || candle.high().signum() <= 0
                || candle.low().signum() <= 0 || candle.close().signum() <= 0) {
            return false;
        }
        if (candle.volume() != null && candle.volume().signum() < 0) {
            return false;
        }
        return candle.low().compareTo(candle.open()) <= 0
                && candle.low().compareTo(candle.close()) <= 0
                && candle.high().compareTo(candle.open()) >= 0
                && candle.high().compareTo(candle.close()) >= 0;
    }
}
