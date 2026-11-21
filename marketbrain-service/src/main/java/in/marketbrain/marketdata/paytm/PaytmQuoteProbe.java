package in.marketbrain.marketdata.paytm;

import com.fasterxml.jackson.databind.JsonNode;
import java.math.BigDecimal;
import java.time.*;
import java.util.*;

/** Diagnostic only: provider security ID is not yet mapped to the local instrument master. */
final class PaytmQuoteProbe {
    static Map<String,Object> assess(JsonNode reply, int securityId, Instant observed) {
        Map<String,Object> out = new LinkedHashMap<>();
        out.put("securityId", securityId);
        out.put("exchange", "NSE");
        out.put("scripType", "EQUITY");
        out.put("observedEpochMilliseconds", observed.toEpochMilli());
        out.put("timestampEpoch", "PAYTM_1980_SECONDS");
        out.put("mappingVerified", false);
        out.put("ordersEnabled", false);
        out.put("fresh", false);
        out.put("status", "MALFORMED_QUOTE");
        if (reply == null || !reply.isObject() || reply.has("error") || reply.has("error_code")
                || reply.path("status").asText().matches("(?i)false|failure|failed|error|[45][0-9][0-9]")
                || (reply.has("success") && !reply.path("success").asBoolean())) return out;
        JsonNode data = reply.path("data");
        if (!data.isArray() || data.size()!=1) return out;
        JsonNode q=data.get(0);
        if (!q.path("security_id").isIntegralNumber() || !q.path("security_id").canConvertToInt()
                || q.path("security_id").intValue()!=securityId || !"LTP".equals(q.path("mode").asText())) return out;
        if (!q.path("found").isBoolean()) return out;
        if (!q.path("found").booleanValue()) { out.put("status","NO_QUOTE"); return out; }
        if (!q.path("last_price").isNumber()) return out;
        BigDecimal price=q.path("last_price").decimalValue();
        if(price.signum()<=0 || price.compareTo(new BigDecimal("1000000000"))>0) return out;
        out.put("lastPrice",price);
        JsonNode timestamp=q.path("last_trade_time");
        if (!timestamp.isIntegralNumber() || !timestamp.canConvertToLong()
                || timestamp.longValue()<=0 || timestamp.longValue()>3786912000L) {
            out.put("status","MISSING_OR_INVALID_TIMESTAMP"); return out;
        }
        long raw=timestamp.longValue();
        // Official pyPMClient epochConverterUtil: exchange seconds since 1980, not Unix seconds.
        Instant traded=Instant.ofEpochSecond(raw+315532800L);
        long age=Duration.between(traded,observed).toMillis();
        out.put("rawTradeTime",raw);out.put("tradeEpochMilliseconds",traded.toEpochMilli());out.put("ageMilliseconds",age);
        if(age<0) out.put("status","FUTURE_TIMESTAMP");
        else if(age>15000) out.put("status","STALE_QUOTE");
        else {out.put("status","FRESH_QUOTE_OBSERVED");out.put("fresh",true);}
        return out;
    }
}
