CREATE TABLE daily_feature_snapshot_automation (
    id BIGSERIAL PRIMARY KEY,
    target_date DATE NOT NULL,
    daily_run_id UUID NOT NULL REFERENCES historical_backfill_job(id),
    feature_snapshot_run_id UUID REFERENCES feature_snapshot_run(id),
    status VARCHAR(24) NOT NULL DEFAULT 'PENDING',
    attempts INTEGER NOT NULL DEFAULT 0,
    feature_manifest_hash VARCHAR(64),
    eligible_count INTEGER,
    withheld_count INTEGER,
    last_error_code VARCHAR(160),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_daily_feature_snapshot_target UNIQUE (target_date),
    CONSTRAINT uk_daily_feature_snapshot_daily_run UNIQUE (daily_run_id),
    CONSTRAINT ck_daily_feature_snapshot_status CHECK (
        status IN ('PENDING', 'RUNNING', 'RETRY', 'COMPLETED', 'REVIEW_REQUIRED', 'FAILED')
    ),
    CONSTRAINT ck_daily_feature_snapshot_attempts CHECK (attempts >= 0),
    CONSTRAINT ck_daily_feature_snapshot_manifest CHECK (
        feature_manifest_hash IS NULL OR feature_manifest_hash ~ '^[0-9a-f]{64}$'
    ),
    CONSTRAINT ck_daily_feature_snapshot_counts CHECK (
        (eligible_count IS NULL AND withheld_count IS NULL)
        OR (eligible_count >= 0 AND withheld_count >= 0
            AND eligible_count + withheld_count = 500)
    ),
    CONSTRAINT ck_daily_feature_snapshot_completion CHECK (
        status <> 'COMPLETED'
        OR (
            feature_snapshot_run_id IS NOT NULL
            AND feature_manifest_hash IS NOT NULL
            AND eligible_count IS NOT NULL
            AND withheld_count IS NOT NULL
            AND completed_at IS NOT NULL
        )
    )
);

CREATE INDEX idx_daily_feature_snapshot_work
    ON daily_feature_snapshot_automation (status, updated_at, target_date)
    WHERE status IN ('PENDING', 'RUNNING', 'RETRY');

ALTER TABLE daily_enrichment_notification
    DROP CONSTRAINT ck_daily_enrichment_notice_kind;

ALTER TABLE daily_enrichment_notification
    ADD CONSTRAINT ck_daily_enrichment_notice_kind CHECK (
        notice_kind IN ('COMPLETION', 'WARNING', 'FEATURE_COMPLETION', 'FEATURE_WARNING')
    );

COMMENT ON TABLE daily_feature_snapshot_automation IS
    'Durable, idempotent post-collection ledger for quality-gated daily feature persistence.';
