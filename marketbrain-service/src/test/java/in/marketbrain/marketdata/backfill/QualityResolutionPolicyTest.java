package in.marketbrain.marketdata.backfill;

import org.junit.jupiter.api.Test;

import java.time.LocalDate;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class QualityResolutionPolicyTest {

    private static final LocalDate JOB_FROM = LocalDate.of(2011, 9, 2);
    private static final LocalDate JOB_TO = LocalDate.of(2026, 9, 1);
    private final QualityResolutionPolicy policy = new QualityResolutionPolicy();

    @Test
    void verifiedExchangeMovePreservesTheRawReturnWithoutAnExclusion() {
        policy.validate(QualityFindingType.LARGE_MOVE, QualityResolutionType.VERIFIED_EXCHANGE_MOVE,
                LocalDate.of(2024, 4, 23), null, null, JOB_FROM, JOB_TO);
    }

    @Test
    void corporateActionRequiresAnExplicitFeatureExclusion() {
        assertThatThrownBy(() -> policy.validate(
                QualityFindingType.LARGE_MOVE, QualityResolutionType.CORPORATE_ACTION_TRANSITION,
                LocalDate.of(2024, 4, 23), null, null, JOB_FROM, JOB_TO))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("feature-exclusion window");

        policy.validate(QualityFindingType.LARGE_MOVE, QualityResolutionType.CORPORATE_ACTION_TRANSITION,
                LocalDate.of(2024, 4, 23), LocalDate.of(2024, 4, 23),
                LocalDate.of(2024, 4, 24), JOB_FROM, JOB_TO);
    }

    @Test
    void confirmedProviderOmissionDocumentsButDoesNotPermitTraining() {
        policy.validate(QualityFindingType.PEER_CONFIRMED_SESSION,
                QualityResolutionType.PROVIDER_OMISSION_CONFIRMED,
                LocalDate.of(2012, 10, 16), null, null, JOB_FROM, JOB_TO);

        assertThat(QualityResolutionType.PROVIDER_OMISSION_CONFIRMED.allowsTraining()).isFalse();
    }

    @Test
    void rejectsResolutionTypesThatDoNotMatchTheFinding() {
        assertThatThrownBy(() -> policy.validate(
                QualityFindingType.PEER_CONFIRMED_SESSION, QualityResolutionType.VERIFIED_EXCHANGE_MOVE,
                LocalDate.of(2012, 10, 16), null, null, JOB_FROM, JOB_TO))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("large-move");
    }

    @Test
    void featureWindowMustRemainInsideTheBackfillJob() {
        assertThatThrownBy(() -> policy.validate(
                QualityFindingType.SUSPICIOUS_GAP, QualityResolutionType.FEATURE_WINDOW_EXCLUDED,
                JOB_FROM, JOB_FROM.minusDays(1), JOB_FROM, JOB_FROM, JOB_TO))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("inside the job window");
    }

    @Test
    void featureWindowCannotExcludeAnUnrelatedDate() {
        assertThatThrownBy(() -> policy.validate(
                QualityFindingType.LARGE_MOVE, QualityResolutionType.PROVIDER_ADJUSTMENT,
                LocalDate.of(2024, 4, 23), LocalDate.of(2024, 4, 24),
                LocalDate.of(2024, 4, 25), JOB_FROM, JOB_TO))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("contain the finding date");
    }
}
