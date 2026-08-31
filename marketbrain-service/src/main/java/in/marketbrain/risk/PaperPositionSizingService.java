package in.marketbrain.risk;

import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.math.RoundingMode;

/**
 * Caps a paper BUY at one percent of the portfolio's current value. This is a
 * sizing rule, not a prediction of maximum loss: market gaps can exceed a stop.
 */
@Service
public class PaperPositionSizingService {

    private static final BigDecimal MAX_PORTFOLIO_RISK_PERCENT = new BigDecimal("0.01");

    public PositionSizingResult size(BigDecimal portfolioValue, BigDecimal availableCash,
                                     BigDecimal entryPrice, BigDecimal stopLossPrice) {
        if (portfolioValue.signum() <= 0 || availableCash.signum() < 0 || entryPrice.signum() <= 0
                || stopLossPrice.signum() <= 0 || stopLossPrice.compareTo(entryPrice) >= 0) {
            throw new IllegalArgumentException("A BUY requires positive portfolio/cash/prices and a stop below entry.");
        }

        var riskBudget = portfolioValue.multiply(MAX_PORTFOLIO_RISK_PERCENT);
        var riskPerShare = entryPrice.subtract(stopLossPrice);
        var quantityByRisk = riskBudget.divide(riskPerShare, 0, RoundingMode.DOWN);
        var quantityByCash = availableCash.divide(entryPrice, 0, RoundingMode.DOWN);
        var quantity = quantityByRisk.min(quantityByCash);

        return new PositionSizingResult(quantity, riskBudget, riskPerShare,
                quantity.multiply(entryPrice), quantity.multiply(riskPerShare));
    }

    public record PositionSizingResult(
            BigDecimal quantity,
            BigDecimal riskBudget,
            BigDecimal riskPerShare,
            BigDecimal estimatedNotional,
            BigDecimal estimatedRisk
    ) {
    }
}
