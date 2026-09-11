package in.marketbrain.training;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

@RestController
@RequestMapping("/api/v1/training")
public class PrototypeSwingOllamaChunkedRankingPreviewController {

    private final PrototypeSwingOllamaChunkedRankingPreviewService service;

    public PrototypeSwingOllamaChunkedRankingPreviewController(
            PrototypeSwingOllamaChunkedRankingPreviewService service
    ) {
        this.service = service;
    }

    @PostMapping("/prototype-swing-ollama-chunked-ranking-preview")
    public PrototypeSwingOllamaChunkedRankingPreview preview(
            @RequestBody(required = false) PrototypeSwingOllamaChunkedRankingRequest request
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
