ALTER TYPE whatsapp_alert_type RENAME TO alert_notification_type;
ALTER TYPE whatsapp_action_type RENAME TO alert_action_type;

ALTER TABLE whatsapp_alert RENAME TO alert_notification;
ALTER TABLE whatsapp_action RENAME TO alert_action;

ALTER TABLE alert_notification
    RENAME COLUMN recipient_phone_hash TO recipient_identity_hash;

ALTER TABLE alert_action
    RENAME COLUMN whatsapp_alert_id TO alert_notification_id;

ALTER TABLE alert_action
    RENAME COLUMN sender_phone_hash TO sender_identity_hash;

ALTER TABLE alert_notification
    ADD COLUMN delivery_channel VARCHAR(32) NOT NULL DEFAULT 'TELEGRAM';

ALTER TABLE alert_notification
    ADD CONSTRAINT ck_alert_notification_delivery_channel
        CHECK (delivery_channel IN ('TELEGRAM'));
