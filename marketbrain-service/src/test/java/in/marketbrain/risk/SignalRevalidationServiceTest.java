package in.marketbrain.risk;

import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.Duration;
import java.time.Instant;

import static org.assertj.core.api.Assertions.assertThat;

class SignalRevalidationServiceTest {

    private final SignalRevalidationService service = new SignalRevalidationService(Duration.ofSeconds(90));
    private final Instant now = Instant.parse("2026-08-31T10:02:00Z");

    @Test
    void keepsBuyValidAfterTwoMinuteHumanDecisionWhenFreshPriceRemainsInZone() {
        var result = service.revalidate(request(SignalAction.BUY, false, new BigDecimal("1101.00"), now.minusSeconds(10)));

        assertThat(result.decision()).isEqualTo(SignalRevalidationResult.Decision.APPROVED_FOR_PAPER_ORDER);
        assertThat(result.revalidatedPrice()).isEqualByComparingTo("1101.00");
    }

    @Test
    void blocksBuyThatHasMovedAboveApprovedPriceZone() {
        var result = service.revalidate(request(SignalAction.BUY, false, new BigDecimal("1111.00"), now.minusSeconds(10)));

        assertThat(result.decision()).isEqualTo(SignalRevalidationResult.Decision.BUY_PRICE_OUTSIDE_ZONE);
    }

    @Test
    void permitsProtectiveSellAfterAdverseMoveBelowReferencePrice() {
        var result = service.revalidate(request(SignalAction.SELL_HOLDING, true, new BigDecimal("1088.00"), now.minusSeconds(10)));

        assertThat(result.decision()).isEqualTo(SignalRevalidationResult.Decision.APPROVED_FOR_PAPER_ORDER);
        assertThat(result.reason()).contains("Protective exit");
    }

    @Test
    void blocksStalePrice() {
        var result = service.revalidate(request(SignalAction.BUY, false, new BigDecimal("1100.00"), now.minusSeconds(91)));

        assertThat(result.decision()).isEqualTo(SignalRevalidationResult.Decision.STALE_MARKET_DATA);
    }

    private SignalRevalidationRequest request(SignalAction action, boolean protectiveExit,
                                              BigDecimal latestPrice, Instant latestPriceAt) {
        return new SignalRevalidationRequest(
                "PAPER", action, protectiveExit,
                now.plusSeconds(180), new BigDecimal("1090.00"), new BigDecimal("1110.00"),
                new BigDecimal("1100.00"), latestPrice, latestPriceAt, now
        );
    }
}
