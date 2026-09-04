package in.marketbrain.marketdata.backfill;

import java.math.BigDecimal;
import java.time.LocalDate;

record NseBhavcopyRecord(
        String symbol,
        String isin,
        String series,
        LocalDate tradingDate,
        BigDecimal previousClose,
        BigDecimal open,
        BigDecimal high,
        BigDecimal low,
        BigDecimal close,
        BigDecimal volume
) {
}
