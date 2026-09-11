package in.marketbrain.training;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

@RestController
@RequestMapping("/api/v1/training")
public class PrototypeSwingOllamaScoreCalibrationPreviewController {

    private final PrototypeSwingOllamaScoreCalibrationPreviewService service;

    public PrototypeSwingOllamaScoreCalibrationPreviewController(
            PrototypeSwingOllamaScoreCalibrationPreviewService service
    ) {
        this.service = service;
    }

    @PostMapping("/prototype-swing-ollama-score-calibration-preview")
    public PrototypeSwingOllamaScoreCalibrationPreview preview(
            @RequestBody(required = false) PrototypeSwingOllamaScoreCalibrationRequest request
    ) {
        try {
            return service.preview(request);
        } catch (IllegalArgumentException exception) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, exception.getMessage());
        } catch (IllegalStateException exception) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, exception.getMessage());
        }
    }
}
