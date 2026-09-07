package in.marketbrain.marketdata.daily;

import in.marketbrain.configuration.DailyEnrichmentProperties;
import in.marketbrain.marketdata.upstox.UpstoxCandle;
import in.marketbrain.marketdata.upstox.UpstoxFetchResult;
import in.marketbrain.marketdata.upstox.UpstoxReadOnlyClient;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;

import java.math.BigDecimal;
import java.sql.ResultSet;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

@SuppressWarnings("unchecked")
class DailyEnrichmentProviderReadinessServiceTest {

    @Test
    void waitsUntilEveryConfiguredProbeContainsTheTargetDate() throws Exception {
        JdbcTemplate jdbcTemplate = mock(JdbcTemplate.class);
        UpstoxReadOnlyClient client = mock(UpstoxReadOnlyClient.class);
        DailyEnrichmentProperties properties = mock(DailyEnrichmentProperties.class);
        LocalDate target = LocalDate.of(2026, 9, 7);

        when(properties.readinessSymbols()).thenReturn(List.of("AAA", "BBB"));
        when(jdbcTemplate.query(any(String.class), any(RowMapper.class))).thenAnswer(invocation -> {
            RowMapper<?> mapper = invocation.getArgument(1);
            ResultSet first = row("AAA", "NSE_EQ|AAA");
            ResultSet second = row("BBB", "NSE_EQ|BBB");
            return List.of(mapper.mapRow(first, 0), mapper.mapRow(second, 1));
        });
        when(client.fetchHistoricalCandles(any())).thenReturn(
                UpstoxFetchResult.success(List.of(candle("2026-09-07T03:45:00Z"))),
                UpstoxFetchResult.success(List.of()));

        DailyEnrichmentProviderReadiness readiness = new DailyEnrichmentProviderReadinessService(
                jdbcTemplate, client, properties).check(target);

        assertThat(readiness.status()).isEqualTo("WAITING_FOR_TARGET_DATE");
        assertThat(readiness.requestedChecks()).isEqualTo(2);
        assertThat(readiness.availableChecks()).isEqualTo(1);
        assertThat(readiness.missingChecks()).isEqualTo(1);
        assertThat(readiness.failedChecks()).isZero();
        assertThat(readiness.databaseWritesPerformed()).isFalse();
    }

    private ResultSet row(String symbol, String key) throws Exception {
        ResultSet row = mock(ResultSet.class);
        when(row.getString("source_symbol")).thenReturn(symbol);
        when(row.getString("provider_instrument_key")).thenReturn(key);
        return row;
    }

    private UpstoxCandle candle(String instant) {
        BigDecimal price = BigDecimal.TEN;
        return new UpstoxCandle(Instant.parse(instant), price, price, price, price, BigDecimal.ONE);
    }
}
