package in.marketbrain.marketdata.universe;

import org.springframework.stereotype.Component;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.Reader;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;

@Component
public class CurrentNifty500CsvParser {

    private static final List<String> EXPECTED_HEADER =
            List.of("companyname", "industry", "symbol", "series", "isincode");

    public List<CurrentNifty500Constituent> parse(Reader reader) throws IOException {
        try (var buffered = new BufferedReader(reader)) {
            String firstLine = buffered.readLine();
            if (firstLine == null) {
                throw new IllegalArgumentException("Current NIFTY 500 CSV is empty");
            }
            List<String> header = parseCsvLine(firstLine.replace("\uFEFF", "")).stream()
                    .map(CurrentNifty500CsvParser::normalizeHeader)
                    .toList();
            if (!EXPECTED_HEADER.equals(header)) {
                throw new IllegalArgumentException(
                        "Unexpected current NIFTY 500 header; provider format may have changed");
            }

            List<CurrentNifty500Constituent> records = new ArrayList<>();
            Set<String> uniqueIsins = new HashSet<>();
            String line;
            int lineNumber = 1;
            while ((line = buffered.readLine()) != null) {
                lineNumber++;
                if (line.isBlank()) {
                    continue;
                }
                List<String> fields = parseCsvLine(line);
                if (fields.size() != EXPECTED_HEADER.size()) {
                    throw new IllegalArgumentException("Expected 5 columns at line " + lineNumber);
                }
                var item = new CurrentNifty500Constituent(
                        fields.get(0).trim(), fields.get(1).trim(), fields.get(2).trim(),
                        fields.get(3).trim(), fields.get(4).trim());
                if (!item.isCashEquity()) {
                    throw new IllegalArgumentException("Non-equity or incomplete constituent at line " + lineNumber);
                }
                if (!uniqueIsins.add(item.isin().toUpperCase(Locale.ROOT))) {
                    throw new IllegalArgumentException("Duplicate ISIN at line " + lineNumber);
                }
                records.add(item);
            }
            if (records.size() < 450 || records.size() > 550) {
                throw new IllegalArgumentException(
                        "Current NIFTY 500 source returned an implausible member count: " + records.size());
            }
            return List.copyOf(records);
        }
    }

    private static String normalizeHeader(String value) {
        return value.replace(" ", "").trim().toLowerCase(Locale.ROOT);
    }

    static List<String> parseCsvLine(String line) {
        List<String> values = new ArrayList<>();
        StringBuilder value = new StringBuilder();
        boolean inQuotes = false;
        for (int index = 0; index < line.length(); index++) {
            char character = line.charAt(index);
            if (character == '"') {
                if (inQuotes && index + 1 < line.length() && line.charAt(index + 1) == '"') {
                    value.append('"');
                    index++;
                } else {
                    inQuotes = !inQuotes;
                }
            } else if (character == ',' && !inQuotes) {
                values.add(value.toString());
                value.setLength(0);
            } else {
                value.append(character);
            }
        }
        if (inQuotes) {
            throw new IllegalArgumentException("Unclosed quoted value in current NIFTY 500 CSV");
        }
        values.add(value.toString());
        return values;
    }
}
