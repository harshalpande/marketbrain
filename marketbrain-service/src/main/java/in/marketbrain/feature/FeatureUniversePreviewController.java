package in.marketbrain.feature;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDate;

@RestController
@RequestMapping("/api/v1/features")
public class FeatureUniversePreviewController {

    private final FeatureUniversePreviewService service;

    public FeatureUniversePreviewController(FeatureUniversePreviewService service) {
        this.service = service;
    }

    @GetMapping("/universe-preview")
    public FeatureUniversePreview preview(@RequestParam LocalDate asOf) {
        try {
            return service.preview(asOf);
        } catch (IllegalArgumentException exception) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, exception.getMessage());
        } catch (IllegalStateException exception) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, exception.getMessage());
        }
    }
}
