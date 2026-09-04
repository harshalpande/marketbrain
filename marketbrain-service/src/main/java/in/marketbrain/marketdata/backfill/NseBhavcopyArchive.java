package in.marketbrain.marketdata.backfill;

import java.time.LocalDate;
import java.util.List;

record NseBhavcopyArchive(
        String status,
        LocalDate tradingDate,
        String format,
        String sourceUrl,
        List<NseBhavcopyRecord> records,
        String detail
) {
    boolean succeeded() {
        return "SUCCESS".equals(status);
    }

    static NseBhavcopyArchive failure(
            String status,
            LocalDate tradingDate,
            String format,
            String sourceUrl,
            String detail
    ) {
        return new NseBhavcopyArchive(status, tradingDate, format, sourceUrl, List.of(), detail);
    }
}
