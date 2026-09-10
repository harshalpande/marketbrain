package in.marketbrain.news;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.UUID;

@RestController
@RequestMapping("/api/v1/news/ingestion")
class NewsIngestionController {

    private final NewsIngestionStatusService statusService;
    private final NewsIngestionRunService runService;

    NewsIngestionController(NewsIngestionStatusService statusService, NewsIngestionRunService runService) {
        this.statusService = statusService;
        this.runService = runService;
    }

    @GetMapping("/status")
    NewsIngestionStatus status() {
        return statusService.status();
    }

    @PostMapping("/run-once")
    NewsIngestionRunResult runOnce(@RequestParam(required = false) UUID runId) {
        return runService.runOnce(runId);
    }
}
