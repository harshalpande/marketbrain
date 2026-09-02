CREATE TABLE provider_instrument (
    id BIGSERIAL PRIMARY KEY,
    source_id BIGINT NOT NULL REFERENCES market_data_source(id),
    instrument_id BIGINT NOT NULL REFERENCES instrument(id),
    provider_instrument_key VARCHAR(160) NOT NULL,
    segment VARCHAR(32) NOT NULL,
    instrument_type VARCHAR(32) NOT NULL,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    received_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_provider_instrument_key UNIQUE (source_id, provider_instrument_key),
    CONSTRAINT uk_provider_instrument_mapping UNIQUE (source_id, instrument_id)
);

CREATE INDEX idx_provider_instrument_instrument ON provider_instrument (instrument_id);

CREATE TABLE market_quote_snapshot (
    id BIGSERIAL PRIMARY KEY,
    instrument_id BIGINT NOT NULL REFERENCES instrument(id),
    source_id BIGINT NOT NULL REFERENCES market_data_source(id),
    provider_instrument_key VARCHAR(160) NOT NULL,
    provider_published_at TIMESTAMPTZ NOT NULL,
    last_trade_at TIMESTAMPTZ,
    received_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_price NUMERIC(18,4) NOT NULL,
    previous_close NUMERIC(18,4),
    volume NUMERIC(24,4),
    quality_status VARCHAR(16) NOT NULL,
    CONSTRAINT ck_market_quote_last_price CHECK (last_price > 0),
    CONSTRAINT ck_market_quote_quality CHECK (quality_status IN ('FRESH', 'STALE')),
    CONSTRAINT uk_market_quote_source_time UNIQUE (source_id, provider_instrument_key, provider_published_at)
);

CREATE INDEX idx_market_quote_instrument_time
    ON market_quote_snapshot (instrument_id, provider_published_at DESC);
