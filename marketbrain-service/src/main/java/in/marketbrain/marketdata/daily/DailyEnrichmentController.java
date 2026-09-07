package in.marketbrain.marketdata.daily;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDate;
import java.util.UUID;

@RestController
@RequestMapping("/api/v1/market-data/daily-enrichment")
public class DailyEnrichmentController {

    private final DailyEnrichmentService service;

    public DailyEnrichmentController(DailyEnrichmentService service) {
        this.service = service;
    }

    @GetMapping("/preview")
    public DailyEnrichmentPreview preview(@RequestParam(required = false) LocalDate targetDate) {
        try {
            return service.preview(targetDate == null ? service.defaultTargetDate() : targetDate);
        } catch (IllegalArgumentException exception) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, exception.getMessage());
        } catch (IllegalStateException exception) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, exception.getMessage());
        }
    }

    @PostMapping("/runs")
    public DailyEnrichmentRunSummary create(
            @RequestParam(required = false) LocalDate targetDate,
            @RequestParam String expectedManifestHash
    ) {
        try {
            return service.create(targetDate == null ? service.defaultTargetDate() : targetDate,
                    expectedManifestHash);
        } catch (IllegalArgumentException exception) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, exception.getMessage());
        } catch (IllegalStateException exception) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, exception.getMessage());
        }
    }

    @PostMapping("/runs/start")
    public DailyEnrichmentRunSummary start(@RequestParam UUID runId) {
        try {
            return service.start(runId);
        } catch (IllegalArgumentException exception) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, exception.getMessage());
        } catch (IllegalStateException exception) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, exception.getMessage());
        }
    }

    @GetMapping("/runs/status")
    public DailyEnrichmentRunSummary status(@RequestParam UUID runId) {
        try {
            return service.summary(runId);
        } catch (IllegalArgumentException exception) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, exception.getMessage());
        }
    }

    @GetMapping("/runs/latest")
    public DailyEnrichmentRunSummary latest() {
        try {
            return service.latestSummary();
        } catch (IllegalArgumentException exception) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, exception.getMessage());
        }
    }
}
