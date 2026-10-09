package in.marketbrain.paper;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.dao.DataAccessException;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;

/** Local/private read-only access. This token is NOT authority to approve or execute trades. */
@RestController
public class PaperAccountReadController {
    private final PaperAccountReadService service;
    private final String token;
    private final String mode;

    public PaperAccountReadController(PaperAccountReadService service,
            @Value("${marketbrain.paper.read-token:}") String token,
            @Value("${marketbrain.execution-mode:PAPER}") String mode) {
        this.service = service; this.token = token; this.mode = mode;
    }

    @GetMapping("/api/v1/paper/account/overview")
    public ResponseEntity<PaperAccountReadService.Overview> overview(
            @RequestHeader(value = "X-MarketBrain-Paper-Read-Token", required = false) String supplied) {
        if (!"PAPER".equals(mode) || !validToken(token)) {
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE, "Paper account read access is disabled.");
        }
        if (!validToken(supplied) || !MessageDigest.isEqual(token.getBytes(StandardCharsets.UTF_8),
                supplied.getBytes(StandardCharsets.UTF_8))) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Paper read token required.");
        }
        try {
            return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(service.overview());
        } catch (DataAccessException unavailable) {
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE, "Account unavailable; no action performed.");
        }
    }

    private static boolean validToken(String value) {
        return value != null && value.matches("[A-Za-z0-9_-]{32,128}");
    }
}
