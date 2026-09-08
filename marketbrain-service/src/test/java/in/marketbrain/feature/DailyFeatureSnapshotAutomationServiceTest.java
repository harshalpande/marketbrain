package in.marketbrain.feature;

import in.marketbrain.configuration.DailyFeatureSnapshotProperties;
import in.marketbrain.marketdata.daily.DailyEnrichmentNotificationService;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;

import java.time.LocalDate;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

class DailyFeatureSnapshotAutomationServiceTest {

    @Test
    void disabledAutomationCannotClaimOrPersistWork() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        DailyFeatureSnapshotProperties properties = mock(DailyFeatureSnapshotProperties.class);
        DailyFeatureAutomationPreviewService previewService = mock(DailyFeatureAutomationPreviewService.class);
        FeatureSnapshotService snapshotService = mock(FeatureSnapshotService.class);
        DailyEnrichmentNotificationService notificationService =
                mock(DailyEnrichmentNotificationService.class);
        when(properties.enabled()).thenReturn(false);
        DailyFeatureSnapshotAutomationService service = new DailyFeatureSnapshotAutomationService(
                jdbc, properties, previewService, snapshotService, notificationService);

        service.runOnce();

        verifyNoInteractions(jdbc, previewService, snapshotService, notificationService);
    }

    @Test
    void terminalMessagesRemainPaperOnlyAndActionFree() {
        LocalDate date = LocalDate.of(2026, 9, 8);
        var complete = new DailyFeatureSnapshotAutomationService.NotificationOutcome(
                date, UUID.randomUUID(), UUID.randomUUID(), "COMPLETED",
                "a".repeat(64), 485, 15, null);
        var warning = new DailyFeatureSnapshotAutomationService.NotificationOutcome(
                date, UUID.randomUUID(), null, "REVIEW_REQUIRED",
                null, null, null, "DATABASE_QUALITY");

        assertThat(DailyFeatureSnapshotAutomationService.completionMessage(complete))
                .contains("[DAILY FEATURES COMPLETE] PAPER MODE")
                .contains("Eligible vectors: 485")
                .contains("no signal, order, or trading action was created");
        assertThat(DailyFeatureSnapshotAutomationService.warningMessage(warning))
                .contains("[DAILY FEATURES WARNING] PAPER MODE")
                .contains("DATABASE_QUALITY")
                .contains("review is required");
    }
}
