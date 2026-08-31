package in.marketbrain.marketdata.universe;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.Reader;
import java.time.LocalDate;
import java.time.format.DateTimeParseException;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;

/**
 * Validates a manually obtained, date-effective Nifty 500 membership CSV before
 * a later persistence step. It deliberately does not download, scrape, or write
 * to the database.
 */
public class Nifty500MembershipCsvParser {

    private static final List<String> EXPECTED_HEADER =
            List.of("symbol", "isin", "companyname", "effectivefrom", "effectiveto");

    public List<Nifty500MembershipRecord> parse(Reader reader) throws IOException {
        try (BufferedReader bufferedReader = new BufferedReader(reader)) {
            String header = bufferedReader.readLine();
            if (header == null) {
                throw new IllegalArgumentException("Nifty 500 CSV is empty");
            }
            validateHeader(parseCsvLine(header), 1);

            List<Nifty500MembershipRecord> records = new ArrayList<>();
            Set<String> uniqueMembershipStarts = new HashSet<>();
            String line;
            int lineNumber = 1;
            while ((line = bufferedReader.readLine()) != null) {
                lineNumber++;
                if (line.isBlank()) {
                    continue;
                }
                List<String> fields = parseCsvLine(line);
                if (fields.size() != EXPECTED_HEADER.size()) {
                    throw new IllegalArgumentException("Expected 5 columns at line " + lineNumber);
                }
                Nifty500MembershipRecord record = new Nifty500MembershipRecord(
                        fields.get(0).trim(), fields.get(1).trim(), fields.get(2).trim(),
                        parseDate(fields.get(3), "effectiveFrom", lineNumber),
                        optionalDate(fields.get(4), "effectiveTo", lineNumber));
                String uniqueKey = record.symbol().toUpperCase(Locale.ROOT) + "|" + record.effectiveFrom();
                if (!uniqueMembershipStarts.add(uniqueKey)) {
                    throw new IllegalArgumentException("Duplicate symbol and effectiveFrom at line " + lineNumber);
                }
                records.add(record);
            }
            if (records.isEmpty()) {
                throw new IllegalArgumentException("Nifty 500 CSV contains no membership records");
            }
            return List.copyOf(records);
        }
    }

    private static void validateHeader(List<String> header, int lineNumber) {
        List<String> normalized = header.stream()
                .map(value -> value.replace(" ", "").trim().toLowerCase(Locale.ROOT))
                .toList();
        if (!EXPECTED_HEADER.equals(normalized)) {
            throw new IllegalArgumentException(
                    "Expected header symbol,isin,companyName,effectiveFrom,effectiveTo at line " + lineNumber);
        }
    }

    private static LocalDate parseDate(String value, String fieldName, int lineNumber) {
        try {
            return LocalDate.parse(value.trim());
        } catch (DateTimeParseException exception) {
            throw new IllegalArgumentException(fieldName + " must use ISO date YYYY-MM-DD at line " + lineNumber);
        }
    }

    private static LocalDate optionalDate(String value, String fieldName, int lineNumber) {
        return value.isBlank() ? null : parseDate(value, fieldName, lineNumber);
    }

    /** Supports quoted comma-containing company names and escaped quote characters. */
    private static List<String> parseCsvLine(String line) {
        List<String> values = new ArrayList<>();
        StringBuilder value = new StringBuilder();
        boolean inQuotes = false;
        for (int i = 0; i < line.length(); i++) {
            char character = line.charAt(i);
            if (character == '"') {
                if (inQuotes && i + 1 < line.length() && line.charAt(i + 1) == '"') {
                    value.append('"');
                    i++;
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
            throw new IllegalArgumentException("Unclosed quoted value in CSV");
        }
        values.add(value.toString());
        return values;
    }
}
