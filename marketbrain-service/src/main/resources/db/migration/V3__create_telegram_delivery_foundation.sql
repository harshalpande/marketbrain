CREATE TABLE telegram_binding (
    binding_key VARCHAR(32) PRIMARY KEY,
    telegram_user_id BIGINT NOT NULL UNIQUE,
    telegram_chat_id BIGINT NOT NULL UNIQUE,
    display_name VARCHAR(255),
    paired_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_interaction_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT ck_telegram_binding_key CHECK (binding_key = 'PRIMARY')
);

CREATE TABLE telegram_poll_cursor (
    cursor_key VARCHAR(32) PRIMARY KEY,
    next_update_offset BIGINT NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ck_telegram_cursor_key CHECK (cursor_key = 'PRIMARY'),
    CONSTRAINT ck_telegram_cursor_offset CHECK (next_update_offset >= 0)
);

INSERT INTO telegram_poll_cursor (cursor_key, next_update_offset)
VALUES ('PRIMARY', 0);

ALTER TABLE alert_action
    ADD COLUMN provider_callback_id VARCHAR(128) UNIQUE;
