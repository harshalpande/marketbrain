package in.marketbrain.training;

import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDate;

@RestController
@RequestMapping("/api/v1/training")
public class HistoricalMembershipSourcePreviewController {

    private final HistoricalMembershipSourcePreviewService service;

    public HistoricalMembershipSourcePreviewController(HistoricalMembershipSourcePreviewService service) {
        this.service = service;
    }

    @PostMapping(
            value = "/nifty500-membership-preview",
            consumes = {"text/csv", MediaType.APPLICATION_OCTET_STREAM_VALUE}
    )
    public HistoricalMembershipSourcePreview preview(
            @RequestParam LocalDate asOf,
            @RequestParam String sourceName,
            @RequestParam String sourceUrl,
            @RequestParam String expectedSourceSha256,
            @RequestBody byte[] payload
    ) {
        try {
            return service.preview(asOf, sourceName, sourceUrl, expectedSourceSha256, payload);
        } catch (IllegalArgumentException exception) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, exception.getMessage());
        } catch (IllegalStateException exception) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, exception.getMessage());
        }
    }
}
