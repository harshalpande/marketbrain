CREATE TABLE instrument_listing_evidence (
    id BIGSERIAL PRIMARY KEY,
    instrument_id BIGINT NOT NULL REFERENCES instrument(id),
    source_code VARCHAR(64) NOT NULL,
    source_url TEXT NOT NULL,
    source_sha256 VARCHAR(64) NOT NULL,
    source_symbol VARCHAR(64) NOT NULL,
    source_isin VARCHAR(16) NOT NULL,
    source_series VARCHAR(16) NOT NULL,
    reported_listed_on DATE NOT NULL,
    provider_prelisting_candle_on DATE,
    reconciliation_status VARCHAR(40) NOT NULL,
    provider_request_count INTEGER NOT NULL DEFAULT 0,
    received_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ck_listing_evidence_source_url CHECK (source_url LIKE 'https://%'),
    CONSTRAINT ck_listing_evidence_hash CHECK (source_sha256 ~ '^[0-9a-f]{64}$'),
    CONSTRAINT ck_listing_evidence_required_text CHECK (
        BTRIM(source_code) <> '' AND BTRIM(source_symbol) <> ''
        AND BTRIM(source_isin) <> '' AND BTRIM(source_series) <> ''
    ),
    CONSTRAINT ck_listing_evidence_status CHECK (
        reconciliation_status IN (
            'BEFORE_REQUEST_WINDOW', 'EXISTING_BOUNDARY',
            'VERIFIED_LISTING_BOUNDARY', 'EARLIER_PROVIDER_HISTORY'
        )
    ),
    CONSTRAINT ck_listing_evidence_provider_date CHECK (
        (reconciliation_status = 'EARLIER_PROVIDER_HISTORY'
            AND provider_prelisting_candle_on IS NOT NULL
            AND provider_prelisting_candle_on < reported_listed_on)
        OR
        (reconciliation_status <> 'EARLIER_PROVIDER_HISTORY'
            AND provider_prelisting_candle_on IS NULL)
    ),
    CONSTRAINT ck_listing_evidence_request_count CHECK (provider_request_count >= 0),
    CONSTRAINT uk_listing_evidence_file UNIQUE (instrument_id, source_sha256, source_series)
);

CREATE INDEX idx_listing_evidence_latest
    ON instrument_listing_evidence (instrument_id, received_at DESC, id DESC);

COMMENT ON TABLE instrument_listing_evidence IS
    'Immutable-source NSE security listing metadata reconciled against earlier Upstox history before a backfill boundary is trusted.';

COMMENT ON COLUMN instrument_listing_evidence.reported_listed_on IS
    'Raw DATE OF LISTING from the identified NSE security-master file; it is not automatically treated as full symbol-lineage inception.';

COMMENT ON COLUMN instrument_listing_evidence.provider_prelisting_candle_on IS
    'A detected Upstox candle before the reported NSE security date, proving that the reported date must not truncate provider history.';
