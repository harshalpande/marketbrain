package in.marketbrain.marketdata.universe;

import java.time.LocalDate;

public record NseEquitySecurity(
        String symbol,
        String companyName,
        String series,
        LocalDate listedOn,
        String isin
) {
}
