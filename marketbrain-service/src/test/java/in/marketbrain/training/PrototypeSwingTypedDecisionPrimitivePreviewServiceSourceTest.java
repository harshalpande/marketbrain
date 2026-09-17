package in.marketbrain.training;

import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.nio.charset.StandardCharsets;

import static org.assertj.core.api.Assertions.assertThat;

class PrototypeSwingTypedDecisionPrimitivePreviewServiceSourceTest {

    @Test
    void typedDecisionPrimitivePreviewIsReadOnlyAndEnumBandConstrained() throws IOException {
        String source = java.nio.file.Files.readString(
                java.nio.file.Path.of("src/main/java/in/marketbrain/training/"
                        + "PrototypeSwingTypedDecisionPrimitivePreviewService.java"),
                StandardCharsets.UTF_8);
        assertThat(source).doesNotContain("@Transactional");
        assertThat(source).doesNotContain("jdbcTemplate.update");
        assertThat(source).doesNotContain("INSERT INTO");
        assertThat(source).doesNotContain("market_signal");
        assertThat(source).doesNotContain("paper_order");
        assertThat(source).contains("MARKETBRAIN_TYPED_DECISION_PRIMITIVE_V1");
        assertThat(source).contains("MARKETBRAIN_TYPED_DECISION_GBNF_V1");
        assertThat(source).contains("\"REVIEW_REQUIRED\".equals(audit.status())");
        assertThat(source).contains("REJECT");
        assertThat(source).contains("WATCHLIST");
        assertThat(source).contains("SHORTLIST");
        assertThat(source).contains("TOP_PICK");
        assertThat(source).contains("VERY_LOW");
        assertThat(source).contains("scoreBand");
        assertThat(source).contains("confidenceBand");
        assertThat(source).contains("primaryReasonCode");
        assertThat(source).contains("guidedRankingService.candidates");
        assertThat(source).contains("databaseWritesPerformed");
        assertThat(source).contains("signalsCreated");
        assertThat(source).contains("ordersCreated");
    }

    @Test
    void typedDecisionPowerShellScriptHasProgressAndEvidenceFiles() throws IOException {
        String source = java.nio.file.Files.readString(
                java.nio.file.Path.of("../ops/windows/PreviewPrototypeSwingTypedDecisionPrimitives.ps1"),
                StandardCharsets.UTF_8);
        assertThat(source).contains("Write-Progress");
        assertThat(source).contains("Start-Transcript");
        assertThat(source).contains("prototype-swing-typed-decision-primitives");
        assertThat(source).contains("grammarPath");
        assertThat(source).contains("attemptPath");
        assertThat(source).contains("NO_JSON_OBJECT_FOUND");
        assertThat(source).contains("BLOCKED_CANDIDATE_PROMOTED_TO_TOP_PICK");
        assertThat(source).contains("No database write, Ollama call, signal, paper fill, order, broker action");
    }
}
