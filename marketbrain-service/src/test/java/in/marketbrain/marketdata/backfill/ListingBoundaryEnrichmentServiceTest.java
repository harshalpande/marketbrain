package in.marketbrain.marketdata.backfill;

import in.marketbrain.configuration.HistoricalBackfillProperties;
import in.marketbrain.marketdata.universe.NseEquitySecurityClient;
import in.marketbrain.marketdata.universe.NseEquitySecurityCsvParser;
import in.marketbrain.marketdata.universe.NseEquitySecuritySourceResult;
import in.marketbrain.marketdata.upstox.UpstoxCandle;
import in.marketbrain.marketdata.upstox.UpstoxFetchResult;
import in.marketbrain.marketdata.upstox.UpstoxReadOnlyClient;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.transaction.support.TransactionCallback;
import org.springframework.transaction.support.TransactionTemplate;

import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.sql.ResultSet;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.contains;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

@SuppressWarnings("unchecked")
class ListingBoundaryEnrichmentServiceTest {

    private static final UUID SNAPSHOT_ID = UUID.fromString("11111111-2222-3333-4444-555555555555");
    private static final String INPUT_HASH = "a".repeat(64);
    private static final String OUTPUT_HASH = "b".repeat(64);
    private static final LocalDate REQUESTED_FROM = LocalDate.of(2019, 10, 5);
    private static final LocalDate REQUESTED_TO = LocalDate.of(2021, 10, 4);
    private static final LocalDate REPORTED_LISTING_DATE = LocalDate.of(2020, 10, 5);

    private final HistoricalBackfillProperties properties = mock(HistoricalBackfillProperties.class);
    private final HistoricalBackfillJobService jobService = mock(HistoricalBackfillJobService.class);
    private final NseEquitySecurityClient nseClient = mock(NseEquitySecurityClient.class);
    private final UpstoxReadOnlyClient upstoxClient = mock(UpstoxReadOnlyClient.class);
    private final JdbcTemplate jdbcTemplate = mock(JdbcTemplate.class);
    private final TransactionTemplate transactionTemplate = mock(TransactionTemplate.class);
    private final ListingBoundaryEnrichmentService service = new ListingBoundaryEnrichmentService(
            properties, jobService, nseClient, new NseEquitySecurityCsvParser(), upstoxClient,
            new YearlyBackfillChunkPlanner(), jdbcTemplate, transactionTemplate);

    @BeforeEach
    void configureSourceAndCandidate() throws Exception {
        byte[] source = sourceCsv().getBytes(StandardCharsets.UTF_8);
        when(properties.workerEnabled()).thenReturn(false);
        when(properties.nseEquitySecurityUrl()).thenReturn(
                "https://nsearchives.nseindia.com/content/equities/EQUITY_L.csv");
        when(nseClient.fetch()).thenReturn(new NseEquitySecuritySourceResult(
                "SUCCESS", source, "c".repeat(64), "Downloaded."));

        ResultSet targetRow = mock(ResultSet.class);
        when(targetRow.getLong("id")).thenReturn(7L);
        when(targetRow.getString("symbol")).thenReturn("RECENT");
        when(targetRow.getString("isin")).thenReturn("INE000000000");
        when(targetRow.getString("provider_instrument_key")).thenReturn("NSE_EQ|INE000000000");
        when(targetRow.getDate("listed_on")).thenReturn(null);
        when(jdbcTemplate.query(contains("SELECT instrument.id"), any(RowMapper.class), eq(SNAPSHOT_ID)))
                .thenAnswer(invocation -> {
                    RowMapper<?> mapper = invocation.getArgument(1);
                    return List.of(mapper.mapRow(targetRow, 0));
                });
    }

