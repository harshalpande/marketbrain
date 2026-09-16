package in.marketbrain.training;

import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

class PrototypeSwingOllamaIntelligenceScorecardServiceTest {

    private final PrototypeSwingOllamaIntelligenceScorecardService service =
            new PrototypeSwingOllamaIntelligenceScorecardService();

    @Test
    void scoresCompletedChunkedRankingWithoutSideEffects() {
        PrototypeSwingOllamaIntelligenceScorecard scorecard = service.scorecard(preview());

        assertThat(scorecard.status()).isIn(
                "READY_FOR_RANDOM_VALIDATION",
                "IMPROVING_NEEDS_RANDOM_VALIDATION",
                "READY_FOR_BROAD_VALIDATION");
        assertThat(scorecard.pipelineReliabilityPercent()).isEqualTo(100);
        assertThat(scorecard.failedChunkCount()).isZero();
        assertThat(scorecard.databaseWritesPerformed()).isFalse();
        assertThat(scorecard.signalsCreated()).isZero();
        assertThat(scorecard.ordersCreated()).isZero();
        assertThat(scorecard.actionExecutionEnabled()).isFalse();
        assertThat(scorecard.dimensions()).extracting(PrototypeSwingOllamaIntelligenceScorecardDimension::name)
                .contains(
                        "PIPELINE_RELIABILITY",
                        "SCHEMA_DISCIPLINE",
                        "SCORE_CALIBRATION",
                        "RANKING_QUALITY",
                        "FINALIST_QUALITY");
        assertThat(scorecard.topImprovementActions()).isNotEmpty();
    }

    @Test
    void flagsFailedChunksAsReviewRequired() {
        PrototypeSwingOllamaChunkedRankingPreview preview = new PrototypeSwingOllamaChunkedRankingPreview(
                "REVIEW_WITH_WARNINGS",
                UUID.randomUUID(),
                "ibm/granite4.1:8b",
                LocalDate.of(2026, 6, 5),
                LocalDate.of(2026, 9, 8),
                0,
                4,
                4,
                2,
                1,
                20,
                "MARKETBRAIN_OLLAMA_CHUNKED_RANKING_V1",
                1,
                0,
                0,
                1,
                4,
                0,
                1,
                List.of(failedChunk()),
                List.of(),
                List.of("CHUNK_1_FAILED"),
                false,
                0,
                0,
                false,
                "failed");

        PrototypeSwingOllamaIntelligenceScorecard scorecard = service.scorecard(preview);

        assertThat(scorecard.status()).isEqualTo("REVIEW_REQUIRED");
        assertThat(scorecard.pipelineReliabilityPercent()).isZero();
        assertThat(scorecard.topImprovementActions()).contains("Fix failed chunks before expanding evaluation.");
    }

    private PrototypeSwingOllamaChunkedRankingPreview preview() {
        List<PrototypeSwingOllamaChunkedRankingChunk> chunks = List.of(
                passedChunk(1, "ABDL", 1),
                warningChunk(2, "360ONE", 4));
        return new PrototypeSwingOllamaChunkedRankingPreview(
                "REVIEW_WITH_WARNINGS",
                UUID.randomUUID(),
                "ibm/granite4.1:8b",
                LocalDate.of(2026, 6, 5),
                LocalDate.of(2026, 9, 8),
                0,
                8,
                4,
                2,
                1,
                20,
                "MARKETBRAIN_OLLAMA_CHUNKED_RANKING_V1",
                2,
                1,
                1,
                0,
                8,
                4,
                2,
                chunks,
                chunks.stream().flatMap(chunk -> chunk.finalists().stream()).toList(),
                List.of("CHUNK_2_WARNING"),
                false,
                0,
                0,
                false,
                "review");
    }

