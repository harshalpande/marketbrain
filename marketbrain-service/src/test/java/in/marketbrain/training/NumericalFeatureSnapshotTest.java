package in.marketbrain.training;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.PreparedStatementSetter;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.transaction.annotation.Isolation;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import java.math.BigDecimal;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Timestamp;
import java.time.Instant;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.mockito.ArgumentMatchers.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

class NumericalFeatureSnapshotTest {
    final NumericalFeatureSnapshot calculator = new NumericalFeatureSnapshot();
    final LocalDate start = LocalDate.of(2024,1,1);
    final UUID runId = UUID.fromString("5bdbfcc1-d990-48d8-9e98-d4927596d917");
    NumericalFeatureSnapshot.SourceBar bar(int i) {
        return new NumericalFeatureSnapshot.SourceBar(i+1,start.plusDays(i),"UPSTOX",Instant.parse("2026-09-01T00:00:00Z"),
                BigDecimal.valueOf(100+i),BigDecimal.valueOf(102+i),BigDecimal.valueOf(99+i),
                BigDecimal.valueOf(101+i),BigDecimal.TEN,false);
    }
    List<NumericalFeatureSnapshot.SourceBar> bars(int count) {
        return java.util.stream.IntStream.range(0,count).mapToObj(this::bar).toList();
    }
    @Test void exactly252TrailingBarsAndNoFuturePriceLeakage() {
        var before = calculator.calculate(start.plusDays(260),bars(261),false);
        var after = calculator.calculate(start.plusDays(260),bars(400),false);
        assertThat(after).isEqualTo(before);
        assertThat(before.observationCount()).isEqualTo(252);
        assertThat(before.sourceCandleIds()).startsWith(10L).endsWith(261L);
        assertThat(before.receivedAfterCutoffCount()).isEqualTo(252);
        assertThat(before.status()).isEqualTo("FEATURES_ONLY_CALENDAR_UNVERIFIED");
        assertThat(before.features().volumeRatio20()).isEqualByComparingTo("1");
        assertThat(before.features().rangePosition252Percent()).isEqualByComparingTo("100");
    }
    @Test void missingDateWarmupAndCapCannotBecomeFeatures() {
        assertThat(calculator.calculate(start.plusDays(251),bars(251),false).status()).isEqualTo("NO_BAR_ON_REQUESTED_DATE");
        assertThat(calculator.calculate(start.plusDays(250),bars(251),false).status()).isEqualTo("INSUFFICIENT_OBSERVATIONS");
        var capped = calculator.calculate(start.plusDays(251),bars(252),true);
        assertThat(capped.status()).isEqualTo("SOURCE_ROW_CAP_EXCEEDED");
        assertThat(capped.features()).isNull();
    }
    @Test void exclusionNotDroppedAndInvalidPricesNotRepaired() {
        var input = new ArrayList<>(bars(260));
        var b = input.getLast();
        input.set(259,new NumericalFeatureSnapshot.SourceBar(b.candleId(),b.date(),b.source(),b.receivedAt(),
                b.open(),b.high(),b.low(),b.close(),b.volume(),true));
        assertThat(calculator.calculate(b.date(),input,false).status()).isEqualTo("EXCLUDED_OBSERVATION");
        input.set(259,new NumericalFeatureSnapshot.SourceBar(b.candleId(),b.date(),b.source(),null,
                b.open(),b.high(),b.low(),BigDecimal.ZERO,b.volume(),false));
        var row = calculator.calculate(b.date(),input,false);
        assertThat(row.status()).isEqualTo("INVALID_OBSERVATION");
        assertThat(row.missingReceivedAtCount()).isEqualTo(1);
    }
    @Test void missingVolumeCannotSilentlyPass() {
        var input = new ArrayList<>(bars(252)); var b = input.getLast();
        input.set(251,new NumericalFeatureSnapshot.SourceBar(b.candleId(),b.date(),b.source(),b.receivedAt(),
                b.open(),b.high(),b.low(),b.close(),null,false));
        assertThat(calculator.calculate(b.date(),input,false).status()).isEqualTo("VOLUME_RATIO_UNAVAILABLE");
    }
    @Test void canonicalizationDeterministicAndExchangePreferred() {
        var b=bar(0);
        var nse=new NumericalFeatureSnapshot.SourceBar(900,b.date(),"NSE_BHAVCOPY",null,b.open(),b.high(),b.low(),b.close(),b.volume(),false);
        var input=new ArrayList<>(List.of(b,bar(1),nse));
        var expected=calculator.canonicalize(input); Collections.reverse(input);
        assertThat(calculator.canonicalize(input)).isEqualTo(expected);
        assertThat(expected.getFirst().candleId()).isEqualTo(900);
    }
    @Test void badScopeNeverTouchesJdbc() {
        var jdbc=mock(JdbcTemplate.class); var service=new NumericalFeatureSnapshotService(jdbc,new ObjectMapper());
        assertThatThrownBy(() -> service.inspect(runId,0,5)).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> service.inspect(null,0,4)).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> service.inspect(runId,500,4)).isInstanceOf(IllegalArgumentException.class);
        verifyNoInteractions(jdbc);
    }
    @Test void serviceBindsBoundedSqlHashesAndKeepsTrainingBlocked() throws Exception {
        var jdbc=mock(JdbcTemplate.class); var mapper=new ObjectMapper().findAndRegisterModules();
        var run=mock(ResultSet.class);var item=mock(ResultSet.class);var candle=mock(ResultSet.class);
        var asOf=LocalDate.of(2026,6,5);
        when(run.getObject("as_of",LocalDate.class)).thenReturn(asOf);
        when(run.getString("dataset_manifest_hash")).thenReturn("a".repeat(64));
        when(run.getInt("instrument_count")).thenReturn(1);
        when(item.getLong("instrument_id")).thenReturn(42L);when(item.getString("symbol")).thenReturn("FIXTURE");
        when(candle.getLong("id")).thenReturn(7L);when(candle.getObject("trading_date",LocalDate.class)).thenReturn(asOf);
        when(candle.getString("source_code")).thenReturn("UPSTOX");
        when(candle.getTimestamp("received_at")).thenReturn(Timestamp.from(Instant.parse("2026-09-01T00:00:00Z")));
        var statement=mock(PreparedStatement.class);
        doAnswer(inv -> {
            String sql=inv.getArgument(0);PreparedStatementSetter setter=inv.getArgument(1);RowMapper<?> rowMapper=inv.getArgument(2);
            setter.setValues(statement);
            var rs=sql.equals(NumericalFeatureSnapshotService.BARS_SQL)?candle:sql.equals(NumericalFeatureSnapshotService.ITEMS_SQL)?item:run;
            return List.of(rowMapper.mapRow(rs,0));
        }).when(jdbc).query(anyString(),any(PreparedStatementSetter.class),any(RowMapper.class));
        var service=new NumericalFeatureSnapshotService(jdbc,mapper);
        var result=service.inspect(runId,0,4);
        assertThat(result.payloadSha256()).matches("[a-f0-9]{64}").isEqualTo(service.inspect(runId,0,4).payloadSha256());
        assertThat(result.payload().decisionDates()).containsExactly(asOf.minusWeeks(8),asOf.minusWeeks(4),asOf);
        assertThat(result.payload().instruments().getFirst().rows()).hasSize(3);
        assertThat(result.trainingAuthorized()).isFalse();assertThat(result.databaseWritesPerformed()).isFalse();
        assertThat(result.modelCallCount()+result.providerCallCount()+result.ordersCreated()).isZero();
        verify(statement,times(2)).setLong(4,42L);
        verify(statement,times(2)).setTimestamp(6,Timestamp.from(Instant.parse("2026-06-05T18:30:00Z")));
        verify(statement,times(6)).setQueryTimeout(5);
        verify(jdbc,never()).update(anyString());
    }
    @Test void transactionAndBeanWiringAndControllerGuards() throws Exception {
        var tx=NumericalFeatureSnapshotService.class.getMethod("inspect",UUID.class,int.class,int.class).getAnnotation(Transactional.class);
        assertThat(tx.readOnly()).isTrue();assertThat(tx.timeout()).isEqualTo(30);
        assertThat(tx.isolation()).isEqualTo(Isolation.REPEATABLE_READ);
        assertThat(NumericalFeatureSnapshotService.BARS_SQL).contains("LIMIT 2001","c.instrument_id = ?","c.opened_at >= ? AND c.opened_at < ?","AS MATERIALIZED");
        new ApplicationContextRunner().withBean(JdbcTemplate.class,() -> mock(JdbcTemplate.class))
                .withBean(ObjectMapper.class,() -> new ObjectMapper().findAndRegisterModules())
                .withBean(NumericalFeatureSnapshotService.class).withBean(NumericalFeatureSnapshotController.class)
                .run(c -> assertThat(c).hasNotFailed().hasSingleBean(NumericalFeatureSnapshotController.class));
        var service=mock(NumericalFeatureSnapshotService.class);
        var mvc=MockMvcBuilders.standaloneSetup(new NumericalFeatureSnapshotController(service)).build();
        mvc.perform(get("/api/v1/training/numerical-feature-snapshot")).andExpect(status().isBadRequest());
        mvc.perform(get("/api/v1/training/numerical-feature-snapshot").param("datasetRunId",runId.toString())).andExpect(status().isOk());
        verify(service).inspect(runId,0,4);
    }
}
