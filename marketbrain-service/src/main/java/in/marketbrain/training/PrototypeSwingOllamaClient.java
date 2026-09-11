package in.marketbrain.training;

import com.fasterxml.jackson.databind.JsonNode;
import in.marketbrain.configuration.MarketBrainProperties;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;

import java.util.Map;

@Component
class PrototypeSwingOllamaClient {

    private final RestClient restClient;

    @Autowired
    PrototypeSwingOllamaClient(RestClient.Builder builder, MarketBrainProperties properties) {
        this(builder.baseUrl(properties.ollama().baseUrl()).build());
    }

    PrototypeSwingOllamaClient(RestClient restClient) {
        this.restClient = restClient;
    }

    String generate(String model, String prompt) {
        try {
            JsonNode response = restClient.post()
                    .uri("/api/generate")
                    .body(Map.of(
                            "model", model,
                            "prompt", prompt,
                            "stream", false,
                            "options", Map.of(
                                    "temperature", 0.1,
                                    "num_ctx", 8192
                            )
                    ))
                    .retrieve()
                    .body(JsonNode.class);
            String text = response == null ? "" : response.path("response").asText("");
            if (text.isBlank()) {
                throw new OllamaTransportException();
            }
            return text.strip();
        } catch (RestClientException exception) {
            throw new OllamaTransportException();
        }
    }

    static final class OllamaTransportException extends RuntimeException {
        OllamaTransportException() {
            super("Ollama request failed without exposing provider details.");
        }
    }
}
