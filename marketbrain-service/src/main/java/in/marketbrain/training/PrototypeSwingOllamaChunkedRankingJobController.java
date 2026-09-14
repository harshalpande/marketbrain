package in.marketbrain.training;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import java.util.UUID;

@RestController
@RequestMapping("/api/v1/training")
public class PrototypeSwingOllamaChunkedRankingJobController {

    private final PrototypeSwingOllamaChunkedRankingJobService service;

    public PrototypeSwingOllamaChunkedRankingJobController(
            PrototypeSwingOllamaChunkedRankingJobService service
    ) {
        this.service = service;
    }

    @PostMapping("/prototype-swing-ollama-chunked-ranking-jobs")
    public PrototypeSwingOllamaChunkedRankingJobStatus submit(
            @RequestBody(required = false) PrototypeSwingOllamaChunkedRankingRequest request
    ) {
        return service.submit(request);
    }

    @GetMapping("/prototype-swing-ollama-chunked-ranking-jobs/{jobId}")
    public PrototypeSwingOllamaChunkedRankingJobStatus status(@PathVariable UUID jobId) {
        try {
            return service.status(jobId);
        } catch (IllegalArgumentException exception) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, exception.getMessage());
        }
    }
}
