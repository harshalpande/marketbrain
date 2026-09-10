package in.marketbrain.whatsapp;

import in.marketbrain.configuration.WhatsAppProperties;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

@Service
class WhatsAppActionProcessor {

    private final JdbcClient jdbc;
    private final WhatsAppProperties properties;

    WhatsAppActionProcessor(JdbcClient jdbc, WhatsAppProperties properties) {
        this.jdbc = jdbc;
        this.properties = properties;
    }

    @Transactional
    WhatsAppActionResult process(String participantWaId, String providerMessageId, String rawToken) {
        String tokenHash = WhatsAppSecurity.sha256(rawToken);
        Optional<PendingAction> pending = jdbc.sql("""
                        SELECT aa.id, aa.action::text AS action, aa.expires_at,
                               aa.processed, an.recipient_identity_hash
                        FROM alert_action aa
                        JOIN alert_notification an ON an.id = aa.alert_notification_id
                        WHERE aa.action_token_hash = :tokenHash
                          AND an.delivery_channel = 'WHATSAPP'
                        """)
                .param("tokenHash", tokenHash)
                .query((rs, rowNum) -> new PendingAction(
                        rs.getObject("id", UUID.class),
                        rs.getString("action"),
                        rs.getTimestamp("expires_at").toInstant(),
                        rs.getBoolean("processed"),
                        rs.getString("recipient_identity_hash")))
                .optional();

        if (pending.isEmpty()) {
            return new WhatsAppActionResult("UNKNOWN", "INVALID", "", false);
        }

        PendingAction action = pending.get();
        if (!WhatsAppSecurity.constantTimeEquals(
                action.recipientIdentityHash(), recipientHash(participantWaId))) {
            return new WhatsAppActionResult(action.action(), "UNAUTHORIZED", "", false);
        }
        if (action.processed()) {
            return new WhatsAppActionResult(action.action(), "ALREADY_HANDLED", "", false);
        }
        if (!action.expiresAt().isAfter(Instant.now())) {
            markProcessed(action.id(), participantWaId, providerMessageId, "EXPIRED");
            return new WhatsAppActionResult(
                    action.action(), "EXPIRED",
                    "This MarketBrain test action has expired. No trade was created.", true);
        }

        String result = switch (action.action()) {
            case "REJECT" -> "REJECTED";
            case "DETAILS" -> "DETAILS_SHOWN";
            case "APPROVE" -> "BLOCKED_PENDING_FRESH_QUOTE";
            default -> "UNSUPPORTED_ACTION";
        };
        if (!markProcessed(action.id(), participantWaId, providerMessageId, result)) {
            return new WhatsAppActionResult(action.action(), "ALREADY_HANDLED", "", false);
        }

        return switch (result) {
            case "REJECTED" -> new WhatsAppActionResult(
                    action.action(), result,
                    "PAPER test action rejected. No trade was created.", true);
            case "DETAILS_SHOWN" -> new WhatsAppActionResult(
                    action.action(), result,
                    "MarketBrain sandbox test only. No live quote, signal, or broker order is attached.", true);
            case "BLOCKED_PENDING_FRESH_QUOTE" -> new WhatsAppActionResult(
                    action.action(), result,
                    "Approval recorded but safely blocked. Fresh-price and risk revalidation are not connected. No PAPER fill or real order was created.",
                    true);
            default -> new WhatsAppActionResult(action.action(), result, "", false);
        };
    }

    private boolean markProcessed(
            UUID actionId,
            String participantWaId,
            String providerMessageId,
            String result
    ) {
        return jdbc.sql("""
                        UPDATE alert_action
                        SET received_at = CURRENT_TIMESTAMP,
                            sender_identity_hash = :senderHash,
                            processed = TRUE,
                            processing_result = :result,
                            provider_callback_id = :callbackHash
                        WHERE id = :id
                          AND processed = FALSE
                        """)
                .param("senderHash", recipientHash(participantWaId))
                .param("result", result)
                .param("callbackHash", recipientHash(providerMessageId))
                .param("id", actionId)
                .update() == 1;
    }

    private String recipientHash(String value) {
        return WhatsAppSecurity.hmacSha256(value, properties.appSecret());
    }

    private record PendingAction(
            UUID id,
            String action,
            Instant expiresAt,
            boolean processed,
            String recipientIdentityHash
    ) {
    }
}
