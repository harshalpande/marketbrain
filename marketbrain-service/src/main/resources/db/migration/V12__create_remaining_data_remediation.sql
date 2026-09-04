INSERT INTO market_data_source (code, display_name, enabled, status)
VALUES ('NSE_BHAVCOPY', 'NSE Official Daily BhavCopy', TRUE, 'AVAILABLE')
ON CONFLICT (code) DO NOTHING;

CREATE TABLE remaining_data_remediation_plan (
    id UUID PRIMARY KEY,
    job_id UUID NOT NULL UNIQUE REFERENCES historical_backfill_job(id) ON DELETE CASCADE,
    plan_hash VARCHAR(64) NOT NULL,
    status VARCHAR(24) NOT NULL DEFAULT 'READY',
    reviewed_by VARCHAR(120) NOT NULL,
    item_count INTEGER NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ck_remaining_remediation_hash CHECK (plan_hash ~ '^[0-9a-f]{64}$'),
    CONSTRAINT ck_remaining_remediation_status CHECK (
        status IN ('READY', 'RUNNING', 'COMPLETED', 'PARTIAL_FAILED')
    ),
    CONSTRAINT ck_remaining_remediation_reviewer CHECK (BTRIM(reviewed_by) <> ''),
    CONSTRAINT ck_remaining_remediation_count CHECK (item_count > 0)
);

CREATE TABLE remaining_data_remediation_item (
    id BIGSERIAL PRIMARY KEY,
    plan_id UUID NOT NULL REFERENCES remaining_data_remediation_plan(id) ON DELETE CASCADE,
    instrument_id BIGINT NOT NULL REFERENCES instrument(id),
    symbol VARCHAR(64) NOT NULL,
    finding_type VARCHAR(40) NOT NULL,
    finding_date DATE NOT NULL,
    related_date DATE,
    analysis_status VARCHAR(64) NOT NULL,
    resolution_type VARCHAR(40) NOT NULL,
    exclusion_from DATE,
    exclusion_to DATE,
    official_symbol VARCHAR(64),
    match_basis VARCHAR(32),
    official_series VARCHAR(16),
    official_open NUMERIC(18,4),
    official_high NUMERIC(18,4),
    official_low NUMERIC(18,4),
    official_close NUMERIC(18,4),
    official_volume NUMERIC(24,4),
    evidence_source VARCHAR(120) NOT NULL,
    evidence_url VARCHAR(500) NOT NULL,
    detail VARCHAR(1000) NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'PENDING',
    attempts INTEGER NOT NULL DEFAULT 0,
    secondary_candle_ready BOOLEAN NOT NULL DEFAULT FALSE,
    resolution_event_id UUID REFERENCES market_data_quality_resolution_event(id),
    last_error_code VARCHAR(64),
    last_error_detail VARCHAR(1000),
    completed_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ck_remaining_remediation_finding_type CHECK (
        finding_type IN (
            'OFFICIAL_SPECIAL_SESSION', 'PEER_CONFIRMED_SESSION',
            'SUSPICIOUS_GAP', 'LARGE_MOVE',
            'LEADING_COVERAGE_GAP', 'TRAILING_COVERAGE_GAP'
        )
    ),
    CONSTRAINT ck_remaining_remediation_resolution_type CHECK (
        resolution_type IN (
            'VERIFIED_EXCHANGE_MOVE', 'CORPORATE_ACTION_TRANSITION', 'PROVIDER_ADJUSTMENT',
            'FEATURE_WINDOW_EXCLUDED', 'SECONDARY_SOURCE_BACKFILLED',
            'PROVIDER_OMISSION_CONFIRMED'
        )
    ),
    CONSTRAINT ck_remaining_remediation_item_status CHECK (
        status IN ('PENDING', 'COMPLETED', 'FAILED')
    ),
    CONSTRAINT ck_remaining_remediation_attempts CHECK (attempts >= 0),
    CONSTRAINT ck_remaining_remediation_evidence_url CHECK (evidence_url LIKE 'https://%'),
    CONSTRAINT ck_remaining_remediation_required_text CHECK (
        BTRIM(symbol) <> '' AND BTRIM(analysis_status) <> ''
        AND BTRIM(evidence_source) <> '' AND BTRIM(detail) <> ''
    ),
    CONSTRAINT ck_remaining_remediation_exclusion CHECK (
        (resolution_type IN ('CORPORATE_ACTION_TRANSITION', 'PROVIDER_ADJUSTMENT', 'FEATURE_WINDOW_EXCLUDED')
            AND exclusion_from IS NOT NULL AND exclusion_to IS NOT NULL
            AND exclusion_to >= exclusion_from)
        OR
        (resolution_type NOT IN (
            'CORPORATE_ACTION_TRANSITION', 'PROVIDER_ADJUSTMENT', 'FEATURE_WINDOW_EXCLUDED'
        )
            AND exclusion_from IS NULL AND exclusion_to IS NULL)
    ),
    CONSTRAINT ck_remaining_remediation_official_candle CHECK (
        resolution_type <> 'SECONDARY_SOURCE_BACKFILLED'
        OR (
            official_open IS NOT NULL AND official_high IS NOT NULL
            AND official_low IS NOT NULL AND official_close IS NOT NULL
            AND official_open > 0 AND official_high > 0
            AND official_low > 0 AND official_close > 0
            AND official_low <= official_open AND official_low <= official_close
            AND official_high >= official_open AND official_high >= official_close
            AND (official_volume IS NULL OR official_volume >= 0)
        )
    ),
    CONSTRAINT ck_remaining_remediation_completion CHECK (
        (status = 'COMPLETED' AND resolution_event_id IS NOT NULL AND completed_at IS NOT NULL)
        OR status <> 'COMPLETED'
    )
);

CREATE UNIQUE INDEX uk_remaining_remediation_finding
    ON remaining_data_remediation_item (
        plan_id, instrument_id, finding_type, finding_date,
        COALESCE(related_date, DATE '0001-01-01')
    );

CREATE INDEX idx_remaining_remediation_work
    ON remaining_data_remediation_item (plan_id, status, id);

COMMENT ON TABLE remaining_data_remediation_plan IS
    'Immutable reviewed Step 20 plan identity plus resumable Step 21 execution status.';

COMMENT ON TABLE remaining_data_remediation_item IS
    'Per-finding Step 21 checkpoints; each candle and resolution completes in one database transaction.';
