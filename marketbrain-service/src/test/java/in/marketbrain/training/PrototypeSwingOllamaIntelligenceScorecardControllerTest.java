package in.marketbrain.training;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import org.junit.jupiter.api.Test;

import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

class PrototypeSwingOllamaIntelligenceScorecardControllerTest {

    @Test
    void acceptsWrappedCompletedJobResult() throws Exception {
        ObjectMapper objectMapper = new ObjectMapper().registerModule(new JavaTimeModule());
        PrototypeSwingOllamaIntelligenceScorecardController controller =
                new PrototypeSwingOllamaIntelligenceScorecardController(
                        new PrototypeSwingOllamaIntelligenceScorecardService(),
                        objectMapper);
        String json = """
                {
                  "status": "COMPLETED",
                  "result": {
                    "status": "REVIEW_REQUIRED",
                    "datasetRunId": "%s",
                    "model": "ibm/granite4.1:8b",
                    "asOf": "2026-06-05",
                    "labelThrough": "2026-09-08",
                    "startOffset": 0,
                    "totalCandidateLimit": 4,
                    "chunkSize": 4,
                    "finalistsPerChunk": 2,
                    "maxRetriesPerChunk": 1,
                    "rankingHorizonSessions": 20,
                    "chunkedRankingVersion": "MARKETBRAIN_OLLAMA_CHUNKED_RANKING_V1",
                    "chunkCount": 1,
                    "passedChunkCount": 1,
                    "warningChunkCount": 0,
                    "failedChunkCount": 0,
                    "processedCandidateCount": 4,
                    "finalistCount": 1,
                    "ollamaCallCount": 1,
                    "chunks": [
                      {
                        "chunkNumber": 1,
                        "offset": 0,
                        "candidateCount": 4,
                        "candidateSymbols": ["ABDL"],
                        "chunkStatus": "CHUNK_PASSED",
                        "attemptCount": 1,
                        "acceptedAttemptNumber": 1,
                        "attempts": [
                          {
                            "chunkNumber": 1,
                            "attemptNumber": 1,
                            "repairInstruction": "",
                            "expectedCandidateIds": ["CANDIDATE_001"],
                            "candidateSymbols": ["ABDL"],
                            "promptHash": "prompt",
                            "prompt": "{}",
                            "promptCharacterCount": 2,
                            "responseHash": "response",
                            "responseCharacterCount": 2,
                            "ollamaElapsedMillis": 100,
                            "ollamaTotalDurationNanos": 100,
                            "ollamaPromptEvalCount": 1,
                            "ollamaEvalCount": 1,
                            "ollamaResponse": "{}",
                            "responseParseableJson": true,
                            "responseSchemaValid": true,
                            "rankingQualityStatus": "QUALITY_REVIEW_PASSED",
                            "scoreCalibrationStatus": "SCORE_CALIBRATION_PASSED",
                            "responseValidationFailures": [],
                            "responseNormalizationWarnings": [],
                            "evaluationFailures": [],
                            "calibrationFailures": [],
                            "acceptedForChunkSummary": true
                          }
                        ],
                        "finalists": [
                          {
                            "chunkNumber": 1,
                            "symbol": "ABDL",
                            "chunkOllamaRank": 1,
                            "chunkJavaBaselineRank": 1,
                            "chunkFinalReviewRank": 1,
                            "chunkActualRank": 1,
                            "ollamaScore": 84,
                            "javaBaselineScore": 60,
                            "finalReviewScore": 66,
                            "ollamaConfidence": "MEDIUM",
                            "arbitrationDecision": "JAVA_ACCEPTED",
                            "targetNetReturnPercent": 10,
                            "targetBenchmarkExcessReturnPercent": 5,
                            "targetMaximumDrawdownPercent": 2,
                            "qualityBucket": "ACTUAL_TOP_TIER",
                            "javaBaselineReason": "baseline",
                            "arbitrationReason": "arbitration",
                            "reason": "reason"
                          }
                        ],
                        "acceptedCalibrationBatch": null
                      }
                    ],
                    "mergedFinalists": [],
                    "aggregateFailures": [],
                    "databaseWritesPerformed": false,
                    "signalsCreated": 0,
                    "ordersCreated": 0,
                    "actionExecutionEnabled": false,
                    "detail": "done"
                  }
                }
                """.formatted(UUID.randomUUID());

        PrototypeSwingOllamaIntelligenceScorecard scorecard =
                controller.scorecard(objectMapper.readTree(json));

        assertThat(scorecard.status()).isEqualTo("READY_FOR_BROAD_VALIDATION");
        assertThat(scorecard.datasetRunId()).isNotNull();
        assertThat(scorecard.model()).isEqualTo("ibm/granite4.1:8b");
        assertThat(scorecard.pipelineReliabilityPercent()).isEqualTo(100);
        assertThat(scorecard.databaseWritesPerformed()).isFalse();
        assertThat(scorecard.signalsCreated()).isZero();
        assertThat(scorecard.ordersCreated()).isZero();
        assertThat(scorecard.actionExecutionEnabled()).isFalse();
    }
}
