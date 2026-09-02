package in.marketbrain.marketdata.backfill;

import org.springframework.stereotype.Component;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;

@Component
public class YearlyBackfillChunkPlanner {

    public List<DateChunk> plan(LocalDate fromDate, LocalDate toDate) {
        if (fromDate == null || toDate == null || toDate.isBefore(fromDate)) {
            throw new IllegalArgumentException("A valid inclusive backfill date range is required");
        }
        List<DateChunk> chunks = new ArrayList<>();
        LocalDate chunkFrom = fromDate;
        while (!chunkFrom.isAfter(toDate)) {
            LocalDate annualEnd = chunkFrom.plusYears(1).minusDays(1);
            LocalDate chunkTo = annualEnd.isBefore(toDate) ? annualEnd : toDate;
            chunks.add(new DateChunk(chunkFrom, chunkTo));
            chunkFrom = chunkTo.plusDays(1);
        }
        return List.copyOf(chunks);
    }

    public record DateChunk(LocalDate fromDate, LocalDate toDate) {
    }
}
