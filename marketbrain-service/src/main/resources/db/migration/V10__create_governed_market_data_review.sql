CREATE TABLE corporate_action_event (
    id BIGSERIAL PRIMARY KEY,
    instrument_id BIGINT NOT NULL REFERENCES instrument(id),
    source_id BIGINT NOT NULL REFERENCES market_data_source(id),
    event_fingerprint VARCHAR(64) NOT NULL,
    provider_name VARCHAR(120) NOT NULL,
    action_type VARCHAR(32) NOT NULL,
    effective_on DATE NOT NULL,
    announced_on DATE,
    record_on DATE,
    amount NUMERIC(18,4),
    ratio VARCHAR(64),
    details TEXT NOT NULL,
    source_url VARCHAR(500) NOT NULL,
    received_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ck_corporate_action_type CHECK (
        action_type IN ('DIVIDEND', 'BONUS', 'SPLIT', 'RIGHTS', 'MERGER', 'DEMERGER', 'OTHER')
    ),
    CONSTRAINT ck_corporate_action_amount CHECK (amount IS NULL OR amount >= 0),
    CONSTRAINT ck_corporate_action_provider_name CHECK (BTRIM(provider_name) <> ''),
    CONSTRAINT ck_corporate_action_source_url CHECK (source_url LIKE 'https://%'),
    CONSTRAINT uk_corporate_action_event UNIQUE (source_id, instrument_id, event_fingerprint)
);

CREATE INDEX idx_corporate_action_instrument_date
    ON corporate_action_event (instrument_id, effective_on);

CREATE TABLE market_data_quality_resolution_event (
    id UUID PRIMARY KEY,
    job_id UUID NOT NULL REFERENCES historical_backfill_job(id) ON DELETE CASCADE,
    instrument_id BIGINT REFERENCES instrument(id),
    finding_type VARCHAR(40) NOT NULL,
    finding_date DATE NOT NULL,
    related_date DATE,
    event_action VARCHAR(12) NOT NULL,
    resolution_type VARCHAR(40),
    evidence_source VARCHAR(120) NOT NULL,
    evidence_url VARCHAR(500) NOT NULL,
    notes VARCHAR(1000) NOT NULL,
    reviewed_by VARCHAR(120) NOT NULL,
    exclusion_from DATE,
    exclusion_to DATE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ck_quality_resolution_finding_type CHECK (
        finding_type IN (
            'OFFICIAL_SPECIAL_SESSION', 'PEER_CONFIRMED_SESSION',
            'SUSPICIOUS_GAP', 'LARGE_MOVE',
            'LEADING_COVERAGE_GAP', 'TRAILING_COVERAGE_GAP'
        )
    ),
    CONSTRAINT ck_quality_resolution_event_action CHECK (event_action IN ('RESOLVE', 'REVOKE')),
    CONSTRAINT ck_quality_resolution_type CHECK (
        resolution_type IS NULL OR resolution_type IN (
            'VERIFIED_EXCHANGE_MOVE', 'CORPORATE_ACTION_TRANSITION', 'PROVIDER_ADJUSTMENT',
            'FEATURE_WINDOW_EXCLUDED', 'SECONDARY_SOURCE_BACKFILLED',
            'PROVIDER_OMISSION_CONFIRMED'
        )
    ),
    CONSTRAINT ck_quality_resolution_action_payload CHECK (
        (event_action = 'RESOLVE' AND resolution_type IS NOT NULL)
        OR (event_action = 'REVOKE' AND resolution_type IS NULL)
    ),
    CONSTRAINT ck_quality_resolution_scope CHECK (
        instrument_id IS NOT NULL OR finding_type = 'OFFICIAL_SPECIAL_SESSION'
    ),
    CONSTRAINT ck_quality_resolution_evidence_url CHECK (evidence_url LIKE 'https://%'),
    CONSTRAINT ck_quality_resolution_required_text CHECK (
        BTRIM(evidence_source) <> '' AND BTRIM(notes) <> '' AND BTRIM(reviewed_by) <> ''
    ),
    CONSTRAINT ck_quality_resolution_exclusion_dates CHECK (
        (exclusion_from IS NULL AND exclusion_to IS NULL)
        OR (exclusion_from IS NOT NULL AND exclusion_to IS NOT NULL AND exclusion_to >= exclusion_from)
    ),
    CONSTRAINT ck_quality_resolution_exclusion_required CHECK (
        resolution_type NOT IN (
            'CORPORATE_ACTION_TRANSITION', 'PROVIDER_ADJUSTMENT', 'FEATURE_WINDOW_EXCLUDED'
        )
        OR (exclusion_from IS NOT NULL AND exclusion_to IS NOT NULL)
    )
);

CREATE INDEX idx_quality_resolution_finding
    ON market_data_quality_resolution_event
        (job_id, finding_type, finding_date, instrument_id, related_date, created_at DESC);

CREATE FUNCTION reject_quality_resolution_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'market_data_quality_resolution_event is append-only; append a REVOKE event instead';
END;
$$;

CREATE TRIGGER trg_quality_resolution_append_only
BEFORE UPDATE OR DELETE ON market_data_quality_resolution_event
FOR EACH ROW EXECUTE FUNCTION reject_quality_resolution_mutation();

CREATE VIEW current_market_data_quality_resolution AS
WITH ranked AS (
    SELECT event.*,
           ROW_NUMBER() OVER (
               PARTITION BY job_id, finding_type, finding_date,
                            COALESCE(instrument_id, 0), COALESCE(related_date, DATE '0001-01-01')
               ORDER BY created_at DESC, id DESC
           ) AS event_rank
    FROM market_data_quality_resolution_event event
)
SELECT id, job_id, instrument_id, finding_type, finding_date, related_date,
       resolution_type, evidence_source, evidence_url, notes, reviewed_by,
       exclusion_from, exclusion_to, created_at,
       resolution_type IN (
           'VERIFIED_EXCHANGE_MOVE', 'CORPORATE_ACTION_TRANSITION', 'PROVIDER_ADJUSTMENT',
           'FEATURE_WINDOW_EXCLUDED', 'SECONDARY_SOURCE_BACKFILLED'
       ) AS allows_training
FROM ranked
WHERE event_rank = 1 AND event_action = 'RESOLVE';

CREATE VIEW market_data_feature_exclusion AS
SELECT resolution.job_id,
       job_instrument.instrument_id,
       resolution.finding_type,
       resolution.finding_date,
       resolution.exclusion_from,
       resolution.exclusion_to,
       resolution.resolution_type,
       resolution.evidence_url
FROM current_market_data_quality_resolution resolution
JOIN LATERAL (
    SELECT DISTINCT chunk.instrument_id
    FROM historical_backfill_chunk chunk
    WHERE chunk.job_id = resolution.job_id
      AND (resolution.instrument_id IS NULL OR chunk.instrument_id = resolution.instrument_id)
) job_instrument ON TRUE
WHERE resolution.allows_training = TRUE
  AND resolution.exclusion_from IS NOT NULL;

COMMENT ON TABLE corporate_action_event IS
    'Read-only provider corporate-action evidence. Raw market candles are never updated by this table.';

COMMENT ON TABLE market_data_quality_resolution_event IS
    'Append-only human review ledger. REVOKE supersedes a prior resolution without deleting audit history.';

COMMENT ON VIEW market_data_feature_exclusion IS
    'Mandatory exclusion windows for future feature and return generation; raw candles remain immutable.';
