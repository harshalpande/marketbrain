package in.marketbrain.marketdata.backfill;

import in.marketbrain.marketdata.universe.Nifty500SnapshotImportResult;
import in.marketbrain.marketdata.universe.Nifty500SnapshotService;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDate;
import java.time.ZoneId;
import java.util.UUID;

@RestController
@RequestMapping("/api/v1/market-data/backfills")
public class HistoricalBackfillController {

    private static final ZoneId INDIA = ZoneId.of("Asia/Kolkata");

    private final Nifty500SnapshotService snapshotService;
    private final HistoricalBackfillJobService jobService;
    private final BackfillQualityService qualityService;

    public HistoricalBackfillController(
            Nifty500SnapshotService snapshotService,
            HistoricalBackfillJobService jobService,
            BackfillQualityService qualityService
    ) {
        this.snapshotService = snapshotService;
        this.jobService = jobService;
        this.qualityService = qualityService;
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
}
