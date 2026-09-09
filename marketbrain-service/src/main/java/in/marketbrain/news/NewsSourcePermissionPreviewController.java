package in.marketbrain.news;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

@RestController
@RequestMapping("/api/v1/news/source-permissions")
public class NewsSourcePermissionPreviewController {

    private final NewsSourcePermissionPreviewService service;

    public NewsSourcePermissionPreviewController(NewsSourcePermissionPreviewService service) {
        this.service = service;
    }

    @PostMapping("/preview")
    public NewsSourcePermissionPreview preview(@RequestBody NewsSourcePermissionPreviewRequest request) {
        try {
            return service.preview(request);
        } catch (IllegalArgumentException exception) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, exception.getMessage());
        }
    }
}
