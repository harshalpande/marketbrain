ALTER TABLE alert_notification
    ADD COLUMN delivery_deduplication_key VARCHAR(160),
    ADD COLUMN updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP;

ALTER TABLE alert_notification
    ADD CONSTRAINT uk_alert_notification_channel_deduplication
        UNIQUE (delivery_channel, delivery_deduplication_key);

COMMENT ON COLUMN alert_notification.delivery_deduplication_key IS
    'Logical system-notification key used to prevent duplicate delivery independently per channel.';

COMMENT ON COLUMN alert_notification.updated_at IS
    'Last durable delivery-state transition; permits safe recovery of abandoned sends.';

COMMENT ON TABLE daily_enrichment_notification IS
    'Aggregate idempotency ledger for system notices delivered to every enabled notification channel.';
