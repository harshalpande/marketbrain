package in.marketbrain.paper;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import static org.junit.jupiter.api.Assertions.*;

class PaperTelegramVerificationTest {
    @ParameterizedTest @ValueSource(strings={"public", "paper_verify_short", "../other", ""})
    void entrypointRefusesNonFixtureSchemasBeforeIo(String schema) {
        assertThrows(IllegalArgumentException.class, () -> PaperTelegramVerification.main(new String[]{"--prepare",schema}));
    }
    @Test void entrypointRefusesArbitraryModesBeforeIo() {
        assertThrows(IllegalArgumentException.class, () -> PaperTelegramVerification.main(new String[]{"--live","paper_verify_"+"a".repeat(32)}));
        assertThrows(IllegalArgumentException.class, () -> PaperTelegramVerification.main(new String[]{}));
    }
    @Test void rehearsalCannotUseApplicationConnectionOrExternalTransport() throws Exception {
        var path=java.nio.file.Path.of("src/main/java/in/marketbrain/paper/PaperTelegramVerification.java");
        String text=java.nio.file.Files.readString(path);
        assertTrue(text.contains("\"127.0.0.1\",5432,\"paper_fixture\""));
        assertFalse(text.contains("System.getenv")); assertFalse(text.contains("System.getProperty"));
        assertFalse(text.contains("new PaperApprovalHttp.BoundedTransport"));
        assertFalse(text.contains("host.docker.internal"));
    }
}
