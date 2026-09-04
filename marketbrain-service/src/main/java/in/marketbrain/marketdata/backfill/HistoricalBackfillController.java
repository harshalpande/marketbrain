package in.marketbrain.marketdata.backfill;

import in.marketbrain.marketdata.universe.Nifty500SnapshotImportResult;
import in.marketbrain.marketdata.universe.Nifty500SnapshotService;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDate;
import java.time.ZoneId;
import java.util.List;
import java.util.UUID;

@RestController
@RequestMapping("/api/v1/market-data/backfills")
public class HistoricalBackfillController {

    private static final ZoneId INDIA = ZoneId.of("Asia/Kolkata");

    private final Nifty500SnapshotService snapshotService;
    private final HistoricalBackfillJobService jobService;
    private final BackfillQualityService qualityService;
    private final QualityResolutionService resolutionService;
    private final LargeMoveEvidenceService largeMoveEvidenceService;
    private final RemainingDataAnalysisService remainingDataAnalysisService;
    private final RemainingDataRemediationService remainingDataRemediationService;
    private final ListingBoundaryEnrichmentService listingBoundaryEnrichmentService;

    public HistoricalBackfillController(
            Nifty500SnapshotService snapshotService,
            HistoricalBackfillJobService jobService,
            BackfillQualityService qualityService,
            QualityResolutionService resolutionService,
            LargeMoveEvidenceService largeMoveEvidenceService,
            RemainingDataAnalysisService remainingDataAnalysisService,
            RemainingDataRemediationService remainingDataRemediationService,
            ListingBoundaryEnrichmentService listingBoundaryEnrichmentService
    ) {
        this.snapshotService = snapshotService;
        this.jobService = jobService;
        this.qualityService = qualityService;
        this.resolutionService = resolutionService;
        this.largeMoveEvidenceService = largeMoveEvidenceService;
        this.remainingDataAnalysisService = remainingDataAnalysisService;
        this.remainingDataRemediationService = remainingDataRemediationService;
        this.listingBoundaryEnrichmentService = listingBoundaryEnrichmentService;
    }

    @PostMapping("/nifty500/current-snapshot")
    public Nifty500SnapshotImportResult importCurrentSnapshot() {
        return snapshotService.importCurrent(LocalDate.now(INDIA));
    }