    private PrototypeSwingOllamaChunkedRankingChunk passedChunk(int chunkNumber, String symbol, int actualRank) {
        PrototypeSwingOllamaChunkedRankingAttempt attempt = attempt(
                chunkNumber,
                "QUALITY_REVIEW_PASSED",
                "SCORE_CALIBRATION_PASSED",
                List.of(),
                List.of());
        return chunk(chunkNumber, "CHUNK_PASSED", 1, List.of(attempt), List.of(finalist(chunkNumber, symbol, actualRank)));
    }

    private PrototypeSwingOllamaChunkedRankingChunk warningChunk(int chunkNumber, String symbol, int actualRank) {
        PrototypeSwingOllamaChunkedRankingAttempt attempt = attempt(
                chunkNumber,
                "QUALITY_REVIEW_WEAK",
                "SCORE_CALIBRATION_WEAK",
                List.of("TOP_PICK_NOT_IN_ACTUAL_TOP_HALF"),
                List.of("BEST_ACTUAL_SCORE_TOO_LOW"));
        return chunk(chunkNumber, "CHUNK_ACCEPTED_WITH_WARNINGS", 1, List.of(attempt), List.of(finalist(chunkNumber, symbol, actualRank)));
    }

    private PrototypeSwingOllamaChunkedRankingChunk failedChunk() {
        PrototypeSwingOllamaChunkedRankingAttempt attempt = new PrototypeSwingOllamaChunkedRankingAttempt(
                1,
                1,
                "",
                List.of("CANDIDATE_001"),
                List.of("ABDL"),
                "promptHash",
                "{}",
                2,
                "responseHash",
                2,
                100L,
                100L,
                10,
                10,
                "{}",
                true,
                false,
                "SCHEMA_GUARDRAIL_BLOCKED",
                "SCORE_CALIBRATION_BLOCKED",
                List.of("REASONING_ENUM_FIELDS"),
                List.of(),
                List.of("RESPONSE_SCHEMA_INVALID"),
                List.of("SCHEMA_GUARDRAIL_BLOCKED"),
                false);
        return chunk(1, "CHUNK_FAILED", 0, List.of(attempt), List.of());
    }

    private PrototypeSwingOllamaChunkedRankingChunk chunk(
            int chunkNumber,
            String status,
            int acceptedAttemptNumber,
            List<PrototypeSwingOllamaChunkedRankingAttempt> attempts,
            List<PrototypeSwingOllamaChunkedRankingFinalist> finalists
    ) {
        return new PrototypeSwingOllamaChunkedRankingChunk(
                chunkNumber,
                (chunkNumber - 1) * 4,
                4,
                List.of("A", "B", "C", "D"),
                status,
                attempts.size(),
                acceptedAttemptNumber,
                attempts,
                finalists,
                null);
    }

    private PrototypeSwingOllamaChunkedRankingAttempt attempt(
            int chunkNumber,
            String rankingQualityStatus,
            String scoreCalibrationStatus,
            List<String> evaluationFailures,
            List<String> calibrationFailures
    ) {
        return new PrototypeSwingOllamaChunkedRankingAttempt(
                chunkNumber,
                1,
                "",
                List.of("CANDIDATE_001"),
                List.of("ABDL"),
                "promptHash",
                "{}",
                2,
                "responseHash",
                2,
                100L,
                100L,
                10,
                10,
                "{}",
                true,
                true,
                rankingQualityStatus,
                scoreCalibrationStatus,
                List.of(),
                List.of(),
                evaluationFailures,
                calibrationFailures,
                true);
    }

    private PrototypeSwingOllamaChunkedRankingFinalist finalist(
            int chunkNumber,
            String symbol,
            int actualRank
    ) {
        return new PrototypeSwingOllamaChunkedRankingFinalist(
                chunkNumber,
                symbol,
                1,
                1,
                1,
                actualRank,
                80,
                75,
                78,
                "MEDIUM",
                "JAVA_ACCEPTED",
                BigDecimal.TEN,
                BigDecimal.ONE,
                BigDecimal.ONE,
                "ACTUAL_TOP_TIER",
                "baseline",
                "arbitration",
                "reason");
    }
}
