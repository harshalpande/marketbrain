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
public class PrototypeSwingTrainingDatasetAuditController {

    private final PrototypeSwingTrainingDatasetAuditService service;

    public PrototypeSwingTrainingDatasetAuditController(PrototypeSwingTrainingDatasetAuditService service) {
        this.service = service;
    }

    @GetMapping("/prototype-swing-dataset-audit")
    public PrototypeSwingTrainingDatasetAudit audit(
            @RequestParam(required = false) UUID datasetRunId
    ) {
        try {
            return service.audit(datasetRunId);
        } catch (IllegalArgumentException exception) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, exception.getMessage());
        } catch (IllegalStateException exception) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, exception.getMessage());
        }
    }
}
