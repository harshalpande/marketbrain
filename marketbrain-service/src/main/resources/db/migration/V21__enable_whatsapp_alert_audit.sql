ALTER TABLE alert_notification
    DROP CONSTRAINT ck_alert_notification_delivery_channel;

ALTER TABLE alert_notification
    ADD CONSTRAINT ck_alert_notification_delivery_channel
        CHECK (delivery_channel IN ('TELEGRAM', 'WHATSAPP'));

COMMENT ON COLUMN alert_notification.delivery_channel IS
    'Controlled delivery transport. WhatsApp remains sandbox-only until separately reviewed for production.';
