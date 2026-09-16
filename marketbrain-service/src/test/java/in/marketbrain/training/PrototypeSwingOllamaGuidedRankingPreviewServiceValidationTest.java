package in.marketbrain.training;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;

import java.lang.reflect.Method;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

class PrototypeSwingOllamaGuidedRankingPreviewServiceValidationTest {

    private final PrototypeSwingOllamaGuidedRankingPreviewService service =
            new PrototypeSwingOllamaGuidedRankingPreviewService(null, null, null, new ObjectMapper());

    @Test
    void toleratesKnownMisfiledGraniteEnumTagsWithoutRelaxingSchema() throws Exception {
        Object validation = validate(response(54), List.of(hardCapCandidate()));

        assertThat(stringList(validation, "failures")).isEmpty();
        assertThat(stringList(validation, "normalizationWarnings"))
                .contains(
                        "ENUM_MISFILED_TOLERATED:positiveEvidenceCodes:MIXED_TREND",
                        "ENUM_MISFILED_TOLERATED:positiveEvidenceCodes:EMA_BEARISH",
                        "ENUM_MISFILED_TOLERATED:riskFlagCodes:RECOVERY_CANDIDATE",
                        "ENUM_MISFILED_TOLERATED:riskFlagCodes:NOT_EXTENDED",
                        "ENUM_MISFILED_TOLERATED:riskFlagCodes:VOLUME_CONFIRMED");
    }

    @Test
    void stillBlocksMaterialHardCapViolation() throws Exception {
        Object validation = validate(response(69), List.of(hardCapCandidate()));

        assertThat(stringList(validation, "failures"))
                .contains("SCORE_CAP_VIOLATION:ABSLAMC:HARD_CAP_54:score=69");
    }

    private Object validate(String response, List<PrototypeSwingOllamaCandidate> candidates) throws Exception {
        Method method = PrototypeSwingOllamaGuidedRankingPreviewService.class
                .getDeclaredMethod("validateResponse", String.class, List.class, int.class);
        method.setAccessible(true);
        return method.invoke(service, response, candidates, 20);
    }

    @SuppressWarnings("unchecked")
    private List<String> stringList(Object validation, String methodName) throws Exception {
        Method method = validation.getClass().getDeclaredMethod(methodName);
        method.setAccessible(true);
        return (List<String>) method.invoke(validation);
    }

    private String response(int score) {
        return """
                {
                  "schemaVersion": "MARKETBRAIN_OLLAMA_RANKING_RESPONSE_V4",
                  "rankingHorizonSessions": 20,
                  "rankedCandidates": [
                    {
                      "rank": 1,
                      "candidateId": "CANDIDATE_001",
                      "symbol": "ABSLAMC",
                      "score": %d,
                      "confidence": "LOW",
                      "positiveEvidenceCodes": ["MIXED_TREND", "EMA_BEARISH"],
                      "riskFlagCodes": ["RECOVERY_CANDIDATE", "NOT_EXTENDED", "VOLUME_CONFIRMED"],
                      "reasonCode": "JAVA_BASELINE_ALIGNED",
                      "signedContributions": {
                        "trendContribution": -10,
                        "momentumContribution": -10,
                        "participationContribution": -10,
                        "riskPenalty": -20,
                        "recoveryCredit": 0,
                        "overextensionPenalty": -20,
                        "algorithmAdjustment": 0,
                        "finalScore": %d
                      },
                      "notTradingSignal": true
                    }
                  ],
                  "riskNoteCode": "SURVIVORSHIP_PROTOTYPE_REVIEW_ONLY",
                  "researchOnlyCode": "NOT_TRADING_SIGNAL"
                }
                """.formatted(score, score);
    }

    private PrototypeSwingOllamaCandidate hardCapCandidate() {
        return new PrototypeSwingOllamaCandidate(
                "ABSLAMC",
                LocalDate.of(2026, 6, 5),
                bd("100"),
                bd("3.50"),
                bd("95"),
                bd("110"),
                bd("120"),
                bd("90"),
                bd("100"),
                bd("72"),
                bd("5"),
                bd("48"),
                bd("0.50"),
                bd("96"),
                bd("1"),
                bd("2"),
                bd("3"),
                bd("-1"),
                bd("-2"),
                bd("-3"),
                bd("8"),
                bd("9"),
                bd("10"));
    }

    private BigDecimal bd(String value) {
        return new BigDecimal(value);
    }
}
