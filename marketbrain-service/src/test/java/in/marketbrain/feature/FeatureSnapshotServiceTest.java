package in.marketbrain.feature;

import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;

import java.time.LocalDate;
import java.util.Collections;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

class FeatureSnapshotServiceTest {

    private static final LocalDate AS_OF = LocalDate.of(2026, 9, 8);
    private static final String REVIEWED_HASH = "a".repeat(64);

    @Test
    void rejectsAChangedLiveManifestBeforeAnyDatabaseWrite() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        FeatureUniversePreviewService previewService = mock(FeatureUniversePreviewService.class);
        FeatureUniverseManifestHasher hasher = mock(FeatureUniverseManifestHasher.class);
        when(previewService.preview(AS_OF)).thenReturn(analysis(REVIEWED_HASH));
        FeatureSnapshotService service = new FeatureSnapshotService(jdbc, previewService, hasher);

        assertThatThrownBy(() -> service.persist(new FeatureSnapshotRequest(
                AS_OF, "b".repeat(64), "Harshal Pande")))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("no longer matches");

        verifyNoInteractions(jdbc, hasher);
    }

    @Test
    void rejectsAnEligibleClassificationWithoutACompleteVector() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        FeatureUniversePreviewService previewService = mock(FeatureUniversePreviewService.class);
        FeatureUniverseManifestHasher hasher = mock(FeatureUniverseManifestHasher.class);
        when(previewService.preview(AS_OF)).thenReturn(analysis(REVIEWED_HASH));
        FeatureSnapshotService service = new FeatureSnapshotService(jdbc, previewService, hasher);

        assertThatThrownBy(() -> service.persist(new FeatureSnapshotRequest(
                AS_OF, REVIEWED_HASH, "Harshal Pande")))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("incomplete");

        verifyNoInteractions(jdbc, hasher);
    }

    private FeatureUniversePreview analysis(String manifestHash) {
        FeaturePreview incomplete = new FeaturePreview(
                "ELIGIBLE", "RELIANCE", "TECHNICAL_V1", AS_OF, AS_OF,
                252, 252, 0, null, null, true, false, "test");
        return new FeatureUniversePreview(
                "REVIEW_REQUIRED", "TECHNICAL_V1", AS_OF,
                UUID.fromString("68117add-3ebe-4681-82fc-ff5613ecd869"),
                LocalDate.of(2026, 9, 2), 500, 500, 0, 0, 0, 500,
                126_000, 126_000, 0, manifestHash, true, false,
                Collections.nCopies(500, incomplete), "test");
    }
}
