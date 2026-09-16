package in.marketbrain.training;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/training")
public class PrototypeSwingOllamaIntelligenceScorecardController {

    private final PrototypeSwingOllamaIntelligenceScorecardService service;
    private final ObjectMapper objectMapper;

    public PrototypeSwingOllamaIntelligenceScorecardController(
            PrototypeSwingOllamaIntelligenceScorecardService service,
            ObjectMapper objectMapper
    ) {
        this.service = service;
        this.objectMapper = objectMapper;
    }

    @PostMapping("/prototype-swing-ollama-intelligence-scorecard")
    public PrototypeSwingOllamaIntelligenceScorecard scorecard(
            @RequestBody JsonNode request
    ) {
        if (request == null || request.isNull() || request.isMissingNode()) {
            throw new IllegalArgumentException("completed chunked ranking result JSON is required.");
        }
        JsonNode result = request.hasNonNull("result") ? request.path("result") : request;
        PrototypeSwingOllamaChunkedRankingPreview preview =
                objectMapper.convertValue(result, PrototypeSwingOllamaChunkedRankingPreview.class);
        return service.scorecard(preview);
    }
}
