CREATE TABLE prototype_swing_training_dataset_run (
    id UUID PRIMARY KEY,
    dataset_contract_version VARCHAR(48) NOT NULL,
    source_universe_code VARCHAR(64) NOT NULL,
    as_of DATE NOT NULL,
    label_through DATE NOT NULL,
    universe_snapshot_id UUID NOT NULL REFERENCES universe_snapshot(id),
    feature_set_version VARCHAR(40) NOT NULL,
    input_feature_manifest_hash VARCHAR(64) NOT NULL,
    dataset_manifest_hash VARCHAR(64) NOT NULL,
    assumed_round_trip_cost_bps INTEGER NOT NULL,
    benchmark_definition VARCHAR(80) NOT NULL,
    historical_membership_status VARCHAR(80) NOT NULL,
    status VARCHAR(24) NOT NULL,
    reviewed_by VARCHAR(120) NOT NULL,
    instrument_count INTEGER NOT NULL,
    feature_eligible_count INTEGER NOT NULL,
    fully_labeled_count INTEGER NOT NULL,
    right_censored_count INTEGER NOT NULL,
    insufficient_history_count INTEGER NOT NULL,
    stale_count INTEGER NOT NULL,
    no_eligible_data_count INTEGER NOT NULL,
    persisted_item_count INTEGER NOT NULL,
    persisted_label_count INTEGER NOT NULL,
    survivorship_risk_present BOOLEAN NOT NULL,
    prototype_training_eligible BOOLEAN NOT NULL,
    benchmark_training_eligible BOOLEAN NOT NULL,
    point_in_time_safe BOOLEAN NOT NULL,
    future_labels_separated BOOLEAN NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_prototype_swing_dataset_scope UNIQUE (
        source_universe_code, as_of, label_through, assumed_round_trip_cost_bps,
        input_feature_manifest_hash
    ),
    CONSTRAINT uk_prototype_swing_dataset_manifest UNIQUE (dataset_manifest_hash),
    CONSTRAINT ck_prototype_swing_dataset_version CHECK (
        dataset_contract_version = 'PROTOTYPE_SWING_TRAINING_DATASET_V1'
    ),
    CONSTRAINT ck_prototype_swing_dataset_code CHECK (
        source_universe_code = 'CURRENT_SNAPSHOT_PROTOTYPE'
    ),
    CONSTRAINT ck_prototype_swing_dataset_dates CHECK (label_through > as_of),
    CONSTRAINT ck_prototype_swing_dataset_hashes CHECK (
        input_feature_manifest_hash ~ '^[0-9a-f]{64}$'
        AND dataset_manifest_hash ~ '^[0-9a-f]{64}$'
    ),
    CONSTRAINT ck_prototype_swing_dataset_status CHECK (status = 'COMPLETED'),
    CONSTRAINT ck_prototype_swing_dataset_reviewer CHECK (BTRIM(reviewed_by) <> ''),
    CONSTRAINT ck_prototype_swing_dataset_counts CHECK (
        instrument_count > 0
        AND feature_eligible_count >= 0
        AND fully_labeled_count >= 0
        AND right_censored_count >= 0
        AND insufficient_history_count >= 0
        AND stale_count >= 0
        AND no_eligible_data_count >= 0
        AND persisted_item_count = instrument_count
        AND fully_labeled_count + right_censored_count = feature_eligible_count
        AND feature_eligible_count + insufficient_history_count + stale_count
            + no_eligible_data_count = instrument_count
        AND persisted_label_count >= fully_labeled_count * 3
    ),
    CONSTRAINT ck_prototype_swing_dataset_governance CHECK (
        survivorship_risk_present = TRUE
        AND prototype_training_eligible = TRUE
        AND benchmark_training_eligible = FALSE
        AND point_in_time_safe = TRUE
        AND future_labels_separated = TRUE
    )
);

