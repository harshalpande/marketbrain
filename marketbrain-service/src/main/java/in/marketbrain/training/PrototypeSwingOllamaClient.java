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
        return generate(model, prompt, false);
    }

    String generateJson(String model, String prompt) {
        return generate(model, prompt, true);
    }

    Generation generateJsonResult(String model, String prompt) {
        return generateResult(model, prompt, true);
    }

    private String generate(String model, String prompt, boolean jsonMode) {
        return generateResult(model, prompt, jsonMode).text();
    }

    private Generation generateResult(String model, String prompt, boolean jsonMode) {
        long startedAt = System.nanoTime();
        try {
            var body = new java.util.LinkedHashMap<String, Object>();
            body.put("model", model);
            body.put("prompt", prompt);
            body.put("stream", false);
            body.put("options", Map.of(
                    "temperature", 0.05,
                    "num_ctx", 8192
            ));
            if (jsonMode) {
                body.put("format", "json");
            }
            JsonNode response = restClient.post()
                    .uri("/api/generate")
                    .body(body)
                    .retrieve()
                    .body(JsonNode.class);
            String text = response == null ? "" : response.path("response").asText("");
            if (text.isBlank()) {
                throw new OllamaTransportException();
            }
            long elapsedMillis = (System.nanoTime() - startedAt) / 1_000_000L;
            return new Generation(
                    text.strip(),
                    elapsedMillis,
                    response == null ? 0L : response.path("total_duration").asLong(0L),
                    response == null ? 0 : response.path("prompt_eval_count").asInt(0),
                    response == null ? 0 : response.path("eval_count").asInt(0)
            );
        } catch (RestClientException exception) {
            throw new OllamaTransportException();
        }
    }

    record Generation(
            String text,
            long elapsedMillis,
            long ollamaTotalDurationNanos,
            int promptEvalCount,
            int evalCount
    ) {
    }

    static final class OllamaTransportException extends RuntimeException {
        OllamaTransportException() {
            super("Ollama request failed without exposing provider details.");
        }
    }
}
