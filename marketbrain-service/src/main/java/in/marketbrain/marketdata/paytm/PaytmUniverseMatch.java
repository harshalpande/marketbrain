package in.marketbrain.marketdata.paytm;

import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;

/** Read only, saved-snapshot corroboration. Does not establish current membership or provider ISIN. */
final class PaytmUniverseMatch {
    static final String SQL="""
        WITH latest AS (
          SELECT id, observed_on FROM universe_snapshot
          WHERE universe_code = 'NIFTY_500'
          ORDER BY observed_on DESC, received_at DESC, id DESC LIMIT 1
        )
        SELECT s.id::text, s.observed_on::text, m.source_isin, m.match_status,
               i.id, i.isin, i.active, i.symbol, i.exchange
        FROM latest s
        LEFT JOIN universe_snapshot_member m ON m.snapshot_id=s.id AND m.source_symbol=?
        LEFT JOIN instrument i ON i.id=m.instrument_id
        LIMIT 2
        """;
    record Row(String snapshotId,String observedOn,String sourceIsin,String matchStatus,
               long instrumentId,String isin,boolean active,String symbol,String exchange) { }
    private final java.util.function.Function<String,List<Row>> lookup;
    PaytmUniverseMatch(JdbcTemplate applicationJdbc) {
        JdbcTemplate read=new JdbcTemplate(Objects.requireNonNull(applicationJdbc.getDataSource()));
        read.setQueryTimeout(5);read.setMaxRows(2);
        lookup=symbol->read.query(SQL,(rs,n)->new Row(rs.getString(1),rs.getString(2),rs.getString(3),rs.getString(4),
                rs.getLong(5),rs.getString(6),rs.getBoolean(7),rs.getString(8),rs.getString(9)),symbol);
    }
    PaytmUniverseMatch(java.util.function.Function<String,List<Row>> lookup){this.lookup=lookup;}
    Map<String,Object> inspect(String symbol) {
        if(symbol==null || !symbol.matches("[A-Z0-9][A-Z0-9&-]{0,29}"))throw new IllegalArgumentException("UNIVERSE_SYMBOL_INVALID");
        Map<String,Object> out=new LinkedHashMap<>();
        out.put("symbol",symbol);out.put("ordersEnabled",false);out.put("currentMembershipVerified",false);
        out.put("providerIsinVerified",false);out.put("snapshotMatched",false);
        out.put("status","LOCAL_UNIVERSE_NOT_MATCHED");
        List<Row> rows=lookup.apply(symbol);
        if(rows.isEmpty()){out.put("status","LOCAL_UNIVERSE_SNAPSHOT_MISSING");return out;}
        if(rows.size()!=1){out.put("status","LOCAL_UNIVERSE_AMBIGUOUS");return out;}
        Row r=rows.getFirst();
        out.put("snapshotId",UUID.fromString(r.snapshotId()).toString());
        out.put("observedOn",java.time.LocalDate.parse(r.observedOn()).toString());
        if(!"MATCHED".equals(r.matchStatus()) || !r.active() || r.instrumentId()<=0
                || !"NSE".equals(r.exchange()) || !symbol.equals(r.symbol()) || r.isin()==null
                || !r.isin().matches("[A-Z]{2}[A-Z0-9]{9}[0-9]") || !r.isin().equals(r.sourceIsin()))return out;
        out.put("instrumentId",r.instrumentId());out.put("isin",r.isin());out.put("snapshotMatched",true);
        out.put("status","LOCAL_SNAPSHOT_SYMBOL_ISIN_MATCHED");return out;
    }
}
