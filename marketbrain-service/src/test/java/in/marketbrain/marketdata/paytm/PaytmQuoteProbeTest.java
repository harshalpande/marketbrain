package in.marketbrain.marketdata.paytm;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import java.time.*;
import java.net.URI;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import static org.assertj.core.api.Assertions.*;

class PaytmQuoteProbeTest {
    static final Instant NOW=Instant.parse("2026-11-21T06:00:00Z");
    static ObjectNode reply(long ageMs) {
        ObjectNode root=new ObjectMapper().createObjectNode();
        root.putArray("data").addObject().put("security_id",3456).put("mode","LTP")
            .put("found",true).put("last_price",423.75)
            .put("last_trade_time",NOW.minusMillis(ageMs).getEpochSecond()-315532800);
        return root;
    }
    @Test void usesDocumentedEpochAndExactFifteenSecondBoundary() {
        var result=PaytmQuoteProbe.assess(reply(15000),3456,NOW);
        assertThat(result).containsEntry("fresh",true).containsEntry("ageMilliseconds",15000L)
            .containsEntry("mappingVerified",false).containsEntry("ordersEnabled",false);
        assertThat(PaytmQuoteProbe.assess(reply(16000),3456,NOW)).containsEntry("status","STALE_QUOTE").containsEntry("fresh",false);
        assertThat(PaytmQuoteProbe.assess(reply(-1000),3456,NOW)).containsEntry("status","FUTURE_TIMESTAMP").containsEntry("fresh",false);
    }
    @ParameterizedTest @ValueSource(strings={"wrongId","wrongMode","duplicate","missingPrice","negativePrice","textPrice","missingTime","millisTime","error","notFound"})
    void refusesBadOrMissingData(String defect) {
        var root=reply(0);var row=(ObjectNode)root.path("data").get(0);
        switch(defect) {
            case "wrongId" -> row.put("security_id",1);
            case "wrongMode" -> row.put("mode","CAS");
            case "duplicate" -> ((com.fasterxml.jackson.databind.node.ArrayNode)root.path("data")).add(row.deepCopy());
            case "missingPrice" -> row.remove("last_price");
            case "negativePrice" -> row.put("last_price",-1);
            case "textPrice" -> row.put("last_price","423.75");
            case "missingTime" -> row.remove("last_trade_time");
            case "millisTime" -> row.put("last_trade_time",NOW.toEpochMilli());
            case "error" -> root.put("error_code","private error must not escape");
            case "notFound" -> row.put("found",false);
        }
        assertThat(PaytmQuoteProbe.assess(root,3456,NOW)).containsEntry("fresh",false).doesNotContainValue("private error must not escape");
    }
    @Test void destinationAllowsOnlyExactReadQuery() {
        String base="https://developer.paytmmoney.com";
        assertThat(PaytmSupervisedClient.allowed(URI.create(base+"/data/v1/price/live?mode=LTP&pref=NSE:3456:EQUITY"))).isTrue();
        for(String suffix:new String[]{"/orders/v1/place","/data/v1/price/live?mode=LTP&pref=NSE:3456:EQUITY&extra=1","/data/v1/price/live?mode=LTP&pref=NSE:3456:EQUITY#x","/data/v1/price/live?mode=LTP&pref=NSE:3456:OPTION"})
            assertThat(PaytmSupervisedClient.allowed(URI.create(base+suffix))).isFalse();
    }
}
