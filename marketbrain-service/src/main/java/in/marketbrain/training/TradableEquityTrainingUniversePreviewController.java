package in.marketbrain.training;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDate;

@RestController
@RequestMapping("/api/v1/training")
public class TradableEquityTrainingUniversePreviewController {

    private final TradableEquityTrainingUniversePreviewService service;

    public TradableEquityTrainingUniversePreviewController(
            TradableEquityTrainingUniversePreviewService service
    ) {
        this.service = service;
    }

    @GetMapping("/tradable-equity-universe-preview")
    public TradableEquityTrainingUniversePreview preview(
            @RequestParam LocalDate asOf,
            @RequestParam(defaultValue = "252") int minimumEligibleObservations
    ) {
        try {
            return service.preview(asOf, minimumEligibleObservations);
        } catch (IllegalArgumentException exception) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, exception.getMessage());
        } catch (IllegalStateException exception) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, exception.getMessage());
        }
    }
}
