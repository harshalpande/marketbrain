package in.marketbrain.training;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.PreparedStatementSetter;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.transaction.annotation.Transactional;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Timestamp;
import java.time.LocalDate;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

class NumericalHistoryCoverageTest {
    final UUID runId = UUID.fromString("5bdbfcc1-d990-48d8-9e98-d4927596d917");

    @Test void contractRemainsDraftAndCannotAuthorizeTraining() {
        var contract = NumericalDataContract.draft();
        assertThat(contract.trainingAuthorized()).isFalse();
        assertThat(contract.horizonSessions()).isEqualTo(20);
        assertThat(contract.candidateFeatures()).doesNotContainAnyElementsOf(contract.forbiddenInputs());
        assertThat(contract.unresolvedGates()).hasSize(7);
        assertThat(contract.entryRule()).contains("OPEN", "never skip");
        assertThat(contract.splitRule()).contains("purge", "train only");
    }

    @Test void guardsRejectBeforeJdbc() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        var service = new NumericalHistoryCoverageService(jdbc);
        for (int[] input : List.of(new int[]{-1,50,730}, new int[]{500,50,730}, new int[]{0,51,730},
                new int[]{0,0,730}, new int[]{0,50,731}, new int[]{0,50,251})) {
            assertThatThrownBy(() -> service.inspect(runId,input[0],input[1],input[2])).isInstanceOf(IllegalArgumentException.class);
        }
        assertThatThrownBy(() -> service.inspect(null,0,50,730)).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> service.inspect(new UUID(0,0),0,50,730)).isInstanceOf(IllegalArgumentException.class);
        verifyNoInteractions(jdbc);
    }

    @Test void queryBindsIndexedBoundsAndTimeoutsAndMapsRows() throws Exception {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        Connection connection = mock(Connection.class);
        PreparedStatement runStatement = mock(PreparedStatement.class), coverageStatement = mock(PreparedStatement.class);
        when(connection.prepareStatement(NumericalHistoryCoverageService.RUN_SQL)).thenReturn(runStatement);
        when(connection.prepareStatement(NumericalHistoryCoverageService.COVERAGE_SQL)).thenReturn(coverageStatement);
        ResultSet metadata = mock(ResultSet.class), item = mock(ResultSet.class);
        when(metadata.getObject("as_of",LocalDate.class)).thenReturn(LocalDate.of(2026,6,5));
        when(metadata.getString("dataset_manifest_hash")).thenReturn("a".repeat(64));
        when(metadata.getInt("instrument_count")).thenReturn(2);
        when(item.getLong("instrument_id")).thenReturn(123L);
        when(item.getString("symbol")).thenReturn("FIXTURE");
        when(item.getString("classification")).thenReturn("INSUFFICIENT_HISTORY");
        when(item.getString("detail")).thenReturn("At least 252 eligible observations required; found 100.");
        when(item.getInt("scanned_rows")).thenReturn(2001);
        when(item.getInt("observed_dates")).thenReturn(100);
        when(item.getInt("received_after_cutoff")).thenReturn(1900);
        List<PreparedStatement> seen = new ArrayList<>();
        doAnswer(invocation -> {
            String sql = invocation.getArgument(0);
            PreparedStatementSetter setter = invocation.getArgument(1);
            RowMapper<?> mapper = invocation.getArgument(2);
            var statement = connection.prepareStatement(sql);
            setter.setValues(statement);
            seen.add(statement);
            return List.of(mapper.mapRow(statement == runStatement ? metadata : item,0));
        }).when(jdbc).query(anyString(),any(PreparedStatementSetter.class),any(RowMapper.class));
        var page = new NumericalHistoryCoverageService(jdbc).inspect(runId,0,1,730);
        assertThat(page.nextOffset()).isEqualTo(1);
        assertThat(page.partial()).isTrue();
        assertThat(page.databaseWritesPerformed()).isFalse();
        assertThat(page.modelCallCount()+page.providerCallCount()+page.ordersCreated()).isZero();
        assertThat(page.instruments().getFirst().persistedReason()).contains("252");
        assertThat(page.instruments().getFirst().receivedAfterDecisionCutoffRows()).isEqualTo(1900);
        verify(runStatement).setQueryTimeout(5);
        verify(coverageStatement).setQueryTimeout(15);
        verify(coverageStatement).setObject(1,runId);
        verify(coverageStatement).setInt(2,1);
        verify(coverageStatement).setInt(3,0);
        verify(coverageStatement).setObject(4,page.asOf());
        verify(coverageStatement).setObject(5,page.windowFrom());
        verify(coverageStatement).setTimestamp(6,Timestamp.from(Instant.parse("2026-06-05T10:30:00Z")));
        verify(coverageStatement).setTimestamp(7,Timestamp.from(page.windowFrom().atStartOfDay(java.time.ZoneId.of("Asia/Kolkata")).toInstant()));
        verify(coverageStatement).setTimestamp(8,Timestamp.from(Instant.parse("2026-06-05T18:30:00Z")));
        assertThat(seen).hasSize(2);
        verify(jdbc,never()).update(anyString());
    }

    @Test void missingRunAndInconsistentPageFailClosed() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        when(jdbc.query(anyString(),any(PreparedStatementSetter.class),any(RowMapper.class))).thenReturn(List.of());
        assertThatThrownBy(() -> new NumericalHistoryCoverageService(jdbc).inspect(runId,0,50,730))
                .isInstanceOf(IllegalArgumentException.class);
        when(jdbc.query(anyString(),any(PreparedStatementSetter.class),any(RowMapper.class)))
                .thenReturn(List.of(new NumericalHistoryCoverageService.Run(LocalDate.of(2026,6,5),"hash",2)))
                .thenReturn(List.of());
        assertThatThrownBy(() -> new NumericalHistoryCoverageService(jdbc).inspect(runId,0,50,730))
                .isInstanceOf(IllegalStateException.class);
    }

    @Test void readOnlyTransactionAndQueryScopeAreExplicit() throws Exception {
        var annotation = NumericalHistoryCoverageService.class.getMethod("inspect",UUID.class,int.class,int.class,int.class)
                .getAnnotation(Transactional.class);
        assertThat(annotation.readOnly()).isTrue();
        assertThat(annotation.timeout()).isEqualTo(30);
        assertThat(NumericalHistoryCoverageService.COVERAGE_SQL).contains("run_id = ?", "LIMIT ? OFFSET ?",
                "c.instrument_id = item.instrument_id", "c.opened_at >= ? AND c.opened_at < ?", "LIMIT 2001");
    }

    @Test void controllerBindsAndRejectsInvalidInput() throws Exception {
        var service = mock(NumericalHistoryCoverageService.class);
        var mvc = MockMvcBuilders.standaloneSetup(new NumericalHistoryCoverageController(service)).build();
        mvc.perform(get("/api/v1/training/numerical-history-coverage").param("datasetRunId",runId.toString()))
                .andExpect(status().isOk());
        verify(service).inspect(runId,0,50,730);
        mvc.perform(get("/api/v1/training/numerical-history-coverage")).andExpect(status().isBadRequest());
        mvc.perform(get("/api/v1/training/numerical-history-coverage").param("datasetRunId","bad"))
                .andExpect(status().isBadRequest());
        when(service.inspect(runId,0,50,730)).thenThrow(new IllegalArgumentException("invalid"));
        mvc.perform(get("/api/v1/training/numerical-history-coverage").param("datasetRunId",runId.toString()))
                .andExpect(status().isBadRequest());
    }

    @Test void springWiresOnlyTheReadOnlyDependencies() {
        new ApplicationContextRunner().withBean(JdbcTemplate.class,() -> mock(JdbcTemplate.class))
                .withBean(NumericalHistoryCoverageService.class).withBean(NumericalHistoryCoverageController.class)
                .run(context -> {assertThat(context).hasNotFailed();assertThat(context).hasSingleBean(NumericalHistoryCoverageController.class);});
    }
}
