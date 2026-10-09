-- Audit only. No existing automation, feature, notification or candle rows are changed on deployment.
CREATE TABLE reviewed_feature_reconciliation (
    id UUID PRIMARY KEY,
    target_date DATE NOT NULL UNIQUE,
    daily_run_id UUID NOT NULL REFERENCES historical_backfill_job(id),
    feature_snapshot_run_id UUID NOT NULL REFERENCES feature_snapshot_run(id),
    feature_manifest_hash VARCHAR(64) NOT NULL CHECK (feature_manifest_hash ~ '^[0-9a-f]{64}$'),
    evidence_sha256 VARCHAR(64) NOT NULL CHECK (evidence_sha256 ~ '^[0-9A-F]{64}$'),
    reviewed_by VARCHAR(120) NOT NULL CHECK (BTRIM(reviewed_by) <> ''),
    previous_status VARCHAR(24) NOT NULL,
    previous_error_code VARCHAR(160) NOT NULL,
    previous_attempts INTEGER NOT NULL CHECK (previous_attempts >= 0),
    previous_completed_at TIMESTAMPTZ,
    previous_updated_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE FUNCTION reject_feature_reconciliation_mutation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'reviewed_feature_reconciliation is append-only';
END;
$$;
CREATE TRIGGER trg_feature_reconciliation_append_only
BEFORE UPDATE OR DELETE ON reviewed_feature_reconciliation
FOR EACH ROW EXECUTE FUNCTION reject_feature_reconciliation_mutation();
