package in.marketbrain.feature;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDate;

@RestController
@RequestMapping("/api/v1/features/daily-automation-preview")
public class DailyFeatureAutomationPreviewController {

    private final DailyFeatureAutomationPreviewService service;

    public DailyFeatureAutomationPreviewController(DailyFeatureAutomationPreviewService service) {
        this.service = service;
    }

    @GetMapping
    public DailyFeatureAutomationPreview preview(@RequestParam LocalDate targetDate) {
        try {
            return service.preview(targetDate);
        } catch (IllegalArgumentException exception) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, exception.getMessage());
        } catch (IllegalStateException exception) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, exception.getMessage());
        }
    }
}
