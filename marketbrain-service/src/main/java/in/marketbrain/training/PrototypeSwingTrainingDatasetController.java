package in.marketbrain.training;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDate;

@RestController
@RequestMapping("/api/v1/training")
public class PrototypeSwingTrainingDatasetController {

    private final PrototypeSwingTrainingDatasetService service;

    public PrototypeSwingTrainingDatasetController(PrototypeSwingTrainingDatasetService service) {
        this.service = service;
    }

    @PostMapping("/prototype-swing-dataset")
    public PrototypeSwingTrainingDatasetSummary persist(
            @RequestParam LocalDate asOf,
            @RequestParam LocalDate labelThrough,
            @RequestParam(defaultValue = "50") int assumedRoundTripCostBps,
            @RequestParam String expectedManifestHash,
            @RequestParam String reviewedBy
    ) {
        try {
            return service.persist(asOf, labelThrough, assumedRoundTripCostBps, expectedManifestHash, reviewedBy);
        } catch (IllegalArgumentException exception) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, exception.getMessage());
        } catch (IllegalStateException exception) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, exception.getMessage());
        }
    }
}
