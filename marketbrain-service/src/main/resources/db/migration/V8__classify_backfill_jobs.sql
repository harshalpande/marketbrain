ALTER TABLE historical_backfill_job
    ADD COLUMN job_type VARCHAR(24) NOT NULL DEFAULT 'PILOT',
    ADD COLUMN batch_number INTEGER;

ALTER TABLE historical_backfill_job
    ADD CONSTRAINT ck_historical_backfill_job_type CHECK (
        (job_type = 'PILOT' AND batch_number IS NULL)
        OR (job_type = 'EXPANSION' AND batch_number IS NOT NULL AND batch_number > 0)
    );

CREATE UNIQUE INDEX uk_historical_backfill_expansion_batch
    ON historical_backfill_job (universe_snapshot_id, batch_number)
    WHERE job_type = 'EXPANSION';

CREATE UNIQUE INDEX uk_historical_backfill_single_active_job
    ON historical_backfill_job ((TRUE))
    WHERE status IN ('CREATED', 'RUNNING', 'WAITING_FOR_CONNECTIVITY', 'PAUSED');

COMMENT ON COLUMN historical_backfill_job.job_type IS
    'Separates the controlled ten-stock pilot from manually created NIFTY 500 expansion batches.';

COMMENT ON COLUMN historical_backfill_job.batch_number IS
    'One-based expansion batch number within a universe snapshot; null for pilot jobs.';
