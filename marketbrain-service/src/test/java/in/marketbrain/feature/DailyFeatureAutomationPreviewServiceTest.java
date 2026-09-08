package in.marketbrain.feature;

import in.marketbrain.marketdata.backfill.BackfillQualityReport;
import in.marketbrain.marketdata.backfill.BackfillQualityService;
import in.marketbrain.marketdata.daily.DailyEnrichmentRunSummary;
import in.marketbrain.marketdata.daily.DailyEnrichmentService;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;

import java.sql.ResultSet;
import java.time.LocalDate;
import java.util.Collections;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

class DailyFeatureAutomationPreviewServiceTest {

    private static final LocalDate TARGET_DATE = LocalDate.of(2026, 9, 8);
    private static final UUID SNAPSHOT_ID = UUID.fromString("68117add-3ebe-4681-82fc-ff5613ecd869");
    private static final UUID DAILY_RUN_ID = UUID.fromString("8a0c3e77-827d-4dc5-a9a1-30ca7523bafe");
    private static final String DAILY_HASH = "a".repeat(64);
    private static final String FEATURE_HASH = "b".repeat(64);

    @Test
    @SuppressWarnings("unchecked")
    void identifiesACompleteDailyHandoffAsReadyToPersist() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        DailyEnrichmentService dailyService = mock(DailyEnrichmentService.class);
        BackfillQualityService qualityService = mock(BackfillQualityService.class);
        FeatureUniversePreviewService featureService = mock(FeatureUniversePreviewService.class);
        BackfillQualityReport quality = passingQuality();
        when(dailyService.findForTarget(TARGET_DATE)).thenReturn(Optional.of(completedDailyRun()));
        when(qualityService.audit(DAILY_RUN_ID, false)).thenReturn(quality);
        when(featureService.preview(TARGET_DATE)).thenReturn(featurePreview());
        when(jdbc.queryForObject(anyString(), eq(Integer.class), any(), eq(SNAPSHOT_ID)))
                .thenReturn(500);
        when(jdbc.query(anyString(), any(RowMapper.class), eq(SNAPSHOT_ID), any(), eq("TECHNICAL_V1")))
                .thenReturn(List.of());
        DailyFeatureAutomationPreviewService service = new DailyFeatureAutomationPreviewService(
                jdbc, dailyService, qualityService, featureService);

        DailyFeatureAutomationPreview result = service.preview(TARGET_DATE);

        assertThat(result.status()).isEqualTo("READY");
        assertThat(result.persistenceAction()).isEqualTo("READY_TO_PERSIST");
        assertThat(result.targetDateCandleCount()).isEqualTo(500);
        assertThat(result.databaseWritesPerformed()).isFalse();
        assertThat(org.mockito.Mockito.mockingDetails(jdbc).getInvocations())
                .allMatch(invocation -> !"update".equals(invocation.getMethod().getName()));
    }

    @Test
    @SuppressWarnings("unchecked")
    void recognizesAnExistingCompletedSnapshotWithTheSameManifest() throws Exception {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        DailyEnrichmentService dailyService = mock(DailyEnrichmentService.class);
        BackfillQualityService qualityService = mock(BackfillQualityService.class);
        FeatureUniversePreviewService featureService = mock(FeatureUniversePreviewService.class);
        BackfillQualityReport quality = passingQuality();
        UUID featureRunId = UUID.randomUUID();
        ResultSet resultSet = mock(ResultSet.class);
        when(resultSet.getObject("id", UUID.class)).thenReturn(featureRunId);
        when(resultSet.getString("status")).thenReturn("COMPLETED");
        when(resultSet.getString("source_manifest_hash")).thenReturn(FEATURE_HASH);
        when(dailyService.findForTarget(TARGET_DATE)).thenReturn(Optional.of(completedDailyRun()));
        when(qualityService.audit(DAILY_RUN_ID, false)).thenReturn(quality);
        when(featureService.preview(TARGET_DATE)).thenReturn(featurePreview());
        when(jdbc.queryForObject(anyString(), eq(Integer.class), any(), eq(SNAPSHOT_ID)))
                .thenReturn(500);
        when(jdbc.query(anyString(), any(RowMapper.class), eq(SNAPSHOT_ID), any(), eq("TECHNICAL_V1")))
                .thenAnswer(invocation -> {
                    RowMapper<?> mapper = invocation.getArgument(1);
                    return List.of(mapper.mapRow(resultSet, 0));
                });
        DailyFeatureAutomationPreviewService service = new DailyFeatureAutomationPreviewService(
                jdbc, dailyService, qualityService, featureService);

        DailyFeatureAutomationPreview result = service.preview(TARGET_DATE);

        assertThat(result.status()).isEqualTo("READY");
        assertThat(result.persistenceAction()).isEqualTo("ALREADY_PERSISTED");
        assertThat(result.existingFeatureSnapshotRunId()).isEqualTo(featureRunId);
        assertThat(result.databaseWritesPerformed()).isFalse();
    }

    @Test
    void refusesToAnalyzeFeaturesWithoutACompletedDailyRun() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        DailyEnrichmentService dailyService = mock(DailyEnrichmentService.class);
        BackfillQualityService qualityService = mock(BackfillQualityService.class);
        FeatureUniversePreviewService featureService = mock(FeatureUniversePreviewService.class);
        when(dailyService.findForTarget(TARGET_DATE)).thenReturn(Optional.empty());
        DailyFeatureAutomationPreviewService service = new DailyFeatureAutomationPreviewService(
                jdbc, dailyService, qualityService, featureService);

        assertThatThrownBy(() -> service.preview(TARGET_DATE))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("No daily enrichment run");

        verifyNoInteractions(jdbc, qualityService, featureService);
    }

    private DailyEnrichmentRunSummary completedDailyRun() {
        return new DailyEnrichmentRunSummary(
                DAILY_RUN_ID, "COMPLETED", SNAPSHOT_ID, LocalDate.of(2026, 9, 5), TARGET_DATE,
                DAILY_HASH, 500, 500, 0, 0, 0, 500, 0, 1_000, 0, 100.0,
                0, null, null, true, true, "complete");
    }

    private FeatureUniversePreview featurePreview() {
        FeaturePreview item = new FeaturePreview(
                "INSUFFICIENT_HISTORY", "TEST", "TECHNICAL_V1", TARGET_DATE, TARGET_DATE,
                200, 200, 0, null, null, true, false, "test");
        return new FeatureUniversePreview(
                "REVIEW_REQUIRED", "TECHNICAL_V1", TARGET_DATE, SNAPSHOT_ID,
                LocalDate.of(2026, 9, 2), 500, 485, 0, 15, 0, 485,
                100_000, 100_000, 0, FEATURE_HASH, true, false,
                Collections.nCopies(500, item), "complete");
    }

    private BackfillQualityReport passingQuality() {
        BackfillQualityReport quality = mock(BackfillQualityReport.class);
        when(quality.jobId()).thenReturn(DAILY_RUN_ID);
        when(quality.jobStatus()).thenReturn("COMPLETED");
        when(quality.qualityStatus()).thenReturn("PASS");
        when(quality.requestedTo()).thenReturn(TARGET_DATE);
        when(quality.instrumentCount()).thenReturn(500);
        return quality;
    }
}
