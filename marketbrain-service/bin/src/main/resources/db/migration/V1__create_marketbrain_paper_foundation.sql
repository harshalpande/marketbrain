CREATE TYPE execution_mode AS ENUM ('PAPER', 'LIVE');
CREATE TYPE signal_action AS ENUM ('BUY', 'SELL_HOLDING');
CREATE TYPE signal_status AS ENUM ('PENDING', 'VALID', 'REVALIDATED', 'EXPIRED', 'RISK_BLOCKED', 'APPROVED', 'REJECTED', 'EXECUTED', 'CLOSED');
CREATE TYPE paper_order_status AS ENUM ('PENDING_REVALIDATION', 'REJECTED', 'FILLED', 'CANCELLED', 'RISK_BLOCKED');
CREATE TYPE whatsapp_alert_type AS ENUM ('NOTE', 'BUY', 'SELL_HOLDING');
CREATE TYPE whatsapp_action_type AS ENUM ('APPROVE', 'REJECT', 'DETAILS');

CREATE TABLE instrument (
    id BIGSERIAL PRIMARY KEY,
    exchange VARCHAR(12) NOT NULL,
    symbol VARCHAR(64) NOT NULL,
    isin VARCHAR(16),
    display_name VARCHAR(255) NOT NULL,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_instrument_exchange_symbol UNIQUE (exchange, symbol)
);

CREATE TABLE universe_membership (
    id BIGSERIAL PRIMARY KEY,
    universe_code VARCHAR(32) NOT NULL,
    instrument_id BIGINT NOT NULL REFERENCES instrument(id),
    effective_from DATE NOT NULL,
    effective_to DATE,
    source_name VARCHAR(100) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ck_universe_membership_dates CHECK (effective_to IS NULL OR effective_to >= effective_from),
    CONSTRAINT uk_universe_membership_effective UNIQUE (universe_code, instrument_id, effective_from)
);

