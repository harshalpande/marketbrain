package in.marketbrain.whatsapp;

import in.marketbrain.configuration.WhatsAppProperties;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.io.IOException;

@RestController
@RequestMapping("/api/v1/whatsapp/webhook")
@ConditionalOnProperty(prefix = "marketbrain.whatsapp", name = "enabled", havingValue = "true")
class WhatsAppWebhookController {

    private static final Logger LOGGER = LoggerFactory.getLogger(WhatsAppWebhookController.class);
    private static final int MAXIMUM_PAYLOAD_BYTES = 1_048_576;

    private final WhatsAppProperties properties;
    private final WhatsAppWebhookService service;

    WhatsAppWebhookController(WhatsAppProperties properties, WhatsAppWebhookService service) {
        this.properties = properties;
        this.service = service;
    }

    @GetMapping(produces = MediaType.TEXT_PLAIN_VALUE)
    ResponseEntity<String> verify(
            @RequestParam(name = "hub.mode", required = false) String mode,
            @RequestParam(name = "hub.verify_token", required = false) String verifyToken,
            @RequestParam(name = "hub.challenge", required = false) String challenge
    ) {
        if (!properties.isWebhookConfigured()) {
            return ResponseEntity.status(503).body("WEBHOOK_NOT_CONFIGURED");
        }
        if (!"subscribe".equals(mode)
                || !WhatsAppSecurity.constantTimeEquals(properties.verifyToken(), verifyToken)
                || challenge == null) {
            return ResponseEntity.status(403).body("VERIFICATION_REJECTED");
        }
        return ResponseEntity.ok(challenge);
    }

    @PostMapping(consumes = MediaType.APPLICATION_JSON_VALUE, produces = MediaType.TEXT_PLAIN_VALUE)
    ResponseEntity<String> receive(
            @RequestBody byte[] payload,
            @RequestHeader(name = "X-Hub-Signature-256", required = false) String signature
    ) {
        if (!properties.isWebhookConfigured()) {
            return ResponseEntity.status(503).body("WEBHOOK_NOT_CONFIGURED");
        }
        if (payload.length > MAXIMUM_PAYLOAD_BYTES) {
            return ResponseEntity.status(413).body("PAYLOAD_TOO_LARGE");
        }
        if (!WhatsAppSecurity.validSignature(payload, signature, properties.appSecret())) {
            return ResponseEntity.status(401).body("INVALID_SIGNATURE");
        }
        try {
            WhatsAppWebhookResult result = service.receive(payload);
            LOGGER.info(
                    "Signed WhatsApp webhook acknowledged: accepted={}, ignored={}, duplicates={}",
                    result.accepted(), result.ignored(), result.duplicates());
            return ResponseEntity.ok("EVENT_RECEIVED");
        } catch (IOException exception) {
            return ResponseEntity.badRequest().body("INVALID_JSON");
        }
    }
}
