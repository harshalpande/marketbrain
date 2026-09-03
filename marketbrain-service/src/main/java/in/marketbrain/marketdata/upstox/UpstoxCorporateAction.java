package in.marketbrain.marketdata.upstox;

import java.math.BigDecimal;
import java.time.LocalDate;

public record UpstoxCorporateAction(
        String name,
        String actionType,
        LocalDate effectiveOn,
        LocalDate announcedOn,
        LocalDate recordOn,
        BigDecimal amount,
        String ratio,
        String details
) {
}
