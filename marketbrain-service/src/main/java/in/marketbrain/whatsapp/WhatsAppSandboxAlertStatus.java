package in.marketbrain.whatsapp;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

record WhatsAppSandboxAlertStatus(
        String status,
        UUID alertId,
        String alertType,
        Instant expiresAt,
        int processedActionCount,
        List<ActionStatus> actions,
        boolean actionExecutionEnabled,
        String executionMode
) {
    record ActionStatus(String action, boolean processed, String result) {
    }
}
