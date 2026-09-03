package in.marketbrain.marketdata.upstox;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.stereotype.Component;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeFormatterBuilder;
import java.time.format.DateTimeParseException;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.zip.GZIPInputStream;

@Component
public class UpstoxResponseParser {

    private static final DateTimeFormatter PROVIDER_DATE = new DateTimeFormatterBuilder()
            .parseCaseInsensitive()
            .appendPattern("d MMM uuuu")
            .toFormatter(Locale.ENGLISH);

    private final ObjectMapper objectMapper;

    public UpstoxResponseParser(ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
    }

    public List<UpstoxInstrument> parseInstruments(byte[] payload) throws IOException {
        try (InputStream input = instrumentPayloadStream(payload)) {
            return objectMapper.readerForListOf(UpstoxInstrument.class).readValue(input);
        }
    }

    public UpstoxQuote parseQuote(String payload, String requestedInstrumentKey) throws IOException {
        JsonNode data = objectMapper.readTree(payload).path("data");
        if (!data.isObject() || data.isEmpty()) {
            throw new IOException("Provider response did not contain quote data");
        }
        JsonNode quote = data.elements().next();
        return new UpstoxQuote(
                textOrFallback(quote.path("instrument_token"), requestedInstrumentKey),
                textOrNull(quote.path("symbol")),
                decimalOrNull(quote.path("last_price")),
                decimalOrNull(quote.path("ohlc").path("close")),
                decimalOrNull(quote.path("volume")),
                instantOrNull(quote.path("timestamp")),
                instantOrNull(quote.path("last_trade_time"))
        );
    }

    public List<UpstoxCandle> parseCandles(String payload) throws IOException {
        JsonNode candles = objectMapper.readTree(payload).path("data").path("candles");
        if (!candles.isArray()) {
            throw new IOException("Provider response did not contain candle data");
        }
        List<UpstoxCandle> result = new ArrayList<>();
        for (JsonNode row : candles) {
            if (!row.isArray() || row.size() < 6) {
                continue;
            }
            result.add(new UpstoxCandle(
                    instantOrNull(row.get(0)),
                    decimalOrNull(row.get(1)),
                    decimalOrNull(row.get(2)),
                    decimalOrNull(row.get(3)),
                    decimalOrNull(row.get(4)),
                    decimalOrNull(row.get(5))
            ));
        }
        return result;
    }

    public List<UpstoxCorporateAction> parseCorporateActions(String payload) throws IOException {
        JsonNode events = objectMapper.readTree(payload).path("data");
        if (!events.isArray()) {
            throw new IOException("Provider response did not contain corporate-action data");
        }
        List<UpstoxCorporateAction> result = new ArrayList<>();
        for (JsonNode event : events) {
            String name = textOrNull(event.path("name"));
            Map<String, String> details = eventDetails(event.path("event_details"));
            LocalDate recordOn = detailDate(details, "record date");
            LocalDate announcedOn = detailDate(details, "announcement date");
            LocalDate effectiveOn = exDate(details);
            if (effectiveOn == null) {
                effectiveOn = dateOrNull(event.path("expiry_date"));
            }
            if (effectiveOn == null) {
                effectiveOn = recordOn;
            }
            if (name == null || effectiveOn == null) {
                continue;
            }
            result.add(new UpstoxCorporateAction(
                    name,
                    actionType(name),
                    effectiveOn,
                    announcedOn,
                    recordOn,
                    decimalOrNull(event.path("amount")),
                    textOrNull(event.path("ratio")),
                    flattenedDetails(details)
            ));
        }
        return List.copyOf(result);
    }

    private Map<String, String> eventDetails(JsonNode node) {
        Map<String, String> details = new LinkedHashMap<>();
        if (!node.isArray()) {
            return details;
        }
        for (JsonNode item : node) {
            String name = textOrNull(item.path("name"));
            String value = textOrNull(item.path("value"));
            if (name != null && value != null) {
                details.put(name.trim(), value.trim());
            }
        }
        return details;
    }

