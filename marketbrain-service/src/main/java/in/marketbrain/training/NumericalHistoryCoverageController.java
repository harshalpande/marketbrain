package in.marketbrain.training;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import java.util.UUID;

@RestController
@RequestMapping("/api/v1/training")
public class NumericalHistoryCoverageController {
    private final NumericalHistoryCoverageService service;
    public NumericalHistoryCoverageController(NumericalHistoryCoverageService service) { this.service = service; }

    @GetMapping("/numerical-history-coverage")
    public NumericalHistoryCoverageService.CoveragePage inspect(@RequestParam UUID datasetRunId,
            @RequestParam(defaultValue = "0") int offset, @RequestParam(defaultValue = "50") int limit,
            @RequestParam(defaultValue = "730") int lookbackDays) {
        try { return service.inspect(datasetRunId, offset, limit, lookbackDays); }
        catch (IllegalArgumentException e) { throw new ResponseStatusException(HttpStatus.BAD_REQUEST, e.getMessage()); }
        catch (IllegalStateException e) { throw new ResponseStatusException(HttpStatus.CONFLICT, e.getMessage()); }
    }
}
