ALTER TABLE market_candle
    ADD COLUMN provider_opened_at TIMESTAMPTZ;

UPDATE market_candle
SET provider_opened_at = opened_at
WHERE provider_opened_at IS NULL;

ALTER TABLE market_candle
    ALTER COLUMN provider_opened_at SET NOT NULL;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM market_candle
        WHERE interval_code = 'days:1'
        GROUP BY instrument_id, source_id,
                 (opened_at AT TIME ZONE 'Asia/Kolkata')::date
        HAVING COUNT(*) > 1
           AND COUNT(DISTINCT ROW(
               open_price, high_price, low_price, close_price, volume, is_complete
           )) > 1
    ) THEN
        RAISE EXCEPTION
            'Conflicting daily candles exist for the same instrument, source, and trading date';
    END IF;
END $$;

WITH ranked_daily_candles AS (
    SELECT id,
           ROW_NUMBER() OVER (
               PARTITION BY instrument_id, source_id,
                            (opened_at AT TIME ZONE 'Asia/Kolkata')::date
               ORDER BY opened_at, id
           ) AS duplicate_rank
    FROM market_candle
    WHERE interval_code = 'days:1'
)
DELETE FROM market_candle candle
USING ranked_daily_candles ranked
WHERE candle.id = ranked.id
  AND ranked.duplicate_rank > 1;

UPDATE market_candle
SET opened_at = DATE_TRUNC('day', opened_at AT TIME ZONE 'Asia/Kolkata')
                    AT TIME ZONE 'Asia/Kolkata'
WHERE interval_code = 'days:1';

ALTER TABLE market_candle
    ADD CONSTRAINT ck_market_candle_daily_canonical_time CHECK (
        interval_code <> 'days:1'
        OR opened_at = DATE_TRUNC('day', opened_at AT TIME ZONE 'Asia/Kolkata')
                           AT TIME ZONE 'Asia/Kolkata'
    );

COMMENT ON COLUMN market_candle.provider_opened_at IS
    'Original timestamp supplied by the provider before interval-specific normalization.';
