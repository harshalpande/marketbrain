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
public class SwingTrainingDatasetPreviewController {

    private final SwingTrainingDatasetPreviewService service;

    public SwingTrainingDatasetPreviewController(SwingTrainingDatasetPreviewService service) {
        this.service = service;
    }

    @GetMapping("/swing-cohort-preview")
    public SwingTrainingDatasetPreview preview(
            @RequestParam LocalDate asOf,
            @RequestParam LocalDate labelThrough,
            @RequestParam(defaultValue = "50") int assumedRoundTripCostBps
    ) {
        try {
            return service.preview(asOf, labelThrough, assumedRoundTripCostBps);
        } catch (IllegalArgumentException exception) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, exception.getMessage());
        } catch (IllegalStateException exception) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, exception.getMessage());
        }
    }
}
