package in.marketbrain.marketdata.universe;

import org.springframework.stereotype.Component;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.Reader;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeFormatterBuilder;
import java.time.format.DateTimeParseException;
import java.time.format.ResolverStyle;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;

@Component
public class NseEquitySecurityCsvParser {

    private static final Set<String> ACCEPTED_CASH_EQUITY_SERIES = Set.of("EQ", "BE", "BZ");
    private static final List<String> EXPECTED_HEADER = List.of(
            "symbol", "nameofcompany", "series", "dateoflisting",
            "paidupvalue", "marketlot", "isinnumber", "facevalue");
    private static final DateTimeFormatter LISTING_DATE = new DateTimeFormatterBuilder()
            .parseCaseInsensitive()
            .appendPattern("dd-MMM-uuuu")
            .toFormatter(Locale.ENGLISH)
            .withResolverStyle(ResolverStyle.STRICT);

    public List<NseEquitySecurity> parse(Reader reader) throws IOException {
        try (var buffered = new BufferedReader(reader)) {
            String firstLine = buffered.readLine();
            if (firstLine == null) {
                throw new IllegalArgumentException("NSE equity security CSV is empty");
            }
            List<String> header = CurrentNifty500CsvParser.parseCsvLine(firstLine.replace("\uFEFF", "")).stream()
                    .map(NseEquitySecurityCsvParser::normalizeHeader)
                    .toList();
            if (!EXPECTED_HEADER.equals(header)) {
                throw new IllegalArgumentException(
                        "Unexpected NSE equity security header; provider format may have changed");
            }

            List<NseEquitySecurity> records = new ArrayList<>();
            Set<String> uniqueSymbolAndIsin = new HashSet<>();
            String line;
            int lineNumber = 1;
            while ((line = buffered.readLine()) != null) {
                lineNumber++;
                if (line.isBlank()) {
                    continue;
                }
                List<String> fields = CurrentNifty500CsvParser.parseCsvLine(line);
                if (fields.size() != EXPECTED_HEADER.size()) {
                    throw new IllegalArgumentException("Expected 8 columns at line " + lineNumber);
                }
                String series = fields.get(2).trim().toUpperCase(Locale.ROOT);
                if (!ACCEPTED_CASH_EQUITY_SERIES.contains(series)) {
                    continue;
                }
                String symbol = fields.get(0).trim().toUpperCase(Locale.ROOT);
                String isin = fields.get(6).trim().toUpperCase(Locale.ROOT);
                LocalDate listedOn = parseDate(fields.get(3).trim(), lineNumber);
                if (symbol.isBlank() || fields.get(1).isBlank() || !isin.matches("[A-Z0-9]{12}")) {
                    throw new IllegalArgumentException("Incomplete NSE equity security at line " + lineNumber);
                }
                if (!uniqueSymbolAndIsin.add(symbol + "|" + isin)) {
                    throw new IllegalArgumentException("Duplicate NSE symbol and ISIN at line " + lineNumber);
                }
                records.add(new NseEquitySecurity(
                        symbol, fields.get(1).trim(), series, listedOn, isin));
            }
            if (records.size() < 500 || records.size() > 5_000) {
                throw new IllegalArgumentException(
                        "NSE equity security source returned an implausible EQ record count: " + records.size());
            }
            return List.copyOf(records);
        }
    }

    private LocalDate parseDate(String value, int lineNumber) {
        try {
            return LocalDate.parse(value.toUpperCase(Locale.ENGLISH), LISTING_DATE);
        } catch (DateTimeParseException exception) {
            throw new IllegalArgumentException("Invalid DATE OF LISTING at line " + lineNumber);
        }
    }

    private static String normalizeHeader(String value) {
        return value.replace(" ", "").trim().toLowerCase(Locale.ROOT);
    }
}
