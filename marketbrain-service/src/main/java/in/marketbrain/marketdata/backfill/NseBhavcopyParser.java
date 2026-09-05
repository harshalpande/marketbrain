package in.marketbrain.marketdata.backfill;

import org.springframework.stereotype.Component;

import java.io.BufferedReader;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.InputStreamReader;
import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeFormatterBuilder;
import java.time.format.DateTimeParseException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;

@Component
class NseBhavcopyParser {

    private static final int MAXIMUM_ARCHIVE_BYTES = 20 * 1024 * 1024;
    private static final int MAXIMUM_CSV_ROWS = 100_000;
    private static final Set<String> PRICE_DISCOVERY_SERIES = Set.of("EQ", "BE", "BZ");
    private static final List<DateTimeFormatter> DATE_FORMATS = List.of(
            DateTimeFormatter.ISO_LOCAL_DATE,
            new DateTimeFormatterBuilder()
                    .parseCaseInsensitive()
                    .appendPattern("dd-MMM-uuuu")
                    .toFormatter(Locale.ENGLISH)
    );

    List<NseBhavcopyRecord> parse(byte[] archive, LocalDate requestedDate) throws IOException {
        if (archive == null || archive.length == 0) {
            throw new IOException("NSE returned an empty Bhavcopy archive");
        }
        if (archive.length > MAXIMUM_ARCHIVE_BYTES) {
            throw new IOException("NSE Bhavcopy archive exceeded the safety limit");
        }

        try (ZipInputStream zip = new ZipInputStream(new ByteArrayInputStream(archive), StandardCharsets.UTF_8)) {
            ZipEntry entry;
            while ((entry = zip.getNextEntry()) != null) {
                if (!entry.isDirectory() && entry.getName().toLowerCase(Locale.ROOT).endsWith(".csv")) {
                    return parseCsv(zip, requestedDate);
                }
            }
        }
        throw new IOException("NSE Bhavcopy archive contained no CSV file");
    }

    private List<NseBhavcopyRecord> parseCsv(ZipInputStream zip, LocalDate requestedDate) throws IOException {
        BufferedReader reader = new BufferedReader(new InputStreamReader(zip, StandardCharsets.UTF_8));
        String headerLine = reader.readLine();
        if (headerLine == null) {
            throw new IOException("NSE Bhavcopy CSV was empty");
        }
        List<String> headers = parseCsvLine(stripBom(headerLine));
        Map<String, Integer> columns = columnIndex(headers);
        Layout layout = Layout.detect(columns);

        List<NseBhavcopyRecord> records = new ArrayList<>();
        String line;
        int rowCount = 0;
        while ((line = reader.readLine()) != null) {
            if (++rowCount > MAXIMUM_CSV_ROWS) {
                throw new IOException("NSE Bhavcopy CSV exceeded the row safety limit");
            }
            if (line.isBlank()) {
                continue;
            }
            List<String> values = parseCsvLine(line);
            String series = value(values, columns, layout.seriesColumn()).toUpperCase(Locale.ROOT);
            if (!PRICE_DISCOVERY_SERIES.contains(series)) {
                continue;
            }
            try {
                String dateValue = value(values, columns, layout.dateColumn());
                LocalDate tradingDate = parseDate(dateValue);
                if (!dateValue.isBlank() && tradingDate == null) {
                    continue;
                }
                if (tradingDate != null && !requestedDate.equals(tradingDate)) {
                    continue;
                }
                String symbol = value(values, columns, layout.symbolColumn()).toUpperCase(Locale.ROOT);
                BigDecimal previousClose = decimal(values, columns, layout.previousCloseColumn());
                BigDecimal close = decimal(values, columns, layout.closeColumn());
                if (symbol.isBlank() || previousClose == null || close == null) {
                    continue;
                }
                records.add(new NseBhavcopyRecord(
                        symbol,
                        value(values, columns, layout.isinColumn()).toUpperCase(Locale.ROOT),
                        series,
                        tradingDate == null ? requestedDate : tradingDate,
                        previousClose,
                        decimal(values, columns, layout.openColumn()),
                        decimal(values, columns, layout.highColumn()),
                        decimal(values, columns, layout.lowColumn()),
                        close,
                        decimal(values, columns, layout.volumeColumn())
                ));
            } catch (NumberFormatException ignored) {
                // A malformed unrelated row must not hide valid official evidence for other instruments.
            }
        }
        if (records.isEmpty()) {
            throw new IOException("NSE Bhavcopy CSV contained no supported cash-equity rows");
        }
        return List.copyOf(records);
    }

    private Map<String, Integer> columnIndex(List<String> headers) {
        Map<String, Integer> result = new HashMap<>();
        for (int index = 0; index < headers.size(); index++) {
            result.put(normalizeHeader(headers.get(index)), index);
        }
        return Map.copyOf(result);
    }

    private String normalizeHeader(String header) {
        return stripBom(header).replaceAll("[^A-Za-z0-9]", "").toUpperCase(Locale.ROOT);
    }

    private String value(List<String> values, Map<String, Integer> columns, String column) {
        Integer index = columns.get(column);
        return index == null || index >= values.size() ? "" : values.get(index).trim();
    }

    private BigDecimal decimal(List<String> values, Map<String, Integer> columns, String column) {
        String value = value(values, columns, column);
        return value.isBlank() ? null : new BigDecimal(value);
    }

    private LocalDate parseDate(String value) {
        if (value.isBlank()) {
            return null;
        }
        for (DateTimeFormatter formatter : DATE_FORMATS) {
            try {
                return LocalDate.parse(value, formatter);
            } catch (DateTimeParseException ignored) {
                // Try the next documented NSE date representation.
            }
        }
        return null;
    }

    static List<String> parseCsvLine(String line) {
        List<String> values = new ArrayList<>();
        StringBuilder value = new StringBuilder();
        boolean quoted = false;
        for (int index = 0; index < line.length(); index++) {
            char current = line.charAt(index);
            if (current == '"') {
                if (quoted && index + 1 < line.length() && line.charAt(index + 1) == '"') {
                    value.append('"');
                    index++;
                } else {
                    quoted = !quoted;
                }
            } else if (current == ',' && !quoted) {
                values.add(value.toString());
                value.setLength(0);
            } else {
                value.append(current);
            }
        }
        values.add(value.toString());
        return List.copyOf(values);
    }

    private String stripBom(String value) {
        return value != null && value.startsWith("\uFEFF") ? value.substring(1) : value;
    }

    private record Layout(
            String symbolColumn,
            String isinColumn,
            String seriesColumn,
            String dateColumn,
            String previousCloseColumn,
            String openColumn,
            String highColumn,
            String lowColumn,
            String closeColumn,
            String volumeColumn
    ) {
        private static Layout detect(Map<String, Integer> columns) throws IOException {
            if (columns.containsKey("SYMBOL") && columns.containsKey("PREVCLOSE")) {
                return new Layout("SYMBOL", "ISIN", "SERIES", "TIMESTAMP",
                        "PREVCLOSE", "OPEN", "HIGH", "LOW", "CLOSE", "TOTTRDQTY");
            }
            if (columns.containsKey("TCKRSYMB") && columns.containsKey("PRVSCLSGPRIC")) {
                return new Layout("TCKRSYMB", "ISIN", "SCTYSRS", "TRADDT",
                        "PRVSCLSGPRIC", "OPNPRIC", "HGHPRIC", "LWPRIC", "CLSPRIC", "TTLTRADGVOL");
            }
            throw new IOException("NSE Bhavcopy CSV headers were not a supported legacy or UDiFF format");
        }
    }
}
