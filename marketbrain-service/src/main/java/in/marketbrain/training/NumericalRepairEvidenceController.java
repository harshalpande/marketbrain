package in.marketbrain.training;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;
import java.time.LocalDate;
import java.util.UUID;

@RestController
@RequestMapping("/api/v1/training")
public class NumericalRepairEvidenceController {
    private final NumericalRepairEvidenceService service;
    public NumericalRepairEvidenceController(NumericalRepairEvidenceService service){this.service=service;}
    @GetMapping("/numerical-repair-evidence")
    public NumericalRepairEvidenceService.Evidence inspect(@RequestParam UUID datasetRunId,@RequestParam LocalDate fromDate,@RequestParam LocalDate throughDate,
            @RequestParam(defaultValue="0") int offset,@RequestParam(defaultValue="4") int limit){
        try{return service.inspect(datasetRunId,fromDate,throughDate,offset,limit);}
        catch(IllegalArgumentException e){throw new ResponseStatusException(HttpStatus.BAD_REQUEST,e.getMessage());}
        catch(IllegalStateException e){throw new ResponseStatusException(HttpStatus.CONFLICT,e.getMessage());}
    }
}
