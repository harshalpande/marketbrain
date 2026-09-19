package in.marketbrain.training;

import com.fasterxml.jackson.databind.JsonNode;
import org.junit.jupiter.api.Test;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.stream.StreamSupport;
import static in.marketbrain.training.NumericalResearchExportTest.MAPPER;
import static org.assertj.core.api.Assertions.*;

/** Drift checks for a review contract, NOT validation of an implemented ten-feature learner. */
class NumericalPrefitContractTest {
    private Path root() {
        var path=Path.of(System.getProperty("user.dir"));
        return path.resolve("ops/data").toFile().exists()?path:path.getParent();
    }
    private JsonNode contract() throws Exception {
        return MAPPER.readTree(root().resolve("ops/data/numerical-prefit-contract-v1.json").toFile());
    }
    private java.util.List<String> strings(JsonNode node) {
        assertThat(node.isArray()).isTrue();
        return StreamSupport.stream(node.spliterator(),false).map(JsonNode::asText).toList();
    }
    @Test void featureOrderMatchesActualDtoAndExistingDataContract() throws Exception {
        var c=contract();var names=strings(c.at("/input/featureOrder"));
        assertThat(names).containsExactlyElementsOf(NumericalDataContract.draft().candidateFeatures());
        assertThat(names).containsExactlyElementsOf(Arrays.stream(NumericalResearchMapping.Vector.class.getRecordComponents()).map(java.lang.reflect.RecordComponent::getName).toList());
        assertThat(names).hasSize(10).doesNotHaveDuplicates();
        assertThat(c.at("/input/mappingVersion").asText()).isEqualTo(NumericalResearchMapping.VERSION);
        assertThat(strings(c.at("/input/featureUnits"))).containsExactly("PERCENT","PERCENT","PERCENT","PERCENT","PERCENT","INDEX_0_100","PERCENT","PERCENT","RATIO","PERCENT_0_100");
        for(var forbidden:strings(c.at("/input/forbiddenFeatures"))) assertThat(names).doesNotContain(forbidden);
    }
    @Test void targetKeepsApprovedScopeWithoutInventingDatesOrBroaderTraining() throws Exception {
        var c=contract();assertThat(c.at("/target/horizonSessions").asInt()).isEqualTo(NumericalDataContract.draft().horizonSessions());
        assertThat(c.at("/target/unit").asText()).isEqualTo("PERCENTAGE_POINTS");
        assertThat(c.at("/target/exit").asText()).isEqualTo("ENTRY_PLUS_19_VERIFIED_SESSIONS_CLOSE");
        assertThat(c.at("/target/intradayStillRequired").asBoolean()).isTrue();
        assertThat(strings(c.at("/target/otherRequiredHorizonsRetained"))).containsExactly("5","60");
        assertThat(c.at("/evaluation/finalDatesFrozen").asBoolean()).isFalse();
        assertThat(c.at("/evaluation/finalDateWindows")).isEmpty();
        assertThat(c.at("/evaluation/proposedMinimumGapSessions").asInt()).isEqualTo(20);
        assertThat(c.at("/evaluation/testInfluencesTransformsOrSelection").asBoolean()).isFalse();
        assertThat(c.at("/evaluation/alreadyInspectedRowsRole").asText()).isEqualTo("DEVELOPMENT_ONLY_NEVER_UNTOUCHED_TEST");
    }
    @Test void preprocessingAndComparatorProposalCannotBeConfusedWithTwoFeatureLab() throws Exception {
        var c=contract();assertThat(c.at("/preprocessing/fitPartition").asText()).isEqualTo("TRAIN_ONLY");
        assertThat(c.at("/preprocessing/allTenFeaturesRequired").asBoolean()).isTrue();
        assertThat(c.at("/preprocessing/missingOrNonFinite").asText()).isEqualTo("ABSTAIN_AND_RETAIN_REASON_NO_IMPUTATION");
        assertThat(c.at("/preprocessing/zeroVarianceScale").asInt()).isEqualTo(1);
        assertThat(c.at("/learners/existingTwoFeatureSyntheticLearnerReusedAsMarketLearner").asBoolean()).isFalse();
        assertThat(c.at("/learners/hyperparameterSearch").asBoolean()).isFalse();
        assertThat(strings(c.at("/learners/comparators"))).containsExactly("ZERO_RETURN","WEIGHTED_TRAIN_MEAN");
        assertThat(c.at("/learners/proposedAlpha").asDouble()).isEqualTo(0.01);
        assertThat(c.at("/learners/alphaStatus").asText()).contains("NOT_CALIBRATED_OR_APPROVED");
    }
    @Test void acceptanceThresholdsStayExplicitlyUnsetAndCostsStayHypothetical() throws Exception {
        var c=contract();var m=c.get("metrics");
        assertThat(m.get("primary").asText()).isEqualTo("EQUAL_DATE_MAE_PERCENTAGE_POINTS");
        assertThat(strings(m.get("hypotheticalRoundTripCostBps"))).containsExactly("0","25","50","100");
        assertThat(m.get("costsAreApprovedBrokerFees").asBoolean()).isFalse();
        assertThat(m.get("costArithmeticIsPortfolioSimulation").asBoolean()).isFalse();
        assertThat(m.get("independentRowBootstrapAllowed").asBoolean()).isFalse();
        for(var name:java.util.List.of("blockLengthSessions","resampleCount","seed","confidenceLevel","minimumAbsoluteMaeImprovementPp","minimumRelativeMaeImprovementPercent","maximumCoverageLossPercent","actualCostSlippagePolicy"))
            assertThat(m.get(name).isNull()).as(name).isTrue();
        assertThat(m.get("unresolvedAcceptanceOutcome").asText()).isEqualTo("RESEARCH_REPORT_ONLY_NO_WINNER_OR_PROMOTION");
    }
    @Test void artifactRecordsTransformLabelSplitAndInspectionIdentity() throws Exception {
        var c=contract();assertThat(strings(c.at("/artifact/requiredMetadata"))).contains("trainingMeans","trainingScales","featureOrder","featureUnits","fitCutoff","labelPolicyHash","foldManifestHash","inspectionLedgerHash","objectiveNormalization").doesNotHaveDuplicates();
        assertThat(c.at("/artifact/featureStatisticAndCoefficientDimension").asInt()).isEqualTo(10);
        assertThat(c.at("/artifact/predictionRoundTripParityRequired").asBoolean()).isTrue();
        assertThat(c.at("/artifact/automaticPromotion").asBoolean()).isFalse();
        assertThat(c.at("/artifact/preserveAllAttemptsAndFailedFolds").asBoolean()).isTrue();
        assertThat(strings(c.get("implementationRegressionChecklist"))).hasSize(11).doesNotHaveDuplicates();
    }
    @Test void sixSubgoalsRemainProposalAndSavedEvidenceDoesNotAuthorizeTraining() throws Exception {
        var c=contract();assertThat(c.get("status").asText()).isEqualTo("PROPOSED_CONTRACT_NOT_EXECUTABLE");
        assertThat(StreamSupport.stream(c.get("subgoals").spliterator(),false).map(n->n.get("id").asText()).toList()).containsExactly("PF1","PF2","PF3","PF4","PF5","PF6");
        var accepted=MAPPER.readTree(root().resolve(c.get("mappingAcceptancePath").asText()).toFile());
        assertThat(accepted.get("evidenceId").asText()).isEqualTo("E65");
        assertThat(accepted.get("trainingEligibleRows").asInt()).isZero();
        assertThat(c.get("existingTrainingEligibleRows").asInt()).isZero();
        assertThat(c.get("existingDevelopmentRows").asInt()).isEqualTo(accepted.get("mappedRows").asInt());
        assertThat(c.get("existingDevelopmentDateGroups").asInt()).isEqualTo(accepted.get("dateGroups").asInt());
        for(var field:java.util.List.of("ownerApprovedCompleteContract","priceAndActionEvidenceCertified","pointInTimeAvailabilityVerified","sourceRightsReviewed","evaluationAcceptanceCriteriaApproved","marketFitAuthorized","paperExecutionAuthorized","liveExecutionAuthorized","thisFileIsRuntimeConfiguration")) {
            assertThat(c.at("/release/"+field).isBoolean()).isTrue();assertThat(c.at("/release/"+field).asBoolean()).as(field).isFalse();
        }
    }
}
