package in.marketbrain.feature;

import in.marketbrain.marketdata.backfill.*;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.context.annotation.AnnotationConfigApplicationContext;
import org.springframework.context.annotation.Configuration;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.annotation.EnableTransactionManagement;
import org.springframework.transaction.annotation.Isolation;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.AbstractPlatformTransactionManager;
import org.springframework.transaction.support.DefaultTransactionStatus;
import org.springframework.web.server.ResponseStatusException;

import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import static in.marketbrain.feature.ReviewedFeatureReconciliationService.*;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class ReviewedFeatureReconciliationTest {
    JdbcTemplate jdbc;
    FeatureSnapshotService snapshots;
    BackfillQualityService quality;
    ReviewedFeatureReconciliationService service;
    BackfillQualityReport daily;
    FeatureSnapshotQuality stored;
    Row row;
    Audit audit;
    List<String> reads, writes;
    int affected;

    @BeforeEach
    @SuppressWarnings("unchecked")
    void setup() {
        jdbc=mock(JdbcTemplate.class); snapshots=mock(FeatureSnapshotService.class); quality=mock(BackfillQualityService.class);
        service=new ReviewedFeatureReconciliationService(jdbc,snapshots,quality);
        reads=new ArrayList<>(); writes=new ArrayList<>(); affected=1;
        row=new Row("REVIEW_REQUIRED",null,MANIFEST,487,13,"DATABASE_QUALITY",1,"SENT",null);
        stored=new FeatureSnapshotQuality("ELIGIBLE",SNAPSHOT,DATE,"TECHNICAL_V1",MANIFEST,MANIFEST,
                500,487,13,500,487,13,0,0,0,0,true,false,"fixture");
        when(snapshots.quality(SNAPSHOT,MANIFEST)).thenAnswer(i -> stored);
        daily=mock(BackfillQualityReport.class);
        when(daily.jobId()).thenReturn(DAILY); when(daily.jobStatus()).thenReturn("COMPLETED");
        when(daily.qualityStatus()).thenReturn("PASS"); when(daily.requestedTo()).thenReturn(DATE);
        when(daily.requestedFrom()).thenReturn(LocalDate.of(2026,9,19)); when(daily.instrumentCount()).thenReturn(500);
        when(daily.currentResolutions()).thenReturn(List.of(new QualityResolutionRecord(RESOLUTION,DAILY,"POLICYBZR",
                QualityFindingType.LARGE_MOVE,LocalDate.of(2026,9,24),null,QualityResolutionType.VERIFIED_EXCHANGE_MOVE,
                true,"fixture","https://example.invalid","fixture","historical label",null,null,null)));
        when(quality.audit(DAILY,false)).thenReturn(daily);
        when(jdbc.query(anyString(),any(RowMapper.class),any(Object[].class))).thenAnswer(i -> {
            String sql=i.getArgument(0); reads.add(sql);
            if(sql.contains("FROM daily_feature_snapshot_automation a")) return row==null?List.of():List.of(row);
            if(sql.contains("FROM reviewed_feature_reconciliation")) return audit==null?List.of():List.of(audit);
            throw new AssertionError("Unexpected query: "+sql);
        });
        when(jdbc.update(anyString(),any(Object[].class))).thenAnswer(i -> {
            String sql=i.getArgument(0); writes.add(sql);
            if(sql.contains("INSERT INTO reviewed_feature_reconciliation")) {
                audit=new Audit(i.getArgument(1),DAILY,SNAPSHOT,MANIFEST,EVIDENCE,"Harshal Pande");
                return affected;
            }
            if(sql.contains("UPDATE daily_feature_snapshot_automation")) {
                row=new Row("COMPLETED",SNAPSHOT,MANIFEST,487,13,null,1,"SENT",null);
                return affected;
            }
            throw new AssertionError("Unexpected mutation: "+sql);
        });
    }
    Request request(){return new Request(EVIDENCE,"Harshal Pande");}

    @Test void previewDoesNotLockOrWriteOrPersistFeatures() {
        Result result=service.preview(); assertThat(result.status()).isEqualTo("READY_TO_RECONCILE");
        assertThat(result.databaseWritesPerformed()).isFalse(); assertThat(writes).isEmpty();
        assertThat(reads).noneMatch(s -> s.contains("FOR UPDATE"));
        verify(snapshots,never()).persist(any()); verify(quality).audit(DAILY,false);
    }
    @Test void applyThenReplayAndGetNeverDuplicateTheAuditOrRegenerate() {
        Result applied=service.apply(request()); assertThat(applied.status()).isEqualTo("RECONCILED");
        assertThat(applied.databaseWritesPerformed()).isTrue(); assertThat(applied.reconciliationId()).isEqualTo(audit.id());
        assertThat(applied.completionNotificationStatus()).isNull(); assertThat(applied.snapshotWrites()).isZero();
        assertThat(applied.signalsCreated()).isZero(); assertThat(applied.ordersCreated()).isZero();
        assertThat(service.apply(request()).status()).isEqualTo("ALREADY_RECONCILED");
        assertThat(service.preview().databaseWritesPerformed()).isFalse(); assertThat(writes).hasSize(2);
        assertThat(reads).anyMatch(s -> s.contains("FOR UPDATE OF a NOWAIT"));
        assertThat(writes).allMatch(s -> !s.contains("UPDATE feature_snapshot") && !s.contains("daily_enrichment_notification"));
        verify(snapshots,never()).persist(any());
    }
    @ParameterizedTest @ValueSource(strings={"RUNNING","PENDING","RETRY","FAILED","COMPLETED"})
    void rejectsOtherStates(String status) {
        row=new Row(status,null,MANIFEST,487,13,"DATABASE_QUALITY",1,"SENT",null);
        assertThatThrownBy(() -> service.apply(request())).isInstanceOf(IllegalStateException.class);
        assertThat(writes).isEmpty(); verifyNoInteractions(snapshots,quality);
    }
    @ParameterizedTest @ValueSource(strings={" ","RESOLVE POLICYBZR 2026-09-24","RECONCILE FEATURES 2026-10-08","YES"})
    void rejectsConfirmationAsName(String name) {
        assertThatThrownBy(() -> service.apply(new Request(EVIDENCE,name))).isInstanceOf(IllegalArgumentException.class);
        verifyNoInteractions(jdbc,snapshots,quality);
    }
    @Test void rejectsUnacceptedEvidence() {
        assertThatThrownBy(() -> service.apply(new Request("0".repeat(64),"Harshal"))).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> service.apply(null)).isInstanceOf(IllegalArgumentException.class); verifyNoInteractions(jdbc);
    }
    @Test void rejectsMissingOrChangedScope() {
        row=null; assertThatThrownBy(() -> service.apply(request())).isInstanceOf(IllegalStateException.class); assertThat(writes).isEmpty();
    }
    @ParameterizedTest @ValueSource(strings={"manifest","counts","attempts","warning","completion","reason","linked"})
    void rejectsChangedCheckpoint(String change) {
        row=new Row("REVIEW_REQUIRED",change.equals("linked")?SNAPSHOT:null,change.equals("manifest")?"bad":MANIFEST,
                change.equals("counts")?486:487,13,change.equals("reason")?"OTHER":"DATABASE_QUALITY",
                change.equals("attempts")?2:1,change.equals("warning")?"SENDING":"SENT",change.equals("completion")?"SENT":null);
        assertThatThrownBy(() -> service.apply(request())).isInstanceOf(IllegalStateException.class); assertThat(writes).isEmpty();
    }
    @Test void rejectsDifferentReviewerOnReplay() {
        service.apply(request()); assertThatThrownBy(() -> service.apply(new Request(EVIDENCE,"Other reviewer"))).isInstanceOf(IllegalStateException.class);
        assertThat(writes).hasSize(2);
    }
    @Test void rejectsBadStoredHashBeforeWrites() {
        stored=new FeatureSnapshotQuality("ELIGIBLE",SNAPSHOT,DATE,"TECHNICAL_V1",MANIFEST,"bad",500,487,13,500,487,13,0,0,0,0,true,false,"");
        assertThatThrownBy(() -> service.apply(request())).isInstanceOf(IllegalStateException.class); assertThat(writes).isEmpty();
    }
    @ParameterizedTest @ValueSource(strings={"quality","open","resolution","provider","date","duplicates","truncated","count"})
    void rejectsChangedDailyQuality(String change) {
        switch(change) {
            case "quality" -> when(daily.qualityStatus()).thenReturn("REVIEW");
            case "open" -> when(daily.unresolvedFindingCount()).thenReturn(1);
            case "resolution" -> when(daily.currentResolutions()).thenReturn(List.of());
            case "provider" -> when(daily.providerSpotCheckRequested()).thenReturn(true);
            case "date" -> when(daily.requestedTo()).thenReturn(DATE.plusDays(1));
            case "duplicates" -> when(daily.duplicateRows()).thenReturn(1);
            case "truncated" -> when(daily.truncatedFindingCount()).thenReturn(1);
            case "count" -> when(daily.instrumentCount()).thenReturn(499);
        }
        assertThatThrownBy(() -> service.apply(request())).isInstanceOf(IllegalStateException.class); assertThat(writes).isEmpty();
    }
    @Test void rejectsZeroAffectedRows() {
        affected=0; assertThatThrownBy(() -> service.apply(request())).isInstanceOf(IllegalStateException.class).hasMessageContaining("Audit insert");
        assertThat(writes).hasSize(1);
    }
    @Configuration @EnableTransactionManagement
    static class TxConfiguration { }
    static class RecordingTransactionManager extends AbstractPlatformTransactionManager {
        int commits, rollbacks;
        boolean active;
        @Override protected Object doGetTransaction(){return new Object();}
        @Override protected boolean isExistingTransaction(Object transaction){return active;}
        @Override protected void doBegin(Object transaction, TransactionDefinition definition){active=true;}
        @Override protected void doCommit(DefaultTransactionStatus status){commits++;}
        @Override protected void doRollback(DefaultTransactionStatus status){rollbacks++;}
        @Override protected void doCleanupAfterCompletion(Object transaction){active=false;}
    }
    @Test void springWiringCommitsTogetherAndRequestsRollbackOnCheckpointFailure() {
        var manager=new RecordingTransactionManager();
        try(var context=new AnnotationConfigApplicationContext()) {
            context.register(TxConfiguration.class,ReviewedFeatureReconciliationService.class,ReviewedFeatureReconciliationController.class);
            context.registerBean(JdbcTemplate.class,() -> jdbc);
            context.registerBean(FeatureSnapshotService.class,() -> snapshots);
            context.registerBean(BackfillQualityService.class,() -> quality);
            context.registerBean("transactionManager",RecordingTransactionManager.class,() -> manager);
            context.refresh();
            var controller=context.getBean(ReviewedFeatureReconciliationController.class);
            assertThat(controller.apply(request()).status()).isEqualTo("RECONCILED");
            assertThat(manager.commits).isEqualTo(1); assertThat(manager.rollbacks).isZero();
            row=new Row("REVIEW_REQUIRED",null,MANIFEST,487,13,"DATABASE_QUALITY",1,"SENT",null); audit=null;
            doReturn(0).when(jdbc).update(contains("UPDATE daily_feature_snapshot_automation"),any(Object[].class));
            assertThatThrownBy(() -> controller.apply(request())).isInstanceOf(ResponseStatusException.class);
            assertThat(manager.commits).isEqualTo(1); assertThat(manager.rollbacks).isEqualTo(1);
            // AOP semantics only; mocked JDBC is not evidence of actual PostgreSQL rollback/concurrency.
        }
    }
    @Test void transactionBoundaryAndMigrationAreExplicit() throws Exception {
        Transactional tx=ReviewedFeatureReconciliationService.class.getMethod("apply",Request.class).getAnnotation(Transactional.class);
        assertThat(tx.readOnly()).isFalse(); assertThat(tx.timeout()).isEqualTo(180); assertThat(tx.isolation()).isEqualTo(Isolation.REPEATABLE_READ);
        assertThat(ReviewedFeatureReconciliationService.class.getMethod("preview").getAnnotation(Transactional.class).readOnly()).isTrue();
        try(var stream=getClass().getResourceAsStream("/db/migration/V26__record_reviewed_feature_reconciliation.sql")) {
            assertThat(stream).isNotNull(); String sql=new String(stream.readAllBytes(),StandardCharsets.UTF_8);
            assertThat(sql).contains("target_date DATE NOT NULL UNIQUE","BEFORE UPDATE OR DELETE","previous_error_code","previous_updated_at");
            assertThat(sql).doesNotContain("UPDATE daily_feature_snapshot_automation","DELETE FROM","INSERT INTO daily_enrichment_notification");
        }
    }
    @Test void controllerDelegatesAndMapsErrors() {
        ReviewedFeatureReconciliationService stub=mock(ReviewedFeatureReconciliationService.class);
        var controller=new ReviewedFeatureReconciliationController(stub);
        controller.preview(); verify(stub).preview(); controller.apply(request()); verify(stub).apply(request());
        when(stub.apply(any())).thenThrow(new IllegalArgumentException("bad request"));
        assertThatThrownBy(() -> controller.apply(request())).isInstanceOfSatisfying(ResponseStatusException.class,e -> assertThat(e.getStatusCode().value()).isEqualTo(400));
        when(stub.preview()).thenThrow(new IllegalStateException("conflict"));
        assertThatThrownBy(controller::preview).isInstanceOfSatisfying(ResponseStatusException.class,e -> assertThat(e.getStatusCode().value()).isEqualTo(409));
    }
    @Test void httpConflictPreservesGuardReasonButHidesDatabaseDetails() throws Exception {
        var stub=mock(ReviewedFeatureReconciliationService.class);
        var mvc=org.springframework.test.web.servlet.setup.MockMvcBuilders.standaloneSetup(new ReviewedFeatureReconciliationController(stub)).build();
        when(stub.preview()).thenThrow(new IllegalStateException("Stored snapshot quality changed."));
        var response=mvc.perform(org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get("/api/v1/features/daily-automation/reviewed-reconciliation"))
                .andReturn().getResponse();
        assertThat(response.getStatus()).isEqualTo(409); assertThat(response.getContentAsString()).contains("Stored snapshot quality changed.");
        doThrow(new org.springframework.dao.DataAccessResourceFailureException("sensitive driver details")).when(stub).preview();
        response=mvc.perform(org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get("/api/v1/features/daily-automation/reviewed-reconciliation"))
                .andReturn().getResponse();
        assertThat(response.getStatus()).isEqualTo(409); assertThat(response.getContentAsString()).contains("Database lock, transaction or migration").doesNotContain("sensitive driver details");
    }
}
