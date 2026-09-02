package in.marketbrain.marketdata.upstox;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;

import java.io.ByteArrayOutputStream;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.zip.GZIPOutputStream;

import static java.nio.charset.StandardCharsets.UTF_8;
import static org.assertj.core.api.Assertions.assertThat;

class UpstoxResponseParserTest {

    private final UpstoxResponseParser parser = new UpstoxResponseParser(new ObjectMapper());

    @Test
    void parsesOfficialGzipInstrumentShapeAndFiltersCashEquity() throws Exception {
        String json = """
                [
                  {"segment":"NSE_EQ","name":"Infosys Limited","isin":"INE009A01021",
                   "instrument_type":"EQ","instrument_key":"NSE_EQ|INE009A01021","trading_symbol":"INFY"},
                  {"segment":"NSE_FO","name":"Infosys Future","instrument_type":"FUT",
                   "instrument_key":"NSE_FO|123","trading_symbol":"INFY FUT"}
                ]
                """;
        var bytes = new ByteArrayOutputStream();
        try (var gzip = new GZIPOutputStream(bytes)) {
            gzip.write(json.getBytes(UTF_8));
        }

        var instruments = parser.parseInstruments(bytes.toByteArray());

        assertThat(instruments).hasSize(2);
        assertThat(instruments.getFirst().isNseEquity()).isTrue();
        assertThat(instruments.getLast().isNseEquity()).isFalse();
    }

    @Test
    void parsesQuoteWithProviderAndTradeTimestamps() throws Exception {
        String json = """
                {"status":"success","data":{"NSE_EQ:INFY":{
                  "instrument_token":"NSE_EQ|INE009A01021","symbol":"INFY",
                  "last_price":1501.25,"volume":1200,"timestamp":"2026-09-02T05:30:30Z",
                  "last_trade_time":"1788327020000","ohlc":{"close":1490.10}
                }}}
                """;

        UpstoxQuote quote = parser.parseQuote(json, "NSE_EQ|INE009A01021");

        assertThat(quote.lastPrice()).isEqualByComparingTo(new BigDecimal("1501.25"));
        assertThat(quote.previousClose()).isEqualByComparingTo(new BigDecimal("1490.10"));
        assertThat(quote.providerPublishedAt()).isEqualTo(Instant.parse("2026-09-02T05:30:30Z"));
        assertThat(quote.lastTradeAt()).isEqualTo(Instant.ofEpochMilli(1788327020000L));
    }

    @Test
    void skipsMalformedCandleRowsWithoutInventingValues() throws Exception {
        String json = """
                {"status":"success","data":{"candles":[
                  ["2026-09-01T09:15:00+05:30",100,110,95,105,500,0],
                  ["incomplete",100]
                ]}}
                """;

        var candles = parser.parseCandles(json);

        assertThat(candles).hasSize(1);
        assertThat(candles.getFirst().openedAt()).isEqualTo(Instant.parse("2026-09-01T03:45:00Z"));
        assertThat(candles.getFirst().close()).isEqualByComparingTo("105");
    }
}
