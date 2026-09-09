CREATE TABLE whatsapp_webhook_event (
    id BIGSERIAL PRIMARY KEY,
    event_key_hash CHAR(64) NOT NULL UNIQUE,
    event_kind VARCHAR(32) NOT NULL,
    disposition VARCHAR(16) NOT NULL,
    waba_id_hash CHAR(64) NOT NULL,
    phone_number_id_hash CHAR(64),
    participant_wa_id_hash CHAR(64),
    provider_message_id_hash CHAR(64),
    action_payload_hash CHAR(64),
    payload_hash CHAR(64) NOT NULL,
    received_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ck_whatsapp_webhook_event_kind CHECK (
        event_kind IN ('MESSAGE', 'BUTTON_REPLY', 'MESSAGE_STATUS', 'UNKNOWN')
    ),
    CONSTRAINT ck_whatsapp_webhook_disposition CHECK (
        disposition IN ('ACCEPTED', 'IGNORED')
    )
);

CREATE INDEX idx_whatsapp_webhook_event_received
    ON whatsapp_webhook_event (received_at DESC);

CREATE OR REPLACE FUNCTION reject_whatsapp_webhook_event_mutation()
RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'WhatsApp webhook events are immutable';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_reject_whatsapp_webhook_event_mutation
BEFORE UPDATE OR DELETE ON whatsapp_webhook_event
FOR EACH ROW EXECUTE FUNCTION reject_whatsapp_webhook_event_mutation();

COMMENT ON TABLE whatsapp_webhook_event IS
    'Content-free, keyed-hash idempotency and audit ledger for signed Meta WhatsApp webhook deliveries.';