    private LocalDate detailDate(Map<String, String> details, String requiredName) {
        return details.entrySet().stream()
                .filter(entry -> entry.getKey().equalsIgnoreCase(requiredName))
                .map(Map.Entry::getValue)
                .map(this::dateOrNull)
                .filter(value -> value != null)
                .findFirst()
                .orElse(null);
    }

    private LocalDate exDate(Map<String, String> details) {
        return details.entrySet().stream()
                .filter(entry -> {
                    String name = entry.getKey().toLowerCase(Locale.ROOT);
                    return name.startsWith("ex ") && name.endsWith(" date");
                })
                .map(Map.Entry::getValue)
                .map(this::dateOrNull)
                .filter(value -> value != null)
                .findFirst()
                .orElse(null);
    }

    private String flattenedDetails(Map<String, String> details) {
        return details.entrySet().stream()
                .map(entry -> entry.getKey() + "=" + entry.getValue())
                .reduce((left, right) -> left + "; " + right)
                .orElse("");
    }

    private String actionType(String name) {
        String normalized = name.toLowerCase(Locale.ROOT);
        if (normalized.contains("dividend")) {
            return "DIVIDEND";
        }
        if (normalized.contains("bonus")) {
            return "BONUS";
        }
        if (normalized.contains("split")) {
            return "SPLIT";
        }
        if (normalized.contains("right")) {
            return "RIGHTS";
        }
        if (normalized.contains("demerger")) {
            return "DEMERGER";
        }
        if (normalized.contains("merger") || normalized.contains("amalgamation")) {
            return "MERGER";
        }
        return "OTHER";
    }

    private InputStream instrumentPayloadStream(byte[] payload) throws IOException {
        if (payload == null || payload.length == 0) {
            throw new IOException("Instrument payload was empty");
        }
        var input = new ByteArrayInputStream(payload);
        if (payload.length >= 2 && payload[0] == (byte) 0x1f && payload[1] == (byte) 0x8b) {
            return new GZIPInputStream(input);
        }
        return input;
    }

    private String textOrFallback(JsonNode node, String fallback) {
        String value = textOrNull(node);
        return value == null ? fallback : value;
    }

    private String textOrNull(JsonNode node) {
        return node == null || node.isMissingNode() || node.isNull() ? null : node.asText();
    }

    private BigDecimal decimalOrNull(JsonNode node) {
        return node == null || node.isMissingNode() || node.isNull() ? null : node.decimalValue();
    }

    private Instant instantOrNull(JsonNode node) {
        if (node == null || node.isMissingNode() || node.isNull()) {
            return null;
        }
        if (node.isNumber()) {
            long value = node.longValue();
            return value > 10_000_000_000L ? Instant.ofEpochMilli(value) : Instant.ofEpochSecond(value);
        }
        String raw = node.asText().trim();
        if (raw.matches("\\d+")) {
            try {
                long value = Long.parseLong(raw);
                return value > 10_000_000_000L ? Instant.ofEpochMilli(value) : Instant.ofEpochSecond(value);
            } catch (NumberFormatException ignored) {
                return null;
            }
        }
        try {
            return OffsetDateTime.parse(raw).toInstant();
        } catch (RuntimeException ignored) {
            try {
                return Instant.parse(raw);
            } catch (RuntimeException invalidTimestamp) {
                return null;
            }
        }
    }

    private LocalDate dateOrNull(JsonNode node) {
        return node == null || node.isMissingNode() || node.isNull() ? null : dateOrNull(node.asText());
    }

    private LocalDate dateOrNull(String raw) {
        if (raw == null || raw.isBlank()) {
            return null;
        }
        try {
            return LocalDate.parse(raw.trim(), PROVIDER_DATE);
        } catch (DateTimeParseException ignored) {
            try {
                return LocalDate.parse(raw.trim(), DateTimeFormatter.ISO_LOCAL_DATE);
            } catch (DateTimeParseException invalidDate) {
                return null;
            }
        }
    }
}
