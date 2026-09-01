package in.marketbrain.telegram;

import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

@RestController
@RequestMapping("/api/v1/telegram/test-alert")
@ConditionalOnProperty(
        prefix = "marketbrain.telegram",
        name = {"enabled", "test-alerts-enabled"},
        havingValue = "true")
class TelegramTestAlertController {

    private final TelegramTestAlertService service;

    TelegramTestAlertController(TelegramTestAlertService service) {
        this.service = service;
    }

    @PostMapping
    Map<String, String> send(@RequestParam TelegramTestAlertService.AlertType type) {
        String messageId = service.send(type);
        return Map.of("status", "SENT", "type", type.name(), "telegramMessageId", messageId);
    }
}
