CREATE TABLE feature_snapshot_run (
    id UUID PRIMARY KEY,
    universe_snapshot_id UUID NOT NULL REFERENCES universe_snapshot(id),
    requested_as_of DATE NOT NULL,
    feature_set_version VARCHAR(40) NOT NULL,
    source_manifest_hash VARCHAR(64) NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'WRITING',
    reviewed_by VARCHAR(120) NOT NULL,
    instrument_count INTEGER NOT NULL,
    persisted_feature_count INTEGER NOT NULL,
    withheld_count INTEGER NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMPTZ,
    CONSTRAINT uk_feature_snapshot_scope UNIQUE (
        universe_snapshot_id, requested_as_of, feature_set_version
    ),
    CONSTRAINT ck_feature_snapshot_version CHECK (feature_set_version ~ '^[A-Z0-9_]{1,40}$'),
    CONSTRAINT ck_feature_snapshot_manifest CHECK (source_manifest_hash ~ '^[0-9a-f]{64}$'),
    CONSTRAINT ck_feature_snapshot_status CHECK (status IN ('WRITING', 'COMPLETED')),
    CONSTRAINT ck_feature_snapshot_reviewer CHECK (BTRIM(reviewed_by) <> ''),
    CONSTRAINT ck_feature_snapshot_counts CHECK (
        instrument_count > 0
        AND persisted_feature_count >= 0
        AND withheld_count >= 0
        AND persisted_feature_count + withheld_count = instrument_count
    ),
    CONSTRAINT ck_feature_snapshot_completion CHECK (
        (status = 'COMPLETED' AND completed_at IS NOT NULL)
        OR (status = 'WRITING' AND completed_at IS NULL)
    )
);

CREATE TABLE feature_snapshot_item (
    id BIGSERIAL PRIMARY KEY,
    run_id UUID NOT NULL REFERENCES feature_snapshot_run(id),
    instrument_id BIGINT NOT NULL REFERENCES instrument(id),
    symbol VARCHAR(64) NOT NULL,
    classification VARCHAR(32) NOT NULL,
    effective_as_of DATE,
    canonical_observation_count INTEGER NOT NULL,
    eligible_observation_count INTEGER NOT NULL,
    excluded_observation_count INTEGER NOT NULL,
    latest_source VARCHAR(64),
    latest_open NUMERIC(18,4),
    latest_high NUMERIC(18,4),
    latest_low NUMERIC(18,4),
    latest_close NUMERIC(18,4),
    latest_volume NUMERIC(24,4),
    previous_close NUMERIC(20,6),
    daily_return_percent NUMERIC(20,6),
    sma20 NUMERIC(20,6),
    sma50 NUMERIC(20,6),
    sma200 NUMERIC(20,6),
    ema12 NUMERIC(20,6),
    ema26 NUMERIC(20,6),
    rsi14 NUMERIC(20,6),
    atr14 NUMERIC(20,6),
    annualized_volatility20_percent NUMERIC(20,6),
    volume_ratio20 NUMERIC(20,6),
    range_position252_percent NUMERIC(20,6),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_feature_snapshot_instrument UNIQUE (run_id, instrument_id),
    CONSTRAINT uk_feature_snapshot_symbol UNIQUE (run_id, symbol),
    CONSTRAINT ck_feature_snapshot_classification CHECK (
        classification IN ('ELIGIBLE', 'STALE', 'INSUFFICIENT_HISTORY', 'NO_ELIGIBLE_DATA')
    ),
    CONSTRAINT ck_feature_snapshot_observation_counts CHECK (
        canonical_observation_count >= 0
        AND eligible_observation_count >= 0
        AND excluded_observation_count >= 0
        AND eligible_observation_count + excluded_observation_count = canonical_observation_count
    ),
    CONSTRAINT ck_feature_snapshot_effective_date CHECK (
        (classification = 'NO_ELIGIBLE_DATA' AND effective_as_of IS NULL)
        OR (classification <> 'NO_ELIGIBLE_DATA' AND effective_as_of IS NOT NULL)
    ),
    CONSTRAINT ck_feature_snapshot_complete_vector CHECK (
        (
            classification = 'ELIGIBLE'
            AND previous_close IS NOT NULL
            AND daily_return_percent IS NOT NULL
            AND sma20 IS NOT NULL AND sma50 IS NOT NULL AND sma200 IS NOT NULL
            AND ema12 IS NOT NULL AND ema26 IS NOT NULL
            AND rsi14 IS NOT NULL AND atr14 IS NOT NULL
            AND annualized_volatility20_percent IS NOT NULL
            AND volume_ratio20 IS NOT NULL
            AND range_position252_percent IS NOT NULL
        )
        OR
        (
            classification <> 'ELIGIBLE'
            AND previous_close IS NULL
            AND daily_return_percent IS NULL
            AND sma20 IS NULL AND sma50 IS NULL AND sma200 IS NULL
            AND ema12 IS NULL AND ema26 IS NULL
            AND rsi14 IS NULL AND atr14 IS NULL
            AND annualized_volatility20_percent IS NULL
            AND volume_ratio20 IS NULL
            AND range_position252_percent IS NULL
        )
    )
);

