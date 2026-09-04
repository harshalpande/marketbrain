package in.marketbrain.marketdata.backfill;

import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class RemainingDataRemediationServiceTest {

    private static final String HASH = "3ea264d124b3618dc793a66677e1b040736d65ad49b230309b60647b1c64b7f8";
    private final RemainingDataRemediationService service =
            new RemainingDataRemediationService(null, null, null, null, null, null);

    @Test
    void acceptsACompleteHashMatchedPlan() {
        RemainingDataAnalysisReport report = report(featureExclusionItem(), HASH, true, 0, 0);

        assertThatCode(() -> service.validateReviewedAnalysis(report, HASH)).doesNotThrowAnyException();
    }

    @Test
    void rejectsAPlanWhoseLiveHashDiffersFromTheReviewedHash() {
        RemainingDataAnalysisReport report = report(featureExclusionItem(), "a".repeat(64), true, 0, 0);

        assertThatThrownBy(() -> service.validateReviewedAnalysis(report, HASH))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("does not match");
    }

    @Test
    void rejectsAPlanWithAnOpenOrSourceFailedFinding() {
        RemainingDataAnalysisReport report = report(featureExclusionItem(), HASH, false, 1, 1);

        assertThatThrownBy(() -> service.validateReviewedAnalysis(report, HASH))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("incomplete");
    }

    @Test
    void rejectsASecondaryCandleWithInvalidOhlcOrdering() {
        LocalDate date = LocalDate.of(2016, 10, 30);
        var invalid = new RemainingDataAnalysisReport.Item(
                QualityFindingType.OFFICIAL_SPECIAL_SESSION, "INFY", date, null,
                "OFFICIAL_CANDLE_AVAILABLE", QualityResolutionType.SECONDARY_SOURCE_BACKFILLED,
                null, null, "INFY", "ISIN", "EQ", new BigDecimal("100"),
                new BigDecimal("90"), new BigDecimal("80"), new BigDecimal("95"), BigDecimal.TEN,
                null, null, null, "NSE official daily BhavCopy", "https://archives.nseindia.com/example.zip",
                "invalid ordering");
        RemainingDataAnalysisReport report = new RemainingDataAnalysisReport(
                UUID.randomUUID(), 1, 1, 0, 0, 0, 1, 1, 0, 0, 0,
                0, 0, true, HASH, false, false, List.of(invalid), "read only");

        assertThatThrownBy(() -> service.validateReviewedAnalysis(report, HASH))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("invalid secondary-source candle");
    }

    @Test
    void comparesStoredDecimalValuesWithoutDependingOnScale() {
        assertThat(service.sameDecimal(new BigDecimal("10.0"), new BigDecimal("10.0000"))).isTrue();
        assertThat(service.sameDecimal(null, null)).isTrue();
        assertThat(service.sameDecimal(BigDecimal.ONE, null)).isFalse();
        assertThat(service.sameDecimal(BigDecimal.ONE, BigDecimal.TEN)).isFalse();
    }

    private RemainingDataAnalysisReport report(
            RemainingDataAnalysisReport.Item item,
            String hash,
            boolean complete,
            int keepOpen,
            int sourceFailures
    ) {
        return new RemainingDataAnalysisReport(
                UUID.randomUUID(), 1, 0, 0, 1, 0, 0,
                0, 1, 0, 0, keepOpen, sourceFailures, complete,
                hash, false, false, List.of(item), "read only");
    }

    private RemainingDataAnalysisReport.Item featureExclusionItem() {
        return new RemainingDataAnalysisReport.Item(
                QualityFindingType.LEADING_COVERAGE_GAP, "AADHARHFC",
                LocalDate.of(2011, 9, 2), LocalDate.of(2024, 5, 15),
                "COVERAGE_WINDOW_REQUIRES_EXCLUSION", QualityResolutionType.FEATURE_WINDOW_EXCLUDED,
                LocalDate.of(2011, 9, 2), LocalDate.of(2024, 5, 14),
                null, null, null, null, null, null, null, null,
                null, null, null, "MarketBrain persisted coverage audit", null, "coverage boundary");
    }
}

