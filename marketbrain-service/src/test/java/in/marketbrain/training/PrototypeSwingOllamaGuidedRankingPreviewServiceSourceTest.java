package in.marketbrain.training;

import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.nio.charset.StandardCharsets;

import static org.assertj.core.api.Assertions.assertThat;

class PrototypeSwingOllamaGuidedRankingPreviewServiceSourceTest {

    @Test
    void guidedPreviewIsReadOnlyAndHasResponseGuardrails() throws IOException {
        String source = java.nio.file.Files.readString(
                java.nio.file.Path.of("src/main/java/in/marketbrain/training/"
                        + "PrototypeSwingOllamaGuidedRankingPreviewService.java"),
                StandardCharsets.UTF_8);
        assertThat(source).doesNotContain("@Transactional");
        assertThat(source).doesNotContain("jdbcTemplate.update");
        assertThat(source).doesNotContain("INSERT INTO");
        assertThat(source).doesNotContain("market_signal");
        assertThat(source).doesNotContain("paper_order");
        assertThat(source).contains("generateJson");
        assertThat(source).contains("validateResponse");
        assertThat(source).contains("RESPONSE_SCHEMA_VERSION");
        assertThat(source).contains("POSITIVE_WINNER");
        assertThat(source).contains("NEGATIVE_LOSER");
        assertThat(source).contains("FALSE_CONFIDENCE_TRAP");
        assertThat(source).contains("SMOOTH_OUTPERFORMER");
        assertThat(source).contains("RECOVERY_OUTPERFORMER");
        assertThat(source).contains("OVEREXTENDED_MOMENTUM_TRAP");
        assertThat(source).contains("score_cap_hint");
        assertThat(source).contains("feature_prior_score");
        assertThat(source).contains("feature_prior_rank");
        assertThat(source).contains("quality_anchor_score");
        assertThat(source).contains("quality_anchor_rank");
        assertThat(source).contains("quality_anchor_band");
        assertThat(source).contains("quality_anchor_gap_to_leader");
        assertThat(source).contains("risk_control_score");
        assertThat(source).contains("opportunity_score");
        assertThat(source).contains("major_conflict_count");
        assertThat(source).contains("positive_signal_count");
        assertThat(source).contains("relative_quality_flag");
        assertThat(source).contains("trend_score");
        assertThat(source).contains("momentum_score");
        assertThat(source).contains("participation_score");
        assertThat(source).contains("risk_penalty");
        assertThat(source).contains("recovery_credit");
        assertThat(source).contains("overextension_penalty");
        assertThat(source).contains("rebound_breakout_credit");
        assertThat(source).contains("anchor_priority_hint");
        assertThat(source).contains("top_pick_eligibility");
        assertThat(source).contains("RankingResponseDto");
        assertThat(source).contains("SignedContributionsDto");
        assertThat(source).contains("signedContributions");
        assertThat(source).contains("MARKETBRAIN_OLLAMA_RANKING_RESPONSE_V4");
        assertThat(source).contains("MARKETBRAIN_SWING_OLLAMA_INSTRUCTION_PACK_V13");
        assertThat(source).contains("MARKETBRAIN_SWING_RUBRIC_V13");
        assertThat(source).contains("POSITIVE_EVIDENCE_CODES");
        assertThat(source).contains("RISK_FLAG_CODES");
        assertThat(source).contains("REASON_CODES");
        assertThat(source).contains("RISK_ADJUSTED_LEADER");
        assertThat(source).contains("MATERIAL_QUALITY_GAP");
        assertThat(source).contains("RISK_ADJUSTED_LEADER_SELECTED");
        assertThat(source).contains("MULTI_FACTOR_ALIGNMENT");
        assertThat(source).contains("DRAWDOWN_TRAP");
        assertThat(source).contains("CONFLICT_HEAVY");
        assertThat(source).contains("EXTREME_OVEREXTENSION");
        assertThat(source).contains("HARD_CAP_69");
        assertThat(source).contains("SOFT_CAP_84");
        assertThat(source).contains("validateScoreCap");
        assertThat(source).contains("SCORE_CAP_VIOLATION");
        assertThat(source).contains("SCORE_CAP_TOLERATED");
        assertThat(source).contains("TOP_PICK_GUARD_VIOLATION");
        assertThat(source).contains("normalizationWarnings");
        assertThat(source).contains("ENUM_NORMALIZED");
        assertThat(source).contains("ENUM_MISFILED_TOLERATED");
        assertThat(source).contains("POSITIVE_EVIDENCE_ALIASES");
        assertThat(source).contains("POSITIVE_EVIDENCE_MISFILED_TOLERATED");
        assertThat(source).contains("RISK_FLAG_MISFILED_TOLERATED");
        assertThat(source).contains("REASON_CODE_ALIASES");
        assertThat(source).contains("EVIDENCE_CODES_EMPTY");
        assertThat(source).contains("hasAtLeastOneValue");
        assertThat(source).contains("positiveEvidenceCodes");
        assertThat(source).contains("riskFlagCodes");
        assertThat(source).contains("reasonCode");
        assertThat(source).contains("REASONING_ENUM_FIELDS");
        assertThat(source).contains("SIGNED_CONTRIBUTION_FINAL_SCORE_MISMATCH");
        assertThat(source).contains("Responsibility boundary");
        assertThat(source).contains("Granite is a bounded reviewer");
        assertThat(source).contains("RECOVERY_CANDIDATE");
        assertThat(source).contains("EXTREME_OVEREXTENSION");
        assertThat(source).contains("HARD_CAP_54");
        assertThat(source).contains("HARD_CAP_69");
        assertThat(source).contains("SOFT_CAP_84");
        assertThat(source).contains("previewCandidates(");
        assertThat(source).contains("OFFSET ?");
    }
}
