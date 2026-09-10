package in.marketbrain.news;

import java.math.BigDecimal;

public record NewsEntityCandidate(
        String symbol,
        String name,
        String exchange,
        String country,
        BigDecimal sentimentScore,
        BigDecimal matchScore
) {
}