CREATE INDEX idx_feature_snapshot_run_as_of
    ON feature_snapshot_run (requested_as_of DESC, feature_set_version, status);

CREATE INDEX idx_feature_snapshot_item_instrument
    ON feature_snapshot_item (instrument_id, effective_as_of DESC)
    WHERE classification = 'ELIGIBLE';

CREATE INDEX idx_feature_snapshot_item_classification
    ON feature_snapshot_item (run_id, classification);

CREATE FUNCTION reject_feature_snapshot_item_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'feature_snapshot_item is immutable; create a new versioned snapshot instead';
END;
$$;

CREATE TRIGGER trg_feature_snapshot_item_immutable
BEFORE UPDATE OR DELETE ON feature_snapshot_item
FOR EACH ROW EXECUTE FUNCTION reject_feature_snapshot_item_mutation();

CREATE FUNCTION govern_feature_snapshot_run_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'feature_snapshot_run is immutable; create a new versioned snapshot instead';
    END IF;
    IF OLD.status = 'COMPLETED' THEN
        RAISE EXCEPTION 'completed feature_snapshot_run is immutable';
    END IF;
    IF NEW.id IS DISTINCT FROM OLD.id
        OR NEW.universe_snapshot_id IS DISTINCT FROM OLD.universe_snapshot_id
        OR NEW.requested_as_of IS DISTINCT FROM OLD.requested_as_of
        OR NEW.feature_set_version IS DISTINCT FROM OLD.feature_set_version
        OR NEW.source_manifest_hash IS DISTINCT FROM OLD.source_manifest_hash
        OR NEW.reviewed_by IS DISTINCT FROM OLD.reviewed_by
        OR NEW.instrument_count IS DISTINCT FROM OLD.instrument_count
        OR NEW.persisted_feature_count IS DISTINCT FROM OLD.persisted_feature_count
        OR NEW.withheld_count IS DISTINCT FROM OLD.withheld_count
        OR NEW.created_at IS DISTINCT FROM OLD.created_at
        OR NEW.status <> 'COMPLETED'
        OR NEW.completed_at IS NULL THEN
        RAISE EXCEPTION 'feature_snapshot_run only permits the governed WRITING to COMPLETED transition';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_feature_snapshot_run_immutable
BEFORE UPDATE OR DELETE ON feature_snapshot_run
FOR EACH ROW EXECUTE FUNCTION govern_feature_snapshot_run_mutation();

COMMENT ON TABLE feature_snapshot_run IS
    'Reviewed, versioned point-in-time feature snapshot bound to an immutable source manifest.';

COMMENT ON TABLE feature_snapshot_item IS
    'Immutable per-instrument feature vector or explicit withheld classification; never a partial vector.';
