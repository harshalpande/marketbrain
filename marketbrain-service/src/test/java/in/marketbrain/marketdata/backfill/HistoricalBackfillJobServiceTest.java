package in.marketbrain.marketdata.backfill;

import in.marketbrain.configuration.HistoricalBackfillProperties;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.support.TransactionCallback;
import org.springframework.transaction.support.TransactionTemplate;

import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.contains;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class HistoricalBackfillJobServiceTest {

    private final JdbcTemplate jdbcTemplate = mock(JdbcTemplate.class);
    private final TransactionTemplate transactionTemplate = mock(TransactionTemplate.class);
    private final HistoricalBackfillProperties properties = mock(HistoricalBackfillProperties.class);
    private final HistoricalBackfillJobService service = new HistoricalBackfillJobService(
            jdbcTemplate, transactionTemplate, properties,
            mock(YearlyBackfillChunkPlanner.class), mock(ExpansionBatchSelector.class));

    @BeforeEach
    void executeTransactionCallbacks() {
        when(transactionTemplate.execute(any())).thenAnswer(invocation -> {
            TransactionCallback<?> callback = invocation.getArgument(0);
            return callback.doInTransaction(null);
        });
    }

    @Test
    void explicitlyRetriesOnlyFailedInvalidDataChunks() {
        UUID jobId = UUID.randomUUID();
        when(properties.workerEnabled()).thenReturn(true);
        when(jdbcTemplate.update(contains("UPDATE historical_backfill_chunk"), eq(jobId))).thenReturn(3);
        when(jdbcTemplate.update(contains("UPDATE historical_backfill_job"), eq(jobId))).thenReturn(1);

        BackfillRetryResult result = service.retryInvalidDataChunks(jobId);

        assertThat(result.retriedChunks()).isEqualTo(3);
        assertThat(result.status()).isEqualTo("RUNNING");
        verify(jdbcTemplate).update(contains("last_error_code = 'INVALID_DATA'"), eq(jobId));
    }

    @Test
    void refusesRetryWhileWorkerIsDisabled() {
        when(properties.workerEnabled()).thenReturn(false);

        assertThatThrownBy(() -> service.retryInvalidDataChunks(UUID.randomUUID()))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("worker is disabled");
    }
}
