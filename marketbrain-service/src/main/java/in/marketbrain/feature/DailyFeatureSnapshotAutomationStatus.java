package in.marketbrain.feature;

import java.time.LocalDate;
import java.util.UUID;

public record DailyFeatureSnapshotAutomationStatus(
        boolean automationEnabled,
        LocalDate activationDate,
        LocalDate targetDate,
        String status,
        int attempts,
        UUID dailyRunId,
        UUID featureSnapshotRunId,
        String featureManifestHash,
        Integer eligibleCount,
        Integer withheldCount,
        String lastErrorCode,
        String notificationStatus,
        String detail
) {
}
