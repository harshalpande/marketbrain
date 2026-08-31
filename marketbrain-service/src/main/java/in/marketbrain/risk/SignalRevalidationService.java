package in.marketbrain.risk;

import org.springframework.stereotype.Service;

import java.time.Duration;

/**
 * Prevents an approval from creating a paper fill with stale data or an invalid
 * BUY price. A protective SELL may still be valid after an adverse price move.
 */
@Service
public class SignalRevalidationService {

    private final Duration maximumDataAge;

    public SignalRevalidationService() {
        this(Duration.ofSeconds(90));
    }

    SignalRevalidationService(Duration maximumDataAge) {
        this.maximumDataAge = maximumDataAge;
    }

    public SignalRevalidationResult revalidate(SignalRevalidationRequest request) {
        if (!"PAPER".equals(request.executionMode())) {
            return blocked(SignalRevalidationResult.Decision.LIVE_MODE_DISABLED,
                    "Only PAPER MODE can create an order in this release.");
        }
        if (!request.assessedAt().isBefore(request.validUntil())) {
            return blocked(SignalRevalidationResult.Decision.SIGNAL_EXPIRED,
                    "The signal validity window has ended.");
        }
        if (Duration.between(request.latestPriceAt(), request.assessedAt()).compareTo(maximumDataAge) > 0) {
            return blocked(SignalRevalidationResult.Decision.STALE_MARKET_DATA,
                    "The latest market price is older than the configured safety limit.");
        }

        var priceInZone = request.latestPrice().compareTo(request.acceptablePriceMin()) >= 0
                && request.latestPrice().compareTo(request.acceptablePriceMax()) <= 0;

        if (request.action() == SignalAction.BUY && !priceInZone) {
            return blocked(SignalRevalidationResult.Decision.BUY_PRICE_OUTSIDE_ZONE,
                    "BUY is blocked: the latest price is outside the approved entry zone and must not be chased.");
        }
        if (request.action() == SignalAction.SELL_HOLDING && !priceInZone
                && !(request.protectiveExit() && request.latestPrice().compareTo(request.referencePrice()) < 0)) {
            return blocked(SignalRevalidationResult.Decision.SELL_PRICE_OUTSIDE_ZONE,
                    "SELL is blocked until the exit condition is revalidated.");
        }

        return new SignalRevalidationResult(
                SignalRevalidationResult.Decision.APPROVED_FOR_PAPER_ORDER,
                request.latestPrice(),
                request.protectiveExit() && !priceInZone
                        ? "Protective exit remains valid after adverse price movement."
                        : "Fresh price is within the approved execution zone."
        );
    }

    private SignalRevalidationResult blocked(SignalRevalidationResult.Decision decision, String reason) {
        return new SignalRevalidationResult(decision, null, reason);
    }
}
