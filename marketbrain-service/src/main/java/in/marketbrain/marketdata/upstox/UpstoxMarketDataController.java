package in.marketbrain.marketdata.upstox;

import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDate;
import java.util.List;

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
        } catch (ConflictingCandleDataException exception) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, exception.getMessage());
        } catch (IllegalArgumentException exception) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, exception.getMessage());
        }
    }

    @PostMapping("/corporate-actions/sync")
    public CorporateActionSyncResult syncCorporateActions(@RequestParam String symbol) {
        try {
            return service.syncCorporateActions(requireSymbol(symbol));
        } catch (IllegalArgumentException exception) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, exception.getMessage());
        } catch (IllegalStateException exception) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, exception.getMessage());
        }
    }

    @GetMapping("/corporate-actions")
    public List<CorporateActionEvidence> corporateActions(@RequestParam String symbol) {
        try {
            return service.corporateActions(requireSymbol(symbol));
        } catch (IllegalArgumentException exception) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, exception.getMessage());
        }
    }

    private String requireInstrumentKey(String value) {
        if (value == null || value.isBlank() || !value.contains("|")) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "instrumentKey must be a provider key such as NSE_EQ|INE009A01021");
        }
        return value;
    }

    private String requireSymbol(String value) {
        if (value == null || value.isBlank() || !value.matches("[A-Za-z0-9&.-]{1,64}")) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "symbol is invalid");
        }
        return value.trim().toUpperCase();
    }
}
