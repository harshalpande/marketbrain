package in.marketbrain.notification;

import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.UUID;

@RestController
@RequestMapping("/api/v1/notifications/test-note")
@ConditionalOnProperty(
        prefix = "marketbrain.notifications",
        name = "test-enabled",
        havingValue = "true")
class DualNotificationTestController {

    private final DualNotificationTestService service;

    DualNotificationTestController(DualNotificationTestService service) {
        this.service = service;
    }

    @PostMapping
    DualNotificationTestResult send(@RequestParam UUID testId) {
        return service.send(testId);
    }
}