    @Test
    void preservesEarlierProviderHistoryInsteadOfApplyingTheReportedSecurityDate() {
        when(jobService.previewNextExpansionBatch(1, 1))
                .thenReturn(preview(INPUT_HASH, false, null, "NOT_ENRICHED", null),
                        preview(OUTPUT_HASH, true, null, "EARLIER_PROVIDER_HISTORY",
                                LocalDate.of(2020, 9, 1)));
        when(upstoxClient.fetchHistoricalCandles(any())).thenReturn(UpstoxFetchResult.success(List.of(
                candle("2020-08-31T18:30:00Z"))));
        when(transactionTemplate.execute(any())).thenAnswer(invocation -> {
            TransactionCallback<?> callback = invocation.getArgument(0);
            return callback.doInTransaction(null);
        });
        when(jdbcTemplate.update(contains("INSERT INTO instrument_listing_evidence"), any(Object[].class)))
                .thenReturn(1);

        ListingBoundaryEnrichmentReport result = service.enrich(1, 1, INPUT_HASH);

        assertThat(result.status()).isEqualTo("COMPLETED");
        assertThat(result.earlierProviderHistoryCount()).isEqualTo(1);
        assertThat(result.verifiedBoundaryCount()).isZero();
        assertThat(result.boundariesApplied()).isZero();
        assertThat(result.items().getFirst().nseSeries()).isEqualTo("BE");
        assertThat(result.items().getFirst().providerPrelistingCandleOn())
                .isEqualTo(LocalDate.of(2020, 9, 1));
        assertThat(result.outputManifestHash()).isEqualTo(OUTPUT_HASH);
        ArgumentCaptor<Object[]> persistenceArguments = ArgumentCaptor.forClass(Object[].class);
        verify(jdbcTemplate).update(
                contains("INSERT INTO instrument_listing_evidence"), persistenceArguments.capture());
        assertThat(persistenceArguments.getValue()[6]).isEqualTo("BE");
    }

    @Test
    void writesNothingWhenTheProviderCheckFails() {
        when(jobService.previewNextExpansionBatch(1, 1))
                .thenReturn(preview(INPUT_HASH, false, null, "NOT_ENRICHED", null));
        when(upstoxClient.fetchHistoricalCandles(any())).thenReturn(
                UpstoxFetchResult.failure("CONNECTION_FAILED", 0, "Retry safely."));

        ListingBoundaryEnrichmentReport result = service.enrich(1, 1, INPUT_HASH);

        assertThat(result.status()).isEqualTo("PROVIDER_CHECK_FAILED");
        assertThat(result.providerCheckFailureCount()).isEqualTo(1);
        assertThat(result.databaseWritesPerformed()).isFalse();
        assertThat(result.evidenceRowsWritten()).isZero();
        verifyNoInteractions(transactionTemplate);
    }

    private ExpansionBatchPreview preview(
            String hash,
            boolean evidenceComplete,
            LocalDate listedOn,
            String evidenceStatus,
            LocalDate prelistingCandleOn
    ) {
        return new ExpansionBatchPreview(
                SNAPSHOT_ID, 2, 1, REQUESTED_FROM, REQUESTED_TO,
                1, 0, 50, 1, hash, evidenceComplete, false,
                List.of(new ExpansionBatchPreview.Instrument(
                        "RECENT", "NSE_EQ|INE000000000", listedOn, REPORTED_LISTING_DATE,
                        evidenceStatus, prelistingCandleOn, listedOn == null ? REQUESTED_FROM : listedOn, 1)),
                "Test preview.");
    }

    private UpstoxCandle candle(String openedAt) {
        return new UpstoxCandle(
                Instant.parse(openedAt), BigDecimal.ONE, BigDecimal.ONE,
                BigDecimal.ONE, BigDecimal.ONE, BigDecimal.TEN);
    }

    private String sourceCsv() {
        StringBuilder csv = new StringBuilder(
                "SYMBOL,NAME OF COMPANY, SERIES, DATE OF LISTING, PAID UP VALUE, MARKET LOT, ISIN NUMBER, FACE VALUE\n");
        csv.append("RECENT,Recent Limited,BE,05-OCT-2020,10,1,INE000000000,10\n");
        for (int index = 1; index < 500; index++) {
            csv.append("SYMBOL").append(index).append(",Company ").append(index)
                    .append(",EQ,01-JAN-2000,10,1,INE")
                    .append(String.format("%09d", index)).append(",10\n");
        }
        return csv.toString();
    }
}
