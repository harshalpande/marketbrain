package in.marketbrain.marketdata.backfill;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class BackfillQualityRulesTest {

    private final BackfillQualityRules rules = new BackfillQualityRules();

    @Test
    void blocksMissingDuplicateOrInvalidCandles() {
        assertThat(rules.instrumentStatus(0, 0, 0, 0, 0, 0, 0, 0, 7)).isEqualTo("BLOCKED");
        assertThat(rules.instrumentStatus(10, 1, 0, 0, 0, 0, 0, 0, 7)).isEqualTo("BLOCKED");
        assertThat(rules.instrumentStatus(10, 0, 1, 0, 0, 0, 0, 0, 7)).isEqualTo("BLOCKED");
    }

    @Test
    void identifiesMissingOfficialSessionsWithoutCallingThemInvalidCandles() {
        assertThat(rules.instrumentStatus(10, 0, 0, 1, 0, 0, 0, 0, 7))
                .isEqualTo("MISSING_PROVIDER_DATA");
    }

    @Test
    void sendsCoverageGapsAndLargeMovesForReviewWithoutCallingThemErrors() {
        assertThat(rules.instrumentStatus(10, 0, 0, 0, 8, 0, 0, 0, 7)).isEqualTo("REVIEW");
        assertThat(rules.instrumentStatus(10, 0, 0, 0, 0, 8, 0, 0, 7)).isEqualTo("REVIEW");
        assertThat(rules.instrumentStatus(10, 0, 0, 0, 0, 0, 1, 0, 7)).isEqualTo("REVIEW");
        assertThat(rules.instrumentStatus(10, 0, 0, 0, 0, 0, 0, 1, 7)).isEqualTo("REVIEW");
        assertThat(rules.requiresReview(0, 0, 0, 1, 7)).isTrue();
        assertThat(rules.requiresReview(0, 0, 0, 0, 7)).isFalse();
    }

    @Test
    void passesCleanCoverageAndEscalatesProviderComparisonProblems() {
        assertThat(rules.instrumentStatus(10, 0, 0, 0, 7, 7, 0, 0, 7)).isEqualTo("PASS");
        assertThat(rules.overallStatus(10, 0, 0, 0, 0, 0)).isEqualTo("PASS");
        assertThat(rules.overallStatus(10, 0, 1, 0, 0, 0)).isEqualTo("MISSING_PROVIDER_DATA");
        assertThat(rules.overallStatus(10, 0, 0, 1, 0, 0)).isEqualTo("REVIEW");
        assertThat(rules.overallStatus(10, 0, 0, 0, 1, 0)).isEqualTo("REVIEW");
        assertThat(rules.overallStatus(10, 0, 0, 0, 0, 1)).isEqualTo("REVIEW");
        assertThat(rules.overallStatus(10, 1, 0, 0, 0, 0)).isEqualTo("BLOCKED");
        assertThat(rules.overallStatus(0, 0, 0, 0, 0, 0)).isEqualTo("BLOCKED");
    }
}
