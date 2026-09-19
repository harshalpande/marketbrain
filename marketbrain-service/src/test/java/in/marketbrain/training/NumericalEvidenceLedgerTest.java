package in.marketbrain.training;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import java.nio.file.*;
import java.util.*;
import static in.marketbrain.training.NumericalEvidenceLedger.*;
import static org.assertj.core.api.Assertions.*;

class NumericalEvidenceLedgerTest {
    @TempDir Path root;
    Policy policy(){return new Policy(60,1000,30,128*1024);}
    @Test void completePersistenceSuite()throws Exception {
        var r=suite(root);assertThat(r.get("status")).isEqualTo("EVIDENCE_CHECKS_PASSED");assertThat(r.get("checkCount")).isEqualTo(22);assertThat(r.get("failedCheckCount")).isEqualTo(0L);
    }
    @Test void snapshotBinaryRoundTripAndInputImmutability()throws Exception {
        var s=fixture(0);assertThat(snapshot(snapshotBytes(s))).isEqualTo(s);
        assertThatThrownBy(()->s.features().clear()).isInstanceOf(UnsupportedOperationException.class);
        assertThatThrownBy(()->s.rawInputHashes().clear()).isInstanceOf(UnsupportedOperationException.class);
    }
    @Test void appendPreservesExistingBytePrefix()throws Exception {
        var store=new Store(root,policy());store.append(fixture(0));byte[] first=Files.readAllBytes(store.data);store.append(fixture(1));byte[] next=Files.readAllBytes(store.data);
        assertThat(Arrays.copyOf(next,first.length)).isEqualTo(first);assertThat(store.audit().entries()).hasSize(2);
    }
    @Test void recordIdsCanonicalizeFeatureAndHashOrdering() {
        var s=fixture(0);var reversed=new LinkedHashMap<String,Double>();var names=new ArrayList<>(s.features().keySet());Collections.reverse(names);names.forEach(n->reversed.put(n,s.features().get(n)));
        var other=change(s,s.providerEventAt(),s.receivedAt(),s.inputAvailableAt(),true,0,reversed,null,s.rightsScopeId(),s.priceActionPolicyHash(),List.of());
        assertThat(snapshotBytes(other)).isEqualTo(snapshotBytes(s));
    }
    @Test void decisionIdentityConflictDoesNotPromoteTheLatestRecord()throws Exception {
        var store=new Store(root,policy());var s=fixture(0);var original=store.append(s);var changed=new TreeMap<>(s.features());changed.put(FEATURES.getFirst(),20.0);
        var conflict=store.append(change(s,s.providerEventAt(),s.receivedAt(),s.inputAvailableAt(),true,0,changed,null,s.rightsScopeId(),s.priceActionPolicyHash(),List.of()));
        assertThat(conflict.disposition()).isEqualTo("QUARANTINED_CONFLICT");assertThat(conflict.entry().assessment().trainingEligible()).isFalse();assertThat(store.audit().entries().getFirst()).isEqualTo(original.entry());
    }
    @Test void correctionCannotReferenceAnotherDecision()throws Exception {
        var store=new Store(root,policy());var a=store.append(fixture(0));var s=fixture(1);
        var wrong=change(s,s.providerEventAt(),s.receivedAt(),s.inputAvailableAt(),true,0,s.features(),a.entry().snapshotId(),s.rightsScopeId(),s.priceActionPolicyHash(),List.of());
        assertThatThrownBy(()->store.append(wrong)).hasMessageContaining("WRONG_DECISION");assertThat(store.audit().entries()).hasSize(1);
    }
    @Test void sameRawHashDoesNotHideChangedCalculatorOrValues()throws Exception {
        var store=new Store(root,policy());var s=fixture(0);store.append(s);var f=new TreeMap<>(s.features());f.put(FEATURES.getFirst(),10.0);
        assertThat(store.append(change(s,s.providerEventAt(),s.receivedAt(),s.inputAvailableAt(),true,0,f,null,s.rightsScopeId(),s.priceActionPolicyHash(),List.of())).appended()).isTrue();
        assertThat(store.audit().entries()).hasSize(2);
    }
    @Test void exactTimeThresholdAndOneNanosecondOver() {
        var s=fixture(0);var t=s.decisionAt();
        var boundary=change(s,t.minusSeconds(60),t.minusSeconds(60),t.minusSeconds(60),true,1000,s.features(),null,s.rightsScopeId(),s.priceActionPolicyHash(),List.of());
        assertThat(assess(boundary,policy()).reasons()).isEmpty();
        var old=change(boundary,boundary.providerEventAt(),boundary.receivedAt(),boundary.inputAvailableAt().minusNanos(1),true,1000,s.features(),null,s.rightsScopeId(),s.priceActionPolicyHash(),List.of());
        assertThat(assess(old,policy()).reasons()).contains("STALE_INPUT");
    }
    @Test void freshReceiptDoesNotMakeAnOldProviderEventFresh() {
        var s=fixture(0);var old=change(s,s.decisionAt().minusSeconds(61),s.receivedAt(),s.inputAvailableAt(),true,0,s.features(),null,s.rightsScopeId(),s.priceActionPolicyHash(),List.of());
        assertThat(assess(old,policy()).reasons()).containsExactly("STALE_PROVIDER_EVENT");
    }
    @Test void receiptDoesNotManufactureProviderEventOrInputAvailability() {
        var s=fixture(0);var unknown=change(s,null,s.receivedAt(),null,true,0,s.features(),null,s.rightsScopeId(),s.priceActionPolicyHash(),List.of());
        assertThat(assess(unknown,policy()).reasons()).containsExactly("PROVIDER_EVENT_TIME_UNKNOWN","INPUT_AVAILABILITY_UNKNOWN");
        assertThat(unknown.providerEventAt()).isNull();assertThat(unknown.inputAvailableAt()).isNull();
    }
    @Test void clockAndImpossibleTimestampOrderAreNotAccepted() {
        var s=fixture(0);var bad=change(s,s.receivedAt().plusNanos(1),s.receivedAt(),s.receivedAt().minusNanos(1),true,1001,s.features(),null,s.rightsScopeId(),s.priceActionPolicyHash(),List.of());
        assertThat(assess(bad,policy()).reasons()).contains("CLOCK_UNTRUSTED","PROVIDER_EVENT_AFTER_RECEIPT","INPUT_AVAILABLE_BEFORE_RECEIPT");
    }
    @Test void allDeclaredValidMetadataStillDoesNotCertifyOrAuthorize() {
        var a=assess(fixture(0),policy());assertThat(a.status()).isEqualTo("DECLARED_STRUCTURE_VALID_NOT_CERTIFIED");assertThat(a.trainingEligible()).isFalse();assertThat(a.collectionAuthorized()).isFalse();
    }
    @Test void partialFrameRecoveryPreservesSourceAndCanContinue()throws Exception {
        var store=new Store(root.resolve("source"),policy());store.append(fixture(0));byte[] full=Files.readAllBytes(store.data);
        byte[] partialFrame=frame(payload(2,store.audit().entries().getLast().entryHash(),"ORIGINAL_RECORDED",fixture(1)));Files.write(store.data,Arrays.copyOf(partialFrame,partialFrame.length-7),StandardOpenOption.APPEND);
        byte[] damaged=Files.readAllBytes(store.data);var recovered=store.recoverTo(root.resolve("new"));assertThat(recovered.recoveredEntries()).isEqualTo(1);
        assertThat(Files.readAllBytes(store.data)).isEqualTo(damaged);assertThat(Files.readAllBytes(root.resolve("new/evidence.bin"))).isEqualTo(full);
        assertThat(new Store(root.resolve("new"),policy()).append(fixture(1)).appended()).isTrue();
    }
    @Test void reorderedFramesWithValidIndividualChecksumsFailTheChain()throws Exception {
        var a=fixture(0);var b=fixture(1);byte[] p1=payload(1,GENESIS,"ORIGINAL_RECORDED",a),p2=payload(2,sha(p1),"ORIGINAL_RECORDED",b);
        var out=new java.io.ByteArrayOutputStream();out.write(header(policy()));out.write(frame(p2));out.write(frame(p1));
        var audit=auditBytes(out.toByteArray(),policy());assertThat(audit.status()).isEqualTo("CORRUPT_ENTRY");assertThat(audit.entries()).isEmpty();
    }
    @Test void directoryInsteadOfDataFileRejected()throws Exception {
        Files.createDirectory(root.resolve("evidence.bin"));assertThatThrownBy(()->new Store(root,policy())).hasMessageContaining("NON_REGULAR");
    }
    @Test void noOperationalDefaultsOrMarketCli() {
        assertThatThrownBy(()->new Policy(0,0,10,1024)).hasMessageContaining("TIME_LIMITS");
        assertThatThrownBy(()->new Policy(60,0,10001,1024)).hasMessageContaining("STORAGE_LIMITS");
        assertThatThrownBy(()->main(new String[]{"--collect-live"})).hasMessageContaining("ONLY_FIXED_SYNTHETIC");
    }
    @Test void recordContractFeatureOrderMatchesMapperAndPlan()throws Exception {
        assertThat(FEATURES).containsExactlyElementsOf(NumericalDataContract.draft().candidateFeatures());
        var path=Path.of(System.getProperty("user.dir"));if(!Files.exists(path.resolve("ops/data")))path=path.getParent();
        var plan=NumericalResearchExportTest.MAPPER.readTree(path.resolve("ops/data/numerical-two-track-plan-v1.json").toFile());
        assertThat(plan.at("/prospective/collectionAuthorized").asBoolean()).isFalse();
        assertThat(plan.at("/retrospective/marketFitAuthorized").asBoolean()).isFalse();
    }
}
