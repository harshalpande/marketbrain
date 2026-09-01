package in.marketbrain.telegram;

import in.marketbrain.configuration.MarketBrainProperties;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.LinkedHashMap;
import java.util.Map;

@RestController
@RequestMapping("/api/v1/telegram")
class TelegramStatusController {

    private final MarketBrainProperties properties;
    private final TelegramStateStore stateStore;

    TelegramStatusController(MarketBrainProperties properties, TelegramStateStore stateStore) {
        this.properties = properties;
        this.stateStore = stateStore;
    }

    @GetMapping("/status")
    Map<String, Object> status() {
        var telegram = properties.telegram();
        var status = new LinkedHashMap<String, Object>();
        status.put("enabled", telegram.enabled());
        status.put("configured", telegram.isConfigured());
        status.put("paired", stateStore.activeBinding().isPresent());
        status.put("transport", "LONG_POLLING");
        status.put("privateChatOnly", true);
        status.put("executionMode", properties.executionMode());
        status.put("testAlertsEnabled", telegram.testAlertsEnabled());
        return status;
    }
}
