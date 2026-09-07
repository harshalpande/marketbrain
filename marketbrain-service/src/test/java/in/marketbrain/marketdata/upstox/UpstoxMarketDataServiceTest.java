package in.marketbrain.marketdata.upstox;

import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@SuppressWarnings("unchecked")
class UpstoxMarketDataServiceTest {

    @Test
    void combinesHistoricalCatchupWithTheCurrentIntradayDailyCandle() {
        UpstoxReadOnlyClient client = mock(UpstoxReadOnlyClient.class);
        UpstoxDataQualityService quality = mock(UpstoxDataQualityService.class);
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        UpstoxHistoricalRequest request = new UpstoxHistoricalRequest(
                "NSE_EQ|INE009A01021", "days", 1,
                LocalDate.of(2026, 9, 7), LocalDate.of(2026, 9, 8));
        UpstoxHistoricalRequest historicalRequest = new UpstoxHistoricalRequest(
                request.instrumentKey(), "days", 1,
                LocalDate.of(2026, 9, 7), LocalDate.of(2026, 9, 7));
        UpstoxIntradayRequest intradayRequest = new UpstoxIntradayRequest(
                request.instrumentKey(), "days", 1);

        when(client.fetchHistoricalCandles(historicalRequest))
                .thenReturn(UpstoxFetchResult.success(List.of(candle("2026-09-06T18:30:00Z"))));
        when(client.fetchIntradayCandles(intradayRequest))
                .thenReturn(UpstoxFetchResult.success(List.of(candle("2026-09-08T03:45:00Z"))));
        when(quality.validCandle(any())).thenReturn(true);
        when(jdbc.query(anyString(), any(RowMapper.class), eq("UPSTOX"), eq(request.instrumentKey())))
                .thenReturn(List.of(11L));
        when(jdbc.update(anyString(), any(Object[].class))).thenReturn(1);

        UpstoxMarketDataService service = new UpstoxMarketDataService(
                client, quality, new UpstoxCandleBatchNormalizer(), jdbc);
        UpstoxImportResult result = service.importCurrentDailyCandles(request);

        assertThat(result.status()).isEqualTo("SUCCESS");
        assertThat(result.received()).isEqualTo(2);
        assertThat(result.accepted()).isEqualTo(2);
        assertThat(result.rejected()).isZero();
        assertThat(result.detail()).contains("Historical catch-up and current-day intraday");
        verify(client).fetchHistoricalCandles(historicalRequest);
        verify(client).fetchIntradayCandles(intradayRequest);
    }

    private UpstoxCandle candle(String openedAt) {
        return new UpstoxCandle(
                Instant.parse(openedAt),
                new BigDecimal("100"), new BigDecimal("101"),
                new BigDecimal("99"), new BigDecimal("100.5"),
                new BigDecimal("1000"));
    }
}
