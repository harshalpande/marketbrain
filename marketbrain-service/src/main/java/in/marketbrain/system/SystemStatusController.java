package in.marketbrain.system;

import in.marketbrain.configuration.MarketBrainProperties;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.time.Instant;
import java.util.Map;

@RestController
@RequestMapping("/api/v1/system")
public class SystemStatusController {

    private final MarketBrainProperties properties;

    public SystemStatusController(MarketBrainProperties properties) {
        this.properties = properties;
    }

    @GetMapping("/status")
    public Map<String, Object> status() {
        return Map.of(
                "service", "marketbrain-service",
                "mode", properties.executionMode(),
                "paperStartingCash", properties.paper().startingCash(),
                "signalMaximumDataAgeSeconds", properties.signal().maximumDataAgeSeconds(),
                "targetAlertSubmissionSeconds", properties.signal().targetAlertSubmissionSeconds(),
                "timestamp", Instant.now()
        );
    }
}
