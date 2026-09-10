package in.marketbrain.whatsapp;

import in.marketbrain.configuration.MarketBrainProperties;
import in.marketbrain.configuration.WhatsAppProperties;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.LinkedHashMap;
import java.util.Map;

@RestController
@RequestMapping("/api/v1/whatsapp")
class WhatsAppStatusController {

    private final MarketBrainProperties marketBrainProperties;
    private final WhatsAppProperties whatsAppProperties;

    WhatsAppStatusController(
            MarketBrainProperties marketBrainProperties,
            WhatsAppProperties whatsAppProperties
    ) {
        this.marketBrainProperties = marketBrainProperties;
        this.whatsAppProperties = whatsAppProperties;
    }

    @GetMapping("/status")
    Map<String, Object> status() {
        var status = new LinkedHashMap<String, Object>();
        status.put("enabled", whatsAppProperties.enabled());
        status.put("sandboxMode", whatsAppProperties.sandboxMode());
        status.put("testAlertsEnabled", whatsAppProperties.testAlertsEnabled());
        status.put("notificationsEnabled", whatsAppProperties.notificationsEnabled());
        status.put("webhookConfigured", whatsAppProperties.isWebhookConfigured());
        status.put("outboundConfigured", whatsAppProperties.isOutboundConfigured());
        status.put("callbackPath", "/api/v1/whatsapp/webhook");
        status.put("signatureValidation", "HMAC_SHA256");
        status.put("recipientAllowListEnforced", true);
        status.put("payloadContentStored", false);
        status.put("actionExecutionEnabled", false);
        status.put("executionMode", marketBrainProperties.executionMode());
        return status;
    }
}