    @PostMapping("/pilot")
    public BackfillJobSummary createPilot(@RequestParam(defaultValue = "15") int years) {
        try {
            return jobService.createPilot(years);
        } catch (IllegalArgumentException | IllegalStateException exception) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, exception.getMessage());
        }
    }

    @PostMapping("/nifty500/next-batch")
    public ExpansionBatchCreationResult createNextExpansionBatch(
            @RequestParam(defaultValue = "15") int years,
            @RequestParam(defaultValue = "50") int batchSize,
            @RequestParam String expectedManifestHash
    ) {
        try {
            return jobService.createNextExpansionBatch(years, batchSize, expectedManifestHash);
        } catch (IllegalArgumentException | IllegalStateException exception) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, exception.getMessage());
        }
    }

    @GetMapping("/nifty500/next-batch-preview")
    public ExpansionBatchPreview previewNextExpansionBatch(
            @RequestParam(defaultValue = "15") int years,
            @RequestParam(defaultValue = "50") int batchSize
    ) {
        try {
            return jobService.previewNextExpansionBatch(years, batchSize);
        } catch (IllegalArgumentException | IllegalStateException exception) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, exception.getMessage());
        }
    }

    @PostMapping("/nifty500/next-batch/listing-boundaries")
    public ListingBoundaryEnrichmentReport enrichNextBatchListingBoundaries(
            @RequestParam(defaultValue = "15") int years,
            @RequestParam(defaultValue = "50") int batchSize,
            @RequestParam String expectedManifestHash
    ) {
        try {
            return listingBoundaryEnrichmentService.enrich(years, batchSize, expectedManifestHash);
        } catch (IllegalArgumentException exception) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, exception.getMessage());
        } catch (IllegalStateException exception) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, exception.getMessage());
        }
    }

    @PostMapping("/start")
    public BackfillJobSummary start(@RequestParam UUID jobId) {
        try {
            return jobService.start(jobId);
        } catch (IllegalArgumentException | IllegalStateException exception) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, exception.getMessage());
        }
    }

    @PostMapping("/pause")
    public BackfillJobSummary pause(@RequestParam UUID jobId) {
        return jobService.pause(jobId);
    }

    @PostMapping("/resume")
    public BackfillJobSummary resume(@RequestParam UUID jobId) {
        try {
            return jobService.resume(jobId);
        } catch (IllegalArgumentException | IllegalStateException exception) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, exception.getMessage());
        }
    }

    @PostMapping("/retry-invalid-data")
    public BackfillRetryResult retryInvalidData(@RequestParam UUID jobId) {
        try {
            return jobService.retryInvalidDataChunks(jobId);
        } catch (IllegalArgumentException | IllegalStateException exception) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, exception.getMessage());
        }
    }

    @GetMapping("/status")
    public BackfillJobSummary status(@RequestParam UUID jobId) {
        try {
            return jobService.summary(jobId);
        } catch (IllegalArgumentException exception) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, exception.getMessage());
        }
    }

    @GetMapping("/latest")
    public BackfillJobSummary latest() {
        try {
            return jobService.latestSummary();
        } catch (IllegalArgumentException exception) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, exception.getMessage());
        }
    }

    @GetMapping("/instruments")
    public List<BackfillJobInstrumentSummary> instruments(@RequestParam UUID jobId) {
        try {
            return jobService.instruments(jobId);
        } catch (IllegalArgumentException exception) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, exception.getMessage());
        }
    }

    @GetMapping("/quality")
    public BackfillQualityReport quality(
            @RequestParam UUID jobId,
            @RequestParam(defaultValue = "false") boolean providerSpotCheck
    ) {
        try {
            return qualityService.audit(jobId, providerSpotCheck);
        } catch (IllegalArgumentException exception) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, exception.getMessage());
        } catch (IllegalStateException exception) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, exception.getMessage());
        }
    }

    @PostMapping("/quality-resolutions")
    public QualityResolutionRecord resolveFinding(@Valid @RequestBody QualityResolutionRequest request) {
        try {
            return resolutionService.resolve(request);
        } catch (IllegalArgumentException exception) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, exception.getMessage());
        } catch (IllegalStateException exception) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, exception.getMessage());
        }
    }

    @PostMapping("/quality-resolutions/revoke")
    public void revokeFinding(@Valid @RequestBody QualityResolutionRevocationRequest request) {
        try {
            resolutionService.revoke(request);
        } catch (IllegalArgumentException exception) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, exception.getMessage());
        } catch (IllegalStateException exception) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, exception.getMessage());
        }
    }

    @GetMapping("/quality-resolutions")
    public List<QualityResolutionRecord> qualityResolutions(@RequestParam UUID jobId) {
        try {
            return resolutionService.current(jobId);
        } catch (IllegalArgumentException exception) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, exception.getMessage());
        } catch (IllegalStateException exception) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, exception.getMessage());
        }
    }

    @GetMapping("/large-move-evidence")
    public LargeMoveEvidenceReport largeMoveEvidence(
            @RequestParam UUID jobId,
            @RequestParam(required = false) String symbol
    ) {
        try {
            return largeMoveEvidenceService.report(jobId, symbol);
        } catch (IllegalArgumentException exception) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, exception.getMessage());
        } catch (IllegalStateException exception) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, exception.getMessage());
        }
    }

    @GetMapping("/remaining-data-analysis")
    public RemainingDataAnalysisReport remainingDataAnalysis(@RequestParam UUID jobId) {
        try {
            return remainingDataAnalysisService.analyze(jobId);
        } catch (IllegalArgumentException exception) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, exception.getMessage());
        } catch (IllegalStateException exception) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, exception.getMessage());
        }
    }

    @PostMapping("/remaining-data-remediation/apply")
    public RemainingDataRemediationReport applyRemainingDataRemediation(
            @Valid @RequestBody RemainingDataRemediationRequest request
    ) {
        try {
            return remainingDataRemediationService.apply(request);
        } catch (IllegalArgumentException exception) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, exception.getMessage());
        } catch (IllegalStateException exception) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, exception.getMessage());
        }
    }

    @GetMapping("/remaining-data-remediation/status")
    public RemainingDataRemediationReport remainingDataRemediationStatus(
            @RequestParam UUID jobId,
            @RequestParam String expectedPlanHash
    ) {
        try {
            return remainingDataRemediationService.status(jobId, expectedPlanHash);
        } catch (IllegalArgumentException exception) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, exception.getMessage());
        } catch (IllegalStateException exception) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, exception.getMessage());
        }
    }
}
