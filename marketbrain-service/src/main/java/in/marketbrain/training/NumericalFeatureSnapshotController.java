package in.marketbrain.training;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;
import java.util.UUID;

@RestController
@RequestMapping("/api/v1/training")
public class NumericalFeatureSnapshotController {
    private final NumericalFeatureSnapshotService service;
    public NumericalFeatureSnapshotController(NumericalFeatureSnapshotService service) { this.service = service; }
    @GetMapping("/numerical-feature-snapshot")
    public NumericalFeatureSnapshotService.Snapshot inspect(@RequestParam UUID datasetRunId,
            @RequestParam(defaultValue="0") int offset, @RequestParam(defaultValue="4") int limit) {
        try { return service.inspect(datasetRunId,offset,limit); }
        catch (IllegalArgumentException e) { throw new ResponseStatusException(HttpStatus.BAD_REQUEST,e.getMessage()); }
        catch (IllegalStateException e) { throw new ResponseStatusException(HttpStatus.CONFLICT,e.getMessage()); }
    }
}
