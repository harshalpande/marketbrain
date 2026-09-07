CREATE TABLE daily_enrichment_notification (
    id BIGSERIAL PRIMARY KEY,
    target_date DATE NOT NULL,
    run_id UUID REFERENCES historical_backfill_job(id) ON DELETE SET NULL,
    notice_kind VARCHAR(24) NOT NULL,
    delivery_status VARCHAR(16) NOT NULL DEFAULT 'PENDING',
    attempts INTEGER NOT NULL DEFAULT 0,
    last_error_code VARCHAR(64),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    sent_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ck_daily_enrichment_notice_kind CHECK (
        notice_kind IN ('COMPLETION', 'WARNING')
    ),
    CONSTRAINT ck_daily_enrichment_notice_status CHECK (
        delivery_status IN ('PENDING', 'SENDING', 'SENT', 'FAILED', 'SUPPRESSED')
    ),
    CONSTRAINT ck_daily_enrichment_notice_attempts CHECK (attempts >= 0),
    CONSTRAINT uk_daily_enrichment_notice UNIQUE (target_date, notice_kind)
);

CREATE INDEX idx_daily_enrichment_notice_delivery
    ON daily_enrichment_notification (delivery_status, updated_at)
    WHERE delivery_status NOT IN ('SENT', 'SUPPRESSED');

INSERT INTO daily_enrichment_notification
    (target_date, run_id, notice_kind, delivery_status, last_error_code)
SELECT requested_to, id,
       CASE WHEN status = 'COMPLETED' THEN 'COMPLETION' ELSE 'WARNING' END,
       'SUPPRESSED', 'PREDATES_NOTIFICATION_ACTIVATION'
FROM historical_backfill_job
WHERE job_type = 'DAILY' AND status IN ('COMPLETED', 'PARTIAL_FAILED')
ON CONFLICT (target_date, notice_kind) DO NOTHING;

COMMENT ON TABLE daily_enrichment_notification IS
    'Idempotency ledger for action-free Telegram completion and warning notices emitted by daily enrichment.';
