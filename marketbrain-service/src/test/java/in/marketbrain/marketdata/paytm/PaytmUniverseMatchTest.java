package in.marketbrain.marketdata.paytm;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import java.util.*;
import static org.assertj.core.api.Assertions.*;

class PaytmUniverseMatchTest {
    static final String ID="11111111-1111-1111-1111-111111111111",ISIN="INE002A01018";
    static PaytmUniverseMatch.Row row(){return new PaytmUniverseMatch.Row(ID,"2026-09-18",ISIN,"MATCHED",1,ISIN,true,"RELIANCE","NSE");}
    @Test void reportsDatedSnapshotWithoutClaimingProviderIsinOrCurrentMembership(){
        var m=new PaytmUniverseMatch(symbol->{assertThat(symbol).isEqualTo("RELIANCE");return List.of(row());});
        assertThat(m.inspect("RELIANCE")).containsEntry("snapshotMatched",true).containsEntry("observedOn","2026-09-18")
            .containsEntry("currentMembershipVerified",false).containsEntry("providerIsinVerified",false).containsEntry("ordersEnabled",false);
    }
    @Test void rejectsMissingAmbiguousAndInvalidInput(){
        assertThat(new PaytmUniverseMatch(s->List.of()).inspect("RELIANCE")).containsEntry("status","LOCAL_UNIVERSE_SNAPSHOT_MISSING");
        assertThat(new PaytmUniverseMatch(s->List.of(row(),row())).inspect("RELIANCE")).containsEntry("status","LOCAL_UNIVERSE_AMBIGUOUS");
        assertThatThrownBy(()->new PaytmUniverseMatch(s->{throw new AssertionError("Must not query");}).inspect("' OR 1=1"))
            .hasMessage("UNIVERSE_SYMBOL_INVALID");
    }
    @ParameterizedTest @ValueSource(strings={"inactive","isin","symbol","exchange","unmatched","missing"})
    void identityMismatchNeverPasses(String defect){
        var r=new PaytmUniverseMatch.Row(ID,"2026-09-18",ISIN,defect.equals("unmatched")?"UNMATCHED":"MATCHED",1,
            defect.equals("missing")?null:defect.equals("isin")?"INE009A01021":ISIN,!defect.equals("inactive"),defect.equals("symbol")?"OTHER":"RELIANCE",defect.equals("exchange")?"BSE":"NSE");
        assertThat(new PaytmUniverseMatch(s->List.of(r)).inspect("RELIANCE")).containsEntry("snapshotMatched",false);
    }
}
