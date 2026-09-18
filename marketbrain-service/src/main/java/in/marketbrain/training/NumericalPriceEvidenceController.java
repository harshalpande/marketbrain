package in.marketbrain.training;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;
import java.time.LocalDate;
import java.util.UUID;

@RestController
@RequestMapping("/api/v1/training")
public class NumericalPriceEvidenceController {
    private final NumericalPriceEvidenceService service;
    public NumericalPriceEvidenceController(NumericalPriceEvidenceService service){this.service=service;}
    @GetMapping("/numerical-price-evidence")
    public NumericalPriceEvidenceService.Evidence inspect(@RequestParam UUID datasetRunId,@RequestParam LocalDate fromDate,
            @RequestParam(defaultValue="0") int offset,@RequestParam(defaultValue="4") int limit) {
        try{return service.inspect(datasetRunId,fromDate,offset,limit);}
        catch(IllegalArgumentException e){throw new ResponseStatusException(HttpStatus.BAD_REQUEST,e.getMessage());}
        catch(IllegalStateException e){throw new ResponseStatusException(HttpStatus.CONFLICT,e.getMessage());}
    }
}
