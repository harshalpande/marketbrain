package in.marketbrain.news;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.math.BigDecimal;
import java.time.Instant;
import java.time.format.DateTimeParseException;
import java.util.ArrayList;
import java.util.List;

@Component
public class MarketauxNewsResponseParser {

    private final ObjectMapper objectMapper;

    public MarketauxNewsResponseParser(ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
    }

    public List<NewsArticleCandidate> parse(String sourceKey, String payload) {
        try {
            JsonNode root = objectMapper.readTree(payload);
            JsonNode data = root.path("data");
            if (!data.isArray()) {
                return List.of();
            }
            List<NewsArticleCandidate> articles = new ArrayList<>();
            for (JsonNode item : data) {
                String url = text(item, "url");
                String title = text(item, "title");
                if (url.isBlank() || title.isBlank()) {
                    continue;
                }
                String providerItemId = text(item, "uuid");
                if (providerItemId.isBlank()) {
                    providerItemId = url;
                }
                articles.add(new NewsArticleCandidate(
                        sourceKey,
                        providerItemId,
                        url,
                        NewsUrlSupport.domain(url),
                        title,
                        firstNonBlank(text(item, "snippet"), text(item, "description")),
                        instant(text(item, "published_at")),
                        entities(item.path("entities"))));
            }
            return List.copyOf(articles);
        } catch (IOException exception) {
            throw new IllegalArgumentException("Marketaux response is not valid JSON.", exception);
        }
    }

    private List<NewsEntityCandidate> entities(JsonNode nodes) {
        if (!nodes.isArray()) {
            return List.of();
        }
        List<NewsEntityCandidate> entities = new ArrayList<>();
        for (JsonNode node : nodes) {
            String symbol = text(node, "symbol");
            if (symbol.isBlank()) {
                continue;
            }
            entities.add(new NewsEntityCandidate(
                    symbol,
                    text(node, "name"),
                    text(node, "exchange"),
                    text(node, "country"),
                    decimal(node.path("sentiment_score")),
                    decimal(node.path("match_score"))));
        }
        return List.copyOf(entities);
    }

    private Instant instant(String value) {
        if (value.isBlank()) {
            return null;
        }
        try {
            return Instant.parse(value);
        } catch (DateTimeParseException exception) {
            return null;
        }
    }

    private BigDecimal decimal(JsonNode node) {
        if (!node.isNumber()) {
            return null;
        }
        return node.decimalValue();
    }

    private String text(JsonNode node, String field) {
        JsonNode value = node.path(field);
        return value.isTextual() ? value.asText().trim() : "";
    }

    private String firstNonBlank(String first, String second) {
        return first.isBlank() ? second : first;
    }
}
