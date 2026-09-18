package in.marketbrain.training;

import org.junit.jupiter.api.Test;
import org.springframework.context.annotation.AnnotationConfigApplicationContext;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.*;

class PrototypeSwingTypedDecisionIndependentTest {
    private final PrototypeSwingOllamaGuidedRankingPreviewService guided =
            mock(PrototypeSwingOllamaGuidedRankingPreviewService.class);
    private final PrototypeSwingTrainingDatasetAuditService audit = mock(PrototypeSwingTrainingDatasetAuditService.class);
    private final PrototypeSwingTypedDecisionPrimitivePreviewService service =
            new PrototypeSwingTypedDecisionPrimitivePreviewService(audit, guided);

    private PrototypeSwingOllamaCandidate candidate(String symbol) {
        return new PrototypeSwingOllamaCandidate(symbol, LocalDate.of(2026, 6, 5),
                new BigDecimal("100"), new BigDecimal("1.2"), new BigDecimal("98"),
                new BigDecimal("95"), new BigDecimal("90"), new BigDecimal("99"), new BigDecimal("97"),
                new BigDecimal("55"), new BigDecimal("2"), new BigDecimal("20"),
                new BigDecimal("1.3"), new BigDecimal("60"),
                new BigDecimal("987.654321"), new BigDecimal("987.654321"), new BigDecimal("987.654321"),
                new BigDecimal("876.54321"), new BigDecimal("876.54321"), new BigDecimal("876.54321"),
                new BigDecimal("765.4321"), new BigDecimal("765.4321"), new BigDecimal("765.4321"));
    }

    @Test
    void independentPromptContainsAsOfEvidenceButNoBaselineOrFutureOutcome() {
        var c = candidate("SECRET_SYMBOL");
        when(guided.topPickEligibility(c)).thenReturn("CAUTION");
        when(guided.scoreCapHint(c)).thenReturn("HARD_CAP_69");
        String prompt = service.independentPrompt(c, 0, 20);
        assertThat(prompt).contains("CANDIDATE_001", "close=100", "rsi14=55", "Hard exclusion reason=NONE");
        assertThat(prompt).doesNotContain("SECRET_SYMBOL", "987.654321", "876.54321", "765.4321",
                "Java guardrail expectation", "qualityAnchor", "featurePriorScore", "actualRank");
        verify(guided, never()).qualityAnchorScore(any());
        verify(guided, never()).featurePriorScore(any());
    }

    @Test
    void changingOnlyFutureLabelsCannotChangeIndependentPrompt() {
        var original = candidate("SAME");
        var changed = new PrototypeSwingOllamaCandidate(original.symbol(), original.effectiveAsOf(),
                original.latestClose(), original.dailyReturnPercent(), original.sma20(), original.sma50(), original.sma200(),
                original.ema12(), original.ema26(), original.rsi14(), original.atr14(),
                original.annualizedVolatility20Percent(), original.volumeRatio20(), original.rangePosition252Percent(),
                null, null, null, null, null, null, null, null, null);
        when(guided.topPickEligibility(any())).thenReturn("ALLOWED");
        when(guided.scoreCapHint(any())).thenReturn("HIGH_ELIGIBLE");
        assertThat(service.independentPrompt(original, 0, 20)).isEqualTo(service.independentPrompt(changed, 0, 20));
    }

    @Test
    void topPickRestrictionDoesNotBecomeAHardExclusion() {
        var c = candidate("CAUTION");
        when(guided.topPickEligibility(c)).thenReturn("BLOCKED");
        assertThat(service.hardExclusionReason(c)).isEqualTo("NONE");
        assertThat(service.independentPrompt(c, 0, 20)).contains("limits TOP_PICK only");
        var missing = mock(PrototypeSwingOllamaCandidate.class);
        assertThat(service.hardExclusionReason(missing)).isEqualTo("MISSING_OR_INVALID_REQUIRED_FEATURES");
    }

    @Test
    void balancedSelectionInterleavesCategoriesWithoutDuplicatesAndSupportsOffset() {
        var opportunity = candidate("OPPORTUNITY");
        var caution = candidate("CAUTION");
        var avoid = candidate("AVOID");
        when(guided.topPickEligibility(any())).thenReturn("ALLOWED");
        when(guided.qualityAnchorScore(any())).thenReturn(55);
        when(guided.positiveSignalCount(opportunity)).thenReturn(4);
        when(guided.topPickEligibility(avoid)).thenReturn("BLOCKED");
        var pool = List.of(avoid, caution, opportunity);
        assertThat(service.balancedCandidates(pool, 0, 6)).containsExactly(opportunity, caution, avoid);
        assertThat(service.balancedCandidates(pool, 1, 2)).containsExactly(caution, avoid);
        assertThat(service.balancedCandidates(pool, 3, 2)).isEmpty();
        assertThat(service.balancedCandidates(List.of(caution, avoid), 0, 6)).containsExactly(caution, avoid);
    }

    @Test
    void previewUsesOneBoundedPoolAndKeepsBaselineAndOutcomesOutsideIndependentPrompt() {
        UUID id = UUID.randomUUID();
        var dataset = mock(PrototypeSwingTrainingDatasetAudit.class);
        when(audit.audit(id)).thenReturn(dataset);
        when(dataset.status()).thenReturn("REVIEW_REQUIRED");
        when(dataset.datasetRunId()).thenReturn(id);
        when(dataset.prototypeTrainingEligible()).thenReturn(true);
        when(dataset.pointInTimeSafe()).thenReturn(true);
        when(dataset.futureLabelsSeparated()).thenReturn(true);
        when(dataset.auditReadyForOllamaRanking()).thenReturn(true);
        when(dataset.failedCheckpoints()).thenReturn(List.of());
        var c = candidate("EXAMPLE");
        when(guided.candidates(id, 0, 500, "RANDOM_VALIDATION")).thenReturn(List.of(c));
        when(guided.qualityAnchorRanks(List.of(c))).thenReturn(java.util.Map.of("EXAMPLE", 1));
        when(guided.qualityAnchorScore(c)).thenReturn(55);
        when(guided.topPickEligibility(c)).thenReturn("ALLOWED");
        when(guided.scoreCapHint(c)).thenReturn("HIGH_ELIGIBLE");
        var result = service.preview(new PrototypeSwingTypedDecisionPrimitiveRequest(id, "BALANCED_VALIDATION", 0, 6, 20));
        assertThat(result.candidateCount()).isEqualTo(1);
        assertThat(result.candidates().getFirst().javaDecision()).isEqualTo("TOP_PICK");
        assertThat(result.candidates().getFirst().targetNetReturnPercent()).isEqualByComparingTo("987.654321");
        assertThat(result.candidates().getFirst().independentPrompt()).doesNotContain("987.654321", "decision=TOP_PICK");
        assertThat(result.actionExecutionEnabled()).isFalse();
        assertThat(result.databaseWritesPerformed()).isFalse();
        verify(guided, times(1)).candidates(id, 0, 500, "RANDOM_VALIDATION");
    }

    @Test
    void springCanConstructPreviewServiceWithItsSingleConstructor() {
        try (var context = new AnnotationConfigApplicationContext()) {
            context.registerBean(PrototypeSwingTrainingDatasetAuditService.class, () -> audit);
            context.registerBean(PrototypeSwingOllamaGuidedRankingPreviewService.class, () -> guided);
            context.register(PrototypeSwingTypedDecisionPrimitivePreviewService.class);
            context.refresh();
            assertThat(context.getBean(PrototypeSwingTypedDecisionPrimitivePreviewService.class)).isNotNull();
        }
    }
}
