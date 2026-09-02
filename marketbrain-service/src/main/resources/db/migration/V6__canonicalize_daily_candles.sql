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
           AND (
               MIN(open_price) <> MAX(open_price)
               OR MIN(close_price) <> MAX(close_price)
               OR MAX(high_price) - MIN(high_price) > 0.01
               OR MAX(low_price) - MIN(low_price) > 0.01
               OR COUNT(DISTINCT ROW(volume IS NULL, volume)) > 1
               OR BOOL_AND(is_complete) <> BOOL_OR(is_complete)
           )
    ) THEN
        RAISE EXCEPTION
            'Conflicting daily candles exist for the same instrument, source, and trading date';
    END IF;
END $$;

WITH duplicate_daily_envelopes AS (
    SELECT instrument_id,
           source_id,
           (opened_at AT TIME ZONE 'Asia/Kolkata')::date AS trading_date,
           MAX(high_price) AS merged_high_price,
           MIN(low_price) AS merged_low_price
    FROM market_candle
    WHERE interval_code = 'days:1'
    GROUP BY instrument_id, source_id,
             (opened_at AT TIME ZONE 'Asia/Kolkata')::date
    HAVING COUNT(*) > 1
)
UPDATE market_candle candle
SET high_price = duplicate.merged_high_price,
    low_price = duplicate.merged_low_price
FROM duplicate_daily_envelopes duplicate
WHERE candle.instrument_id = duplicate.instrument_id
  AND candle.source_id = duplicate.source_id
  AND (candle.opened_at AT TIME ZONE 'Asia/Kolkata')::date = duplicate.trading_date;

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
