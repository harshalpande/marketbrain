package in.marketbrain.notification;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/v1/notifications")
class NotificationStatusController {

    private final List<SystemNotificationGateway> gateways;
    private final boolean testEnabled;

    NotificationStatusController(
            List<SystemNotificationGateway> gateways,
            @Value("${marketbrain.notifications.test-enabled:false}") boolean testEnabled
    ) {
        this.gateways = gateways.stream()
                .sorted(Comparator.comparing(SystemNotificationGateway::channel))
                .toList();
        this.testEnabled = testEnabled;
    }

    @GetMapping("/status")
    Map<String, Object> status() {
        List<String> channels = gateways.stream()
                .map(SystemNotificationGateway::channel)
                .toList();
        var status = new LinkedHashMap<String, Object>();
        status.put("configuredChannels", channels);
        status.put("dualDeliveryReady",
                channels.contains("TELEGRAM") && channels.contains("WHATSAPP"));
        status.put("messageParity", "EXACT_SHARED_TEXT");
        status.put("perChannelIdempotency", true);
        status.put("failureIsolation", true);
        status.put("testEnabled", testEnabled);
        status.put("whatsAppConversationWindowRequired", true);
        status.put("actionExecutionEnabled", false);
        return status;
    }
}
