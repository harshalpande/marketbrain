package in.marketbrain.feature;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDate;
import java.util.NoSuchElementException;
import java.util.UUID;

@RestController
@RequestMapping("/api/v1/features/snapshots")
public class FeatureSnapshotController {

    private final FeatureSnapshotService service;

    public FeatureSnapshotController(FeatureSnapshotService service) {
        this.service = service;
    }

    @PostMapping
    public FeatureSnapshotSummary persist(
            @RequestParam LocalDate asOf,
            @RequestParam String expectedManifestHash,
            @RequestParam String reviewedBy
    ) {
        try {
            return service.persist(new FeatureSnapshotRequest(asOf, expectedManifestHash, reviewedBy));
        } catch (IllegalArgumentException exception) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, exception.getMessage());
        } catch (IllegalStateException exception) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, exception.getMessage());
        }
    }

    @GetMapping("/quality")
    public FeatureSnapshotQuality quality(
            @RequestParam UUID runId,
            @RequestParam String expectedManifestHash
    ) {
        try {
            return service.quality(runId, expectedManifestHash);
        } catch (NoSuchElementException exception) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, exception.getMessage());
        } catch (IllegalArgumentException exception) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, exception.getMessage());
        } catch (IllegalStateException exception) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, exception.getMessage());
        }
    }
}
