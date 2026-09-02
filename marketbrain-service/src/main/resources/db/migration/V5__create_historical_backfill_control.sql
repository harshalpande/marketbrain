CREATE TABLE universe_snapshot (
    id UUID PRIMARY KEY,
    universe_code VARCHAR(32) NOT NULL,
    observed_on DATE NOT NULL,
    source_name VARCHAR(100) NOT NULL,
    source_url VARCHAR(500) NOT NULL,
    source_sha256 VARCHAR(64) NOT NULL,
    received_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    source_member_count INTEGER NOT NULL,
    matched_member_count INTEGER NOT NULL,
    CONSTRAINT ck_universe_snapshot_counts CHECK (
        source_member_count > 0
        AND matched_member_count >= 0
        AND matched_member_count <= source_member_count
    ),
    CONSTRAINT uk_universe_snapshot_version UNIQUE (universe_code, observed_on, source_sha256)
);

CREATE TABLE universe_snapshot_member (
    snapshot_id UUID NOT NULL REFERENCES universe_snapshot(id) ON DELETE CASCADE,
    source_symbol VARCHAR(64) NOT NULL,
    source_isin VARCHAR(16) NOT NULL,
    source_company_name VARCHAR(255) NOT NULL,
    source_industry VARCHAR(255),
    instrument_id BIGINT REFERENCES instrument(id),
    provider_instrument_key VARCHAR(160),
    match_status VARCHAR(32) NOT NULL,
    PRIMARY KEY (snapshot_id, source_isin),
    CONSTRAINT ck_universe_snapshot_match CHECK (
        (match_status = 'MATCHED' AND instrument_id IS NOT NULL AND provider_instrument_key IS NOT NULL)
        OR (match_status = 'UNMATCHED' AND instrument_id IS NULL AND provider_instrument_key IS NULL)
    )
);

CREATE INDEX idx_universe_snapshot_latest
    ON universe_snapshot (universe_code, observed_on DESC, received_at DESC);
CREATE INDEX idx_universe_snapshot_member_instrument
    ON universe_snapshot_member (instrument_id) WHERE instrument_id IS NOT NULL;

CREATE TABLE historical_backfill_job (
    id UUID PRIMARY KEY,
    universe_snapshot_id UUID NOT NULL REFERENCES universe_snapshot(id),
    provider_code VARCHAR(64) NOT NULL,
    interval_code VARCHAR(16) NOT NULL,
    requested_from DATE NOT NULL,
    requested_to DATE NOT NULL,
    requested_instrument_limit INTEGER NOT NULL,
    status VARCHAR(24) NOT NULL DEFAULT 'CREATED',
    connectivity_failure_count INTEGER NOT NULL DEFAULT 0,
    connectivity_retry_at TIMESTAMPTZ,
    connectivity_wait_started_at TIMESTAMPTZ,
    connectivity_notice_sent_at TIMESTAMPTZ,
    last_connectivity_error_code VARCHAR(64),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ck_historical_backfill_dates CHECK (requested_to >= requested_from),
    CONSTRAINT ck_historical_backfill_limit CHECK (requested_instrument_limit BETWEEN 1 AND 500),
    CONSTRAINT ck_historical_backfill_connectivity_failures CHECK (connectivity_failure_count >= 0),
    CONSTRAINT ck_historical_backfill_status CHECK (
        status IN ('CREATED', 'RUNNING', 'WAITING_FOR_CONNECTIVITY', 'PAUSED', 'COMPLETED', 'PARTIAL_FAILED')
    )
);

CREATE INDEX idx_historical_backfill_connectivity_wait
    ON historical_backfill_job (connectivity_retry_at)
    WHERE status = 'WAITING_FOR_CONNECTIVITY';

CREATE TABLE historical_backfill_chunk (
    id BIGSERIAL PRIMARY KEY,
    job_id UUID NOT NULL REFERENCES historical_backfill_job(id) ON DELETE CASCADE,
    instrument_id BIGINT NOT NULL REFERENCES instrument(id),
    provider_instrument_key VARCHAR(160) NOT NULL,
    source_symbol VARCHAR(64) NOT NULL,
    from_date DATE NOT NULL,
    to_date DATE NOT NULL,
    status VARCHAR(24) NOT NULL DEFAULT 'PENDING',
    attempts INTEGER NOT NULL DEFAULT 0,
    accepted_rows INTEGER NOT NULL DEFAULT 0,
    rejected_rows INTEGER NOT NULL DEFAULT 0,
    last_error_code VARCHAR(64),
    next_attempt_at TIMESTAMPTZ,
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ck_historical_backfill_chunk_dates CHECK (to_date >= from_date),
    CONSTRAINT ck_historical_backfill_chunk_attempts CHECK (attempts >= 0 AND attempts <= 3),
    CONSTRAINT ck_historical_backfill_chunk_counts CHECK (accepted_rows >= 0 AND rejected_rows >= 0),
    CONSTRAINT ck_historical_backfill_chunk_status CHECK (
        status IN ('PENDING', 'RUNNING', 'RETRY', 'COMPLETED', 'FAILED')
    ),
    CONSTRAINT uk_historical_backfill_chunk UNIQUE (job_id, instrument_id, from_date, to_date)
);

CREATE INDEX idx_historical_backfill_chunk_work
    ON historical_backfill_chunk (status, next_attempt_at, id);
CREATE INDEX idx_historical_backfill_chunk_job_status
    ON historical_backfill_chunk (job_id, status);

CREATE TABLE market_data_quality_issue (
    id BIGSERIAL PRIMARY KEY,
    job_id UUID REFERENCES historical_backfill_job(id) ON DELETE CASCADE,
    chunk_id BIGINT REFERENCES historical_backfill_chunk(id) ON DELETE CASCADE,
    instrument_id BIGINT REFERENCES instrument(id),
    issue_code VARCHAR(64) NOT NULL,
    severity VARCHAR(16) NOT NULL,
    affected_rows INTEGER NOT NULL DEFAULT 0,
    detected_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    resolved_at TIMESTAMPTZ,
    CONSTRAINT ck_market_data_quality_severity CHECK (severity IN ('INFO', 'WARNING', 'BLOCKING')),
    CONSTRAINT ck_market_data_quality_rows CHECK (affected_rows >= 0)
);

CREATE INDEX idx_market_data_quality_open
    ON market_data_quality_issue (severity, detected_at DESC) WHERE resolved_at IS NULL;
