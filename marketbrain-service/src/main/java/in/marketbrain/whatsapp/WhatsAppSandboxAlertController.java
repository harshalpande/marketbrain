package in.marketbrain.whatsapp;

import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.UUID;

@RestController
@RequestMapping("/api/v1/whatsapp/test-alert")
@ConditionalOnProperty(
        prefix = "marketbrain.whatsapp",
        name = {"enabled", "test-alerts-enabled"},
        havingValue = "true")
class WhatsAppSandboxAlertController {

    private final WhatsAppSandboxAlertService service;

    WhatsAppSandboxAlertController(WhatsAppSandboxAlertService service) {
        this.service = service;
    }

    @PostMapping
    WhatsAppSandboxAlertStatus send() {
        return service.send();
    }

    @GetMapping("/{alertId}")
    WhatsAppSandboxAlertStatus status(@PathVariable UUID alertId) {
        return service.status(alertId);
    }
}