CREATE TABLE prototype_swing_training_dataset_item (
    id BIGSERIAL PRIMARY KEY,
    run_id UUID NOT NULL REFERENCES prototype_swing_training_dataset_run(id),
    instrument_id BIGINT NOT NULL REFERENCES instrument(id),
    symbol VARCHAR(64) NOT NULL,
    classification VARCHAR(32) NOT NULL,
    effective_as_of DATE,
    missing_horizons VARCHAR(32) NOT NULL,
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
    detail VARCHAR(500) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_prototype_swing_dataset_item UNIQUE (run_id, instrument_id),
    CONSTRAINT uk_prototype_swing_dataset_item_symbol UNIQUE (run_id, symbol),
    CONSTRAINT ck_prototype_swing_dataset_item_classification CHECK (
        classification IN ('LABELED', 'RIGHT_CENSORED', 'INSUFFICIENT_HISTORY', 'STALE', 'NO_ELIGIBLE_DATA')
    ),
    CONSTRAINT ck_prototype_swing_dataset_item_features CHECK (
        (
            classification IN ('LABELED', 'RIGHT_CENSORED')
            AND effective_as_of IS NOT NULL
            AND latest_close IS NOT NULL
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
            classification NOT IN ('LABELED', 'RIGHT_CENSORED')
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

CREATE TABLE prototype_swing_training_dataset_label (
    id BIGSERIAL PRIMARY KEY,
    item_id BIGINT NOT NULL REFERENCES prototype_swing_training_dataset_item(id),
    horizon_sessions INTEGER NOT NULL,
    outcome_date DATE NOT NULL,
    gross_return_percent NUMERIC(20,6) NOT NULL,
    assumed_round_trip_cost_percent NUMERIC(20,6) NOT NULL,
    net_return_percent NUMERIC(20,6) NOT NULL,
    maximum_favorable_excursion_percent NUMERIC(20,6) NOT NULL,
    maximum_adverse_excursion_percent NUMERIC(20,6) NOT NULL,
    maximum_drawdown_percent NUMERIC(20,6) NOT NULL,
    benchmark_proxy_return_percent NUMERIC(20,6),
    benchmark_excess_return_percent NUMERIC(20,6),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_prototype_swing_dataset_label UNIQUE (item_id, horizon_sessions),
    CONSTRAINT ck_prototype_swing_dataset_label_horizon CHECK (horizon_sessions IN (5, 20, 60))
);

CREATE INDEX idx_prototype_swing_dataset_run_as_of
    ON prototype_swing_training_dataset_run (as_of DESC, label_through DESC);

CREATE INDEX idx_prototype_swing_dataset_item_symbol
    ON prototype_swing_training_dataset_item (symbol, run_id);

CREATE FUNCTION reject_prototype_swing_training_dataset_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'prototype swing training datasets are immutable; create a new manifest-bound run instead';
END;
$$;

CREATE TRIGGER trg_prototype_swing_dataset_run_immutable
BEFORE UPDATE OR DELETE ON prototype_swing_training_dataset_run
FOR EACH ROW EXECUTE FUNCTION reject_prototype_swing_training_dataset_mutation();

CREATE TRIGGER trg_prototype_swing_dataset_item_immutable
BEFORE UPDATE OR DELETE ON prototype_swing_training_dataset_item
FOR EACH ROW EXECUTE FUNCTION reject_prototype_swing_training_dataset_mutation();

CREATE TRIGGER trg_prototype_swing_dataset_label_immutable
BEFORE UPDATE OR DELETE ON prototype_swing_training_dataset_label
FOR EACH ROW EXECUTE FUNCTION reject_prototype_swing_training_dataset_mutation();

COMMENT ON TABLE prototype_swing_training_dataset_run IS
    'Immutable prototype swing-training dataset over current snapshot membership. Not official historical NIFTY 500 benchmark training.';

COMMENT ON TABLE prototype_swing_training_dataset_item IS
    'Immutable feature rows used by a prototype swing-training dataset run.';

COMMENT ON TABLE prototype_swing_training_dataset_label IS
    'Immutable 5/20/60-session future outcome labels for prototype swing-training dataset items.';
