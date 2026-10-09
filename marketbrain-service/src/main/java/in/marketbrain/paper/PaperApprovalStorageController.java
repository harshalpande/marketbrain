package in.marketbrain.paper;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;

/** Read token only authorizes status inspection, never setup, publishing or approval. */
@RestController
public class PaperApprovalStorageController {
    private final PaperApprovalStorage storage;
    private final String token,mode;
    public PaperApprovalStorageController(PaperApprovalStorage storage,
            @Value("${marketbrain.paper.read-token:}") String token,
            @Value("${marketbrain.execution-mode:PAPER}") String mode){this.storage=storage;this.token=token;this.mode=mode;}
    @GetMapping("/api/v1/paper/approval/storage")
    public ResponseEntity<PaperApprovalStorage.Status> status(@RequestHeader(value="X-MarketBrain-Paper-Read-Token",required=false) String supplied){
        if(!"PAPER".equals(mode)||!valid(token))throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,"Paper status disabled");
        if(!valid(supplied)||!MessageDigest.isEqual(token.getBytes(StandardCharsets.UTF_8),supplied.getBytes(StandardCharsets.UTF_8)))throw new ResponseStatusException(HttpStatus.UNAUTHORIZED,"Private read token required");
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(storage.status());
    }
    private static boolean valid(String s){return s!=null&&s.matches("[A-Za-z0-9_-]{32,128}");}
}
