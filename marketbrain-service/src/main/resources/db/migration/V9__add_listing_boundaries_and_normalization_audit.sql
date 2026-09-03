ALTER TABLE instrument
    ADD COLUMN listed_on DATE,
    ADD COLUMN listing_date_source_url TEXT;

ALTER TABLE instrument
    ADD CONSTRAINT ck_instrument_listing_date_provenance CHECK (
        (listed_on IS NULL AND listing_date_source_url IS NULL)
        OR (listed_on IS NOT NULL AND listing_date_source_url IS NOT NULL)
    );

ALTER TABLE market_data_quality_issue
    ADD COLUMN details TEXT;

UPDATE instrument
SET listed_on = DATE '2020-10-05',
    listing_date_source_url =
        'https://www.nseindia.com/static/event-details-listing-ceremony-angel-broking',
    updated_at = CURRENT_TIMESTAMP
WHERE exchange = 'NSE' AND symbol = 'ANGELONE';

UPDATE instrument
SET listed_on = DATE '2019-09-19',
    listing_date_source_url =
        'https://nsearchives.nseindia.com/corporate/IIFLWAM_22092020153542_IIFLWAM_9973_reply.pdf',
    updated_at = CURRENT_TIMESTAMP
WHERE exchange = 'NSE' AND symbol = '360ONE';

CREATE UNIQUE INDEX uk_market_data_quality_issue_open_chunk_code
    ON market_data_quality_issue (chunk_id, issue_code)
    WHERE chunk_id IS NOT NULL AND resolved_at IS NULL;

COMMENT ON COLUMN instrument.listed_on IS
    'First exchange-listed trading date for this symbol lineage; null until supported by authoritative evidence.';

COMMENT ON COLUMN instrument.listing_date_source_url IS
    'Authoritative source supporting listed_on. Both fields are populated or absent together.';

COMMENT ON INDEX uk_market_data_quality_issue_open_chunk_code IS
    'Prevents duplicate unresolved audit findings when a backfill chunk is explicitly retried.';
