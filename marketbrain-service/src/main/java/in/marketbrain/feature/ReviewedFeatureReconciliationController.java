package in.marketbrain.feature;

import org.springframework.dao.DataAccessException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

@RestController
@RequestMapping("/api/v1/features/daily-automation/reviewed-reconciliation")
public class ReviewedFeatureReconciliationController {
    private final ReviewedFeatureReconciliationService service;
    public ReviewedFeatureReconciliationController(ReviewedFeatureReconciliationService service) { this.service=service; }
    @GetMapping
    public ReviewedFeatureReconciliationService.Result preview() {
        try { return service.preview(); }
        catch (IllegalStateException | DataAccessException ex) { throw conflict(ex); }
    }
    @PostMapping
    public ReviewedFeatureReconciliationService.Result apply(@RequestBody ReviewedFeatureReconciliationService.Request request) {
        try { return service.apply(request); }
        catch (IllegalArgumentException ex) { throw new ResponseStatusException(HttpStatus.BAD_REQUEST, ex.getMessage()); }
        catch (IllegalStateException | DataAccessException ex) { throw conflict(ex); }
    }
    private ResponseStatusException conflict(RuntimeException ex) {
        String reason = ex instanceof DataAccessException
                ? "Database lock, transaction or migration state needs review." : ex.getMessage();
        return new ResponseStatusException(HttpStatus.CONFLICT, reason
                + " Do not retry a write automatically; use GET to reconcile.");
    }
    @ExceptionHandler(ResponseStatusException.class)
    public ResponseEntity<ProblemDetail> problem(ResponseStatusException ex) {
        ProblemDetail detail=ProblemDetail.forStatusAndDetail(ex.getStatusCode(),ex.getReason());
        detail.setTitle("Reviewed feature reconciliation stopped");
        detail.setProperty("operation","REVIEWED_FEATURE_RECONCILIATION_V1");
        return ResponseEntity.status(ex.getStatusCode()).body(detail);
    }
}
