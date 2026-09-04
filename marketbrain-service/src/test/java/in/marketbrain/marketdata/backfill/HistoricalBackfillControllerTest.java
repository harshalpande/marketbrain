package in.marketbrain.marketdata.backfill;

import in.marketbrain.marketdata.universe.Nifty500SnapshotService;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class HistoricalBackfillControllerTest {

    @Test
    void returnsAUsefulProblemDetailWhenListingEnrichmentIsRejected() {
        ListingBoundaryEnrichmentService enrichmentService = mock(ListingBoundaryEnrichmentService.class);
        HistoricalBackfillController controller = new HistoricalBackfillController(
                mock(Nifty500SnapshotService.class),
                mock(HistoricalBackfillJobService.class),
                mock(BackfillQualityService.class),
                mock(QualityResolutionService.class),
                mock(LargeMoveEvidenceService.class),
                mock(RemainingDataAnalysisService.class),
                mock(RemainingDataRemediationService.class),
                enrichmentService);
        when(enrichmentService.enrich(15, 200, "a".repeat(64)))
                .thenThrow(new IllegalStateException(
                        "NSE listing metadata did not match the selected symbol and ISIN for: [HFCL]"));

        var response = controller.enrichNextBatchListingBoundaries(15, 200, "a".repeat(64));

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.CONFLICT);
        assertThat(response.getBody()).isInstanceOf(ProblemDetail.class);
        ProblemDetail problem = (ProblemDetail) response.getBody();
        assertThat(problem.getTitle()).isEqualTo("Listing-boundary enrichment rejected");
        assertThat(problem.getDetail()).contains("HFCL");
        assertThat(problem.getProperties())
                .containsEntry("operation", "NIFTY500_LISTING_BOUNDARY_ENRICHMENT");
    }
}
