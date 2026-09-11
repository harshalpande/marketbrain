package in.marketbrain.training;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

@RestController
@RequestMapping("/api/v1/training")
public class PrototypeSwingOllamaRankingPreviewController {

    private final PrototypeSwingOllamaRankingPreviewService service;

    public PrototypeSwingOllamaRankingPreviewController(PrototypeSwingOllamaRankingPreviewService service) {
        this.service = service;
    }

    @PostMapping("/prototype-swing-ollama-ranking-preview")
    public PrototypeSwingOllamaRankingPreview preview(
            @RequestBody(required = false) PrototypeSwingOllamaRankingRequest request
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
