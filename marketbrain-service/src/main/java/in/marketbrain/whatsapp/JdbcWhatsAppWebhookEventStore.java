package in.marketbrain.whatsapp;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

@Repository
class JdbcWhatsAppWebhookEventStore implements WhatsAppWebhookEventStore {

    private final JdbcClient jdbc;

    JdbcWhatsAppWebhookEventStore(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    @Override
    public boolean save(WhatsAppWebhookEvent event) {
        return jdbc.sql("""
                        INSERT INTO whatsapp_webhook_event
                            (event_key_hash, event_kind, disposition, waba_id_hash,
                             phone_number_id_hash, participant_wa_id_hash,
                             provider_message_id_hash, action_payload_hash, payload_hash)
                        VALUES
                            (:eventKeyHash, :eventKind, :disposition, :wabaIdHash,
                             :phoneNumberIdHash, :participantWaIdHash,
                             :providerMessageIdHash, :actionPayloadHash, :payloadHash)
                        ON CONFLICT (event_key_hash) DO NOTHING
                        """)
                .param("eventKeyHash", event.eventKeyHash())
                .param("eventKind", event.eventKind())
                .param("disposition", event.disposition())
                .param("wabaIdHash", event.wabaIdHash())
                .param("phoneNumberIdHash", event.phoneNumberIdHash())
                .param("participantWaIdHash", event.participantWaIdHash())
                .param("providerMessageIdHash", event.providerMessageIdHash())
                .param("actionPayloadHash", event.actionPayloadHash())
                .param("payloadHash", event.payloadHash())
                .update() == 1;
    }
}
