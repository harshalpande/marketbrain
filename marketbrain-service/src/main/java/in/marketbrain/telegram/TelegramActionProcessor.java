package in.marketbrain.telegram;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.Optional;

@Service
class TelegramActionProcessor {

    private final JdbcClient jdbc;

    TelegramActionProcessor(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    @Transactional
    TelegramActionResult process(TelegramCallback callback, String rawToken) {
        String tokenHash = TelegramSecurity.sha256(rawToken);
        Optional<PendingAction> pending = jdbc.sql("""
                        SELECT aa.action::text AS action,
                               aa.expires_at,
                               aa.processed,
                               an.recipient_identity_hash
                        FROM alert_action aa
                        JOIN alert_notification an ON an.id = aa.alert_notification_id
                        WHERE aa.action_token_hash = :tokenHash
                        """)
                .param("tokenHash", tokenHash)
                .query((rs, rowNum) -> new PendingAction(
                        rs.getString("action"),
                        rs.getTimestamp("expires_at").toInstant(),
                        rs.getBoolean("processed"),
                        rs.getString("recipient_identity_hash")))
                .optional();

        if (pending.isEmpty()) {
            return new TelegramActionResult("This action is invalid.", true);
        }

        PendingAction action = pending.get();
        if (!TelegramSecurity.constantTimeEquals(
                action.recipientIdentityHash(),
                TelegramSecurity.identityHash(callback.userId(), callback.chatId()))) {
            return new TelegramActionResult("This action is not assigned to you.", true);
        }
        if (action.processed()) {
            return new TelegramActionResult("This one-time action was already handled.", true);
        }
        if (!action.expiresAt().isAfter(Instant.now())) {
            markProcessed(tokenHash, callback, "EXPIRED");
            return new TelegramActionResult("This action has expired.", true);
        }

        String result = switch (action.action()) {
            case "REJECT" -> "REJECTED";
            case "DETAILS" -> "DETAILS_SHOWN";
            case "APPROVE" -> "BLOCKED_PENDING_FRESH_QUOTE";
            default -> "UNSUPPORTED_ACTION";
        };

        if (!markProcessed(tokenHash, callback, result)) {
            return new TelegramActionResult("This one-time action was already handled.", true);
        }

        return switch (result) {
            case "REJECTED" -> new TelegramActionResult("PAPER action rejected. No trade was created.", false);
            case "DETAILS_SHOWN" -> new TelegramActionResult(
                    "Test alert only. No live quote or broker order is attached.", true);
            case "BLOCKED_PENDING_FRESH_QUOTE" -> new TelegramActionResult(
                    "Approval recorded, but safely blocked: fresh-price and risk revalidation are not connected yet. No PAPER fill or real order was created.",
                    true);
            default -> new TelegramActionResult("Unsupported action.", true);
        };
    }

    private boolean markProcessed(String tokenHash, TelegramCallback callback, String result) {
        return jdbc.sql("""
                        UPDATE alert_action
                        SET received_at = CURRENT_TIMESTAMP,
                            sender_identity_hash = :senderHash,
                            processed = TRUE,
                            processing_result = :result,
                            provider_callback_id = :callbackId
                        WHERE action_token_hash = :tokenHash
                          AND processed = FALSE
                        """)
                .param("senderHash", TelegramSecurity.identityHash(callback.userId(), callback.chatId()))
                .param("result", result)
                .param("callbackId", callback.callbackId())
                .param("tokenHash", tokenHash)
                .update() == 1;
    }

    private record PendingAction(
            String action,
            Instant expiresAt,
            boolean processed,
            String recipientIdentityHash
    ) {
    }
}
