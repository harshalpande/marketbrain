package in.marketbrain.marketdata.backfill;

import in.marketbrain.configuration.HistoricalBackfillProperties;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.transaction.support.TransactionTemplate;

import java.sql.Date;
import java.sql.ResultSet;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.contains;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

@SuppressWarnings("unchecked")
class HistoricalBackfillPreviewServiceTest {

    @Test
    void secondBatchReusesTheFirstBatchHistoricalWindow() throws Exception {
        JdbcTemplate jdbcTemplate = mock(JdbcTemplate.class);
        HistoricalBackfillProperties properties = mock(HistoricalBackfillProperties.class);
        UUID snapshotId = UUID.fromString("11111111-2222-3333-4444-555555555555");
        LocalDate frozenFrom = LocalDate.of(2011, 9, 2);
        LocalDate frozenTo = LocalDate.of(2026, 9, 1);

        when(properties.maximumExpansionBatchSize()).thenReturn(50);
        when(properties.pilotSymbols()).thenReturn(List.of("INFY"));
        when(jdbcTemplate.queryForObject(contains("status IN ('CREATED'"), eq(Integer.class)))
                .thenReturn(0);
        when(jdbcTemplate.query(contains("SELECT id FROM universe_snapshot"), any(RowMapper.class)))
                .thenReturn(List.of(snapshotId));
        when(jdbcTemplate.queryForObject(contains("job_type = 'PILOT'"), eq(Integer.class), eq(snapshotId)))
                .thenReturn(1);
        when(jdbcTemplate.queryForObject(contains("status = 'PARTIAL_FAILED'"), eq(Integer.class), eq(snapshotId)))
                .thenReturn(0);
        when(jdbcTemplate.query(contains("FROM universe_snapshot_member"), any(RowMapper.class), eq(snapshotId)))
                .thenReturn(List.of(
                        new ExpansionBatchSelector.Candidate(1L, "NSE_EQ|AAA", "AAA", frozenFrom),
                        new ExpansionBatchSelector.Candidate(2L, "NSE_EQ|BBB", "BBB", frozenFrom)));
        when(jdbcTemplate.query(contains("SELECT DISTINCT chunk.instrument_id"), any(RowMapper.class), eq(snapshotId)))
                .thenReturn(List.of(1L));
        when(jdbcTemplate.queryForObject(contains("COALESCE(MAX(batch_number)"), eq(Integer.class), eq(snapshotId)))
                .thenReturn(2);

        ResultSet dateWindowRow = mock(ResultSet.class);
        when(dateWindowRow.getDate("requested_from")).thenReturn(Date.valueOf(frozenFrom));
        when(dateWindowRow.getDate("requested_to")).thenReturn(Date.valueOf(frozenTo));
        when(jdbcTemplate.query(contains("SELECT requested_from, requested_to"), any(RowMapper.class), eq(snapshotId)))
                .thenAnswer(invocation -> {
                    RowMapper<?> mapper = invocation.getArgument(1);
                    return List.of(mapper.mapRow(dateWindowRow, 0));
                });

        HistoricalBackfillJobService service = new HistoricalBackfillJobService(
                jdbcTemplate, mock(TransactionTemplate.class), properties,
                new YearlyBackfillChunkPlanner(), new ExpansionBatchSelector());

        ExpansionBatchPreview preview = service.previewNextExpansionBatch(15, 1);

        assertThat(preview.batchNumber()).isEqualTo(2);
        assertThat(preview.requestedFrom()).isEqualTo(frozenFrom);
        assertThat(preview.requestedTo()).isEqualTo(frozenTo);
        assertThat(preview.instruments()).extracting(ExpansionBatchPreview.Instrument::symbol)
                .containsExactly("BBB");
        assertThat(preview.totalChunks()).isEqualTo(15);
        assertThat(preview.databaseWritesPerformed()).isFalse();
    }
}
