package in.marketbrain.marketdata.upstox;

import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDate;

/** Manual, read-only feasibility endpoints. No scheduled or broker action exists here. */
@RestController
@RequestMapping("/api/v1/market-data/upstox")
public class UpstoxMarketDataController {

    private final UpstoxMarketDataService service;

    public UpstoxMarketDataController(UpstoxMarketDataService service) {
        this.service = service;
    }

    @PostMapping("/instruments/nse/import")
    public UpstoxImportResult importNseInstruments() {
        return service.importNseEquityInstruments();
    }

    @PostMapping("/quote")
    public UpstoxQuoteResult quote(@RequestParam String instrumentKey) {
        return service.fetchAndStoreQuote(requireInstrumentKey(instrumentKey));
    }

    @PostMapping("/candles/import")
    public UpstoxImportResult importCandles(
            @RequestParam String instrumentKey,
            @RequestParam(defaultValue = "days") String unit,
            @RequestParam(defaultValue = "1") int interval,
            @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate fromDate,
            @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate toDate
    ) {
        try {
            return service.importHistoricalCandles(new UpstoxHistoricalRequest(
                    requireInstrumentKey(instrumentKey), unit, interval, fromDate, toDate));
        } catch (IllegalArgumentException exception) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, exception.getMessage());
        }
    }

    private String requireInstrumentKey(String value) {
        if (value == null || value.isBlank() || !value.contains("|")) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "instrumentKey must be a provider key such as NSE_EQ|INE009A01021");
        }
        return value;
    }
}
