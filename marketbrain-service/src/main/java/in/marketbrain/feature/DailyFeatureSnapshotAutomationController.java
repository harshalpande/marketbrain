package in.marketbrain.feature;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDate;

@RestController
@RequestMapping("/api/v1/features/daily-automation")
public class DailyFeatureSnapshotAutomationController {

    private final DailyFeatureSnapshotAutomationService service;

    public DailyFeatureSnapshotAutomationController(DailyFeatureSnapshotAutomationService service) {
        this.service = service;
    }

    @GetMapping("/status")
    public DailyFeatureSnapshotAutomationStatus status(@RequestParam LocalDate targetDate) {
        try {
            return service.status(targetDate);
        } catch (IllegalArgumentException exception) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, exception.getMessage());
        }
    }
}
