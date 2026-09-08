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
public class FeaturePreviewController {

    private final FeaturePreviewService service;

    public FeaturePreviewController(FeaturePreviewService service) {
        this.service = service;
    }

    @GetMapping("/preview")
    public FeaturePreview preview(
            @RequestParam String symbol,
            @RequestParam LocalDate asOf
    ) {
        try {
            return service.preview(symbol, asOf);
        } catch (IllegalArgumentException exception) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, exception.getMessage());
        }
    }
}
