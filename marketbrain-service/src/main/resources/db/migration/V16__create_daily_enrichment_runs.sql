ALTER TABLE historical_backfill_job
    DROP CONSTRAINT ck_historical_backfill_job_type;

ALTER TABLE historical_backfill_job
    ADD COLUMN selection_manifest_hash VARCHAR(64),
    ADD CONSTRAINT ck_historical_backfill_job_type CHECK (
        (job_type = 'PILOT' AND batch_number IS NULL)
        OR (job_type = 'EXPANSION' AND batch_number IS NOT NULL AND batch_number > 0)
        OR (job_type = 'DAILY' AND batch_number IS NULL)
    ),
    ADD CONSTRAINT ck_historical_backfill_manifest_hash CHECK (
        (job_type = 'DAILY' AND selection_manifest_hash IS NOT NULL
            AND selection_manifest_hash ~ '^[0-9a-f]{64}$')
        OR (job_type <> 'DAILY' AND selection_manifest_hash IS NULL)
    );

CREATE UNIQUE INDEX uk_historical_backfill_daily_target
    ON historical_backfill_job (universe_snapshot_id, requested_to)
    WHERE job_type = 'DAILY';

COMMENT ON COLUMN historical_backfill_job.job_type IS
    'Separates the controlled pilot, reviewed expansion batches, and incremental DAILY enrichment runs.';

COMMENT ON COLUMN historical_backfill_job.selection_manifest_hash IS
    'Deterministic reviewed selection manifest. Required by DAILY enrichment runs and null for legacy jobs.';