CREATE TABLE market_data_source (
    id BIGSERIAL PRIMARY KEY,
    code VARCHAR(64) NOT NULL UNIQUE,
    display_name VARCHAR(255) NOT NULL,
    enabled BOOLEAN NOT NULL DEFAULT FALSE,
    status VARCHAR(32) NOT NULL DEFAULT 'UNVERIFIED',
    last_success_at TIMESTAMPTZ,
    last_failure_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE market_candle (
    id BIGSERIAL PRIMARY KEY,
    instrument_id BIGINT NOT NULL REFERENCES instrument(id),
    source_id BIGINT NOT NULL REFERENCES market_data_source(id),
    interval_code VARCHAR(16) NOT NULL,
    opened_at TIMESTAMPTZ NOT NULL,
    source_published_at TIMESTAMPTZ,
    received_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    open_price NUMERIC(18,4) NOT NULL,
    high_price NUMERIC(18,4) NOT NULL,
    low_price NUMERIC(18,4) NOT NULL,
    close_price NUMERIC(18,4) NOT NULL,
    volume NUMERIC(24,4),
    is_complete BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT ck_market_candle_prices CHECK (low_price <= open_price AND low_price <= close_price AND high_price >= open_price AND high_price >= close_price),
    CONSTRAINT uk_market_candle_source UNIQUE (instrument_id, source_id, interval_code, opened_at)
);

CREATE TABLE paper_portfolio (
    id BIGSERIAL PRIMARY KEY,
    execution_mode execution_mode NOT NULL DEFAULT 'PAPER',
    name VARCHAR(100) NOT NULL,
    starting_cash NUMERIC(18,2) NOT NULL,
    current_cash NUMERIC(18,2) NOT NULL,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ck_paper_portfolio_mode CHECK (execution_mode = 'PAPER'),
    CONSTRAINT ck_paper_portfolio_cash CHECK (starting_cash >= 0 AND current_cash >= 0),
    CONSTRAINT uk_active_paper_portfolio_name UNIQUE (name)
);

CREATE TABLE market_signal (
    id UUID PRIMARY KEY,
    instrument_id BIGINT NOT NULL REFERENCES instrument(id),
    strategy_code VARCHAR(100) NOT NULL,
    strategy_version VARCHAR(64) NOT NULL,
    action signal_action NOT NULL,
    status signal_status NOT NULL DEFAULT 'PENDING',
    confidence_score NUMERIC(5,2) NOT NULL,
    generated_at TIMESTAMPTZ NOT NULL,
    data_as_of TIMESTAMPTZ NOT NULL,
    valid_until TIMESTAMPTZ NOT NULL,
    reference_price NUMERIC(18,4) NOT NULL,
    acceptable_price_min NUMERIC(18,4) NOT NULL,
    acceptable_price_max NUMERIC(18,4) NOT NULL,
    maximum_slippage_percent NUMERIC(6,3) NOT NULL,
    target_price NUMERIC(18,4),
    stop_loss_price NUMERIC(18,4),
    rationale JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ck_signal_confidence CHECK (confidence_score >= 0 AND confidence_score <= 100),
    CONSTRAINT ck_signal_validity CHECK (valid_until > generated_at),
    CONSTRAINT ck_signal_price_zone CHECK (acceptable_price_min > 0 AND acceptable_price_max >= acceptable_price_min),
    CONSTRAINT ck_signal_reference_in_zone CHECK (reference_price BETWEEN acceptable_price_min AND acceptable_price_max),
    CONSTRAINT ck_signal_stop_loss CHECK (stop_loss_price IS NULL OR stop_loss_price > 0)
);

CREATE INDEX idx_market_signal_active ON market_signal (status, valid_until);
CREATE INDEX idx_market_signal_instrument_generated ON market_signal (instrument_id, generated_at DESC);

CREATE TABLE signal_risk_assessment (
    id BIGSERIAL PRIMARY KEY,
    signal_id UUID NOT NULL REFERENCES market_signal(id),
    assessed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    assessed_price NUMERIC(18,4) NOT NULL,
    recommended_quantity NUMERIC(18,4),
    portfolio_risk_percent NUMERIC(6,3) NOT NULL,
    approved BOOLEAN NOT NULL,
    rejection_reason VARCHAR(500),
    details JSONB NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT ck_signal_risk_percent CHECK (portfolio_risk_percent >= 0 AND portfolio_risk_percent <= 100),
    CONSTRAINT ck_risk_rejection_reason CHECK ((approved = TRUE AND rejection_reason IS NULL) OR (approved = FALSE AND rejection_reason IS NOT NULL))
);

CREATE TABLE whatsapp_alert (
    id UUID PRIMARY KEY,
    signal_id UUID REFERENCES market_signal(id),
    alert_type whatsapp_alert_type NOT NULL,
    external_message_id VARCHAR(255),
    recipient_phone_hash VARCHAR(128) NOT NULL,
    sent_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ,
    delivery_status VARCHAR(32) NOT NULL DEFAULT 'PENDING_CONFIGURATION',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE whatsapp_action (
    id UUID PRIMARY KEY,
    whatsapp_alert_id UUID NOT NULL REFERENCES whatsapp_alert(id),
    action whatsapp_action_type NOT NULL,
    action_token_hash VARCHAR(128) NOT NULL UNIQUE,
    received_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ NOT NULL,
    sender_phone_hash VARCHAR(128),
    processed BOOLEAN NOT NULL DEFAULT FALSE,
    idempotency_key VARCHAR(128) NOT NULL UNIQUE,
    processing_result VARCHAR(64),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE paper_order (
    id UUID PRIMARY KEY,
    paper_portfolio_id BIGINT NOT NULL REFERENCES paper_portfolio(id),
    signal_id UUID NOT NULL REFERENCES market_signal(id),
    instrument_id BIGINT NOT NULL REFERENCES instrument(id),
    action signal_action NOT NULL,
    status paper_order_status NOT NULL DEFAULT 'PENDING_REVALIDATION',
    requested_quantity NUMERIC(18,4) NOT NULL,
    approved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ck_paper_order_quantity CHECK (requested_quantity > 0)
);

CREATE TABLE paper_fill (
    id UUID PRIMARY KEY,
    paper_order_id UUID NOT NULL UNIQUE REFERENCES paper_order(id),
    filled_at TIMESTAMPTZ NOT NULL,
    fill_price NUMERIC(18,4) NOT NULL,
    quantity NUMERIC(18,4) NOT NULL,
    fees NUMERIC(18,4) NOT NULL DEFAULT 0,
    slippage_percent NUMERIC(6,3) NOT NULL DEFAULT 0,
    source_price_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT ck_paper_fill_price CHECK (fill_price > 0),
    CONSTRAINT ck_paper_fill_quantity CHECK (quantity > 0)
);

INSERT INTO market_data_source (code, display_name, enabled, status)
VALUES
    ('PAYTM_MONEY', 'Paytm Money Open API', FALSE, 'UNVERIFIED'),
    ('UPSTOX', 'Upstox Developer API', FALSE, 'UNVERIFIED'),
    ('NSE_DATA', 'NSE Data and Analytics', FALSE, 'UNVERIFIED');

INSERT INTO paper_portfolio (name, starting_cash, current_cash)
VALUES ('Default Paper Portfolio', 100000.00, 100000.00);
