package in.marketbrain.marketdata.paytm;
import java.nio.charset.StandardCharsets;
import java.util.*;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import static org.assertj.core.api.Assertions.*;

class PaytmReviewIdentityTest {
    static String master(){return "security_id,symbol,exchange,series,segment,instrument_type\n2885,RELIANCE,NSE,EQ,E,ES\n";}
    static String members(){
        StringBuilder s=new StringBuilder("Company Name,Industry,Symbol,Series,ISIN Code\nReliance,Industry,RELIANCE,EQ,INE002A01018\n");
        for(int i=1;i<450;i++)s.append("Company,Industry,S").append(i).append(",EQ,").append(String.format("INE%09d",i)).append('\n');
        return s.toString();
    }
    static Map<String,Object> local(){return new PaytmUniverseMatch(s->List.of(PaytmUniverseMatchTest.row())).inspect("RELIANCE");}
    static PaytmReviewIdentity source(String master,String members){return new PaytmReviewIdentity(uri->(uri.equals(PaytmReviewIdentity.PAYTM)?master:members).getBytes(StandardCharsets.UTF_8));}
    @Test void bindsUniqueSymbolToOfficialConstituentAndLocalIsin(){
        var r=source(master(),members()).resolve("RELIANCE",local());
        assertThat(r.securityId()).isEqualTo(2885);assertThat(r.isin()).isEqualTo("INE002A01018");
        assertThat(r.providerSha256()).hasSize(64);assertThat(r.constituentSha256()).hasSize(64);
        assertThat(r.evidence()).containsEntry("providerIsinVerified",false).containsEntry("membershipScope","LATEST_PUBLISHED_FILE");
    }
    @ParameterizedTest @ValueSource(strings={"duplicate","aliasId","leadingZeroAlias","wrongSeries","badId","badCsv","missingHeader","missingMember","wrongIsin","smallList","sourceError","localMismatch","badSymbol"})
    void rejectsBeforeQuoteWhenAnyIdentityLinkIsMissing(String defect){
        String m=master(),n=members();var local=local();String symbol="RELIANCE";
        switch(defect){
            case "duplicate" -> m+="2885,RELIANCE,NSE,EQ,E,ES\n";
            case "aliasId" -> m+="2885,OTHER,NSE,EQ,E,ES\n";
            case "leadingZeroAlias" -> m+="02885,OTHER,NSE,EQ,E,ES\n";
            case "wrongSeries" -> m=m.replace(",EQ,",",BE,");
            case "badId" -> m=m.replace("2885","-1");
            case "badCsv" -> m=m.replace("RELIANCE","\"RELIANCE");
            case "missingHeader" -> m=m.replace("security_id","other");
            case "missingMember" -> n=n.replace("RELIANCE","OTHER");
            case "wrongIsin" -> n=n.replace("INE002A01018","INE009A01021");
            case "smallList" -> n=n.lines().limit(2).reduce("",(a,b)->a+b+"\n");
            case "localMismatch" -> local.put("snapshotMatched",false);
            case "badSymbol" -> symbol="../RELIANCE";
        }
        var resolver=defect.equals("sourceError")?new PaytmReviewIdentity(uri->{throw new Exception("PRIVATE_SOURCE_ERROR");}):source(m,n);
        String selected=symbol;
        assertThatThrownBy(()->resolver.resolve(selected,local)).isInstanceOf(RuntimeException.class).hasMessageMatching("PAYTM_IDENTITY_[A-Z_]+");
    }
    @Test void parsesQuotedFieldsAndRejectsUnclosedOrExtraQuotes(){
        assertThat(PaytmReviewIdentity.fields("\"a,b\",\"c\"\"d\",x")).containsExactly("a,b","c\"d","x");
        assertThatThrownBy(()->PaytmReviewIdentity.fields("a,\"b")).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(()->PaytmReviewIdentity.fields("\"a\"x,b")).isInstanceOf(IllegalArgumentException.class);
    }
    @ParameterizedTest @ValueSource(strings={"RR","BE"})
    void unrelatedOtherSeriesDoNotRejectRequestedEqMember(String series){
        String mixed=members().replace("S1,EQ,","S1,"+series+",");
        assertThat(source(master(),mixed).resolve("RELIANCE",local()).securityId()).isEqualTo(2885);
        String requested=members().replace("RELIANCE,EQ,","RELIANCE,"+series+",");
        assertThatThrownBy(()->source(master(),requested).resolve("RELIANCE",local())).hasMessage("PAYTM_IDENTITY_NIFTY_PARSE_FAILED");
    }
    @ParameterizedTest @ValueSource(strings={"duplicateSymbol","duplicateIsin","invalidIsin","badWidth"})
    void mixedSeriesStillValidatesAllRows(String defect){
        String csv=members().replace("S1,EQ,","S1,RR,");
        csv=switch(defect){
            case "duplicateSymbol" -> csv.replace("S2,EQ,","S1,EQ,");
            case "duplicateIsin" -> csv.replace("INE000000002","INE000000001");
            case "invalidIsin" -> csv.replace("INE000000001","INVALID");
            default -> csv.replace("S1,RR,","S1,RR,extra,");
        };
        var resolver=source(master(),csv);
        assertThatThrownBy(()->resolver.resolve("RELIANCE",local())).hasMessage("PAYTM_IDENTITY_NIFTY_PARSE_FAILED");
    }
    @Test void distinguishesDownloadAndMatchFailuresWithoutLeakingSourceDetails(){
        assertThatThrownBy(()->new PaytmReviewIdentity(uri->{throw new Exception("PRIVATE");}).resolve("RELIANCE",local())).hasMessage("PAYTM_IDENTITY_PAYTM_DOWNLOAD_FAILED");
        assertThatThrownBy(()->new PaytmReviewIdentity(uri->{if(uri.equals(PaytmReviewIdentity.NIFTY))throw new Exception("PRIVATE");return master().getBytes(StandardCharsets.UTF_8);}).resolve("RELIANCE",local())).hasMessage("PAYTM_IDENTITY_NIFTY_DOWNLOAD_FAILED");
        assertThatThrownBy(()->source(master(),members().replace("INE002A01018","INE009A01021")).resolve("RELIANCE",local())).hasMessage("PAYTM_IDENTITY_ISIN_MATCH_FAILED");
    }
}
