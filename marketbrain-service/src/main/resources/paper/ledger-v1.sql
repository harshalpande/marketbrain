-- Candidate application migration. NOT on the Flyway path: isolated verification first.
-- Run transactionally with the intended schema on search_path. No account creation/funding.
SET LOCAL lock_timeout = '3s';
SET LOCAL statement_timeout = '10s';
LOCK TABLE paper_portfolio, paper_order, paper_fill IN SHARE ROW EXCLUSIVE MODE;
CREATE TABLE paper_ledger_account (
    portfolio_id BIGINT PRIMARY KEY REFERENCES paper_portfolio(id),
    opening_cash BIGINT NOT NULL CHECK (opening_cash >= 0),
    cash BIGINT NOT NULL CHECK (cash >= 0),
    reserved BIGINT NOT NULL DEFAULT 0 CHECK (reserved >= 0 AND reserved <= cash),
    revision BIGINT NOT NULL DEFAULT 0 CHECK (revision >= 0),
    last_at TIMESTAMPTZ,
    policy TEXT,
    tail CHAR(64) NOT NULL
);
CREATE TABLE paper_ledger_command (
    portfolio_id BIGINT NOT NULL REFERENCES paper_ledger_account(portfolio_id),
    command_id VARCHAR(100) NOT NULL,
    revision BIGINT NOT NULL CHECK (revision > 0),
    payload TEXT NOT NULL CHECK (octet_length(payload) <= 16384),
    receipt TEXT NOT NULL CHECK (octet_length(receipt) <= 16384),
    previous_hash CHAR(64) NOT NULL,
    hash CHAR(64) NOT NULL,
    PRIMARY KEY (portfolio_id, command_id),
    UNIQUE (portfolio_id, revision)
);
CREATE TABLE paper_ledger_decision (
    portfolio_id BIGINT NOT NULL REFERENCES paper_ledger_account(portfolio_id),
    approval_id VARCHAR(100) NOT NULL,
    order_id VARCHAR(100) NOT NULL,
    payload TEXT NOT NULL CHECK (octet_length(payload) <= 16384),
    PRIMARY KEY (portfolio_id, approval_id),
    UNIQUE (portfolio_id, order_id)
);
CREATE TABLE paper_ledger_order (
    portfolio_id BIGINT NOT NULL,
    order_id VARCHAR(100) NOT NULL,
    instrument_id BIGINT NOT NULL REFERENCES instrument(id),
    payload TEXT NOT NULL CHECK (octet_length(payload) <= 16384),
    hash CHAR(64) NOT NULL,
    PRIMARY KEY (portfolio_id, order_id),
    FOREIGN KEY (portfolio_id, order_id) REFERENCES paper_ledger_decision(portfolio_id, order_id)
);
CREATE TABLE paper_ledger_position (
    portfolio_id BIGINT NOT NULL REFERENCES paper_ledger_account(portfolio_id),
    instrument_id BIGINT NOT NULL REFERENCES instrument(id),
    quantity BIGINT NOT NULL CHECK (quantity >= 0),
    reserved BIGINT NOT NULL CHECK (reserved >= 0 AND reserved <= quantity),
    hash CHAR(64) NOT NULL,
    PRIMARY KEY (portfolio_id, instrument_id)
);
CREATE TABLE paper_ledger_fill (
    portfolio_id BIGINT NOT NULL,
    fill_id VARCHAR(100) NOT NULL,
    order_id VARCHAR(100) NOT NULL,
    payload TEXT NOT NULL CHECK (octet_length(payload) <= 16384),
    PRIMARY KEY (portfolio_id, fill_id),
    FOREIGN KEY (portfolio_id, order_id) REFERENCES paper_ledger_order(portfolio_id, order_id)
);
CREATE INDEX paper_ledger_fill_order ON paper_ledger_fill(portfolio_id, order_id, fill_id);
CREATE FUNCTION paper_ledger_immutable() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'Ledger evidence is append only'; END;
$$;
CREATE TRIGGER paper_ledger_command_immutable BEFORE UPDATE OR DELETE ON paper_ledger_command
FOR EACH ROW EXECUTE FUNCTION paper_ledger_immutable();
CREATE TRIGGER paper_ledger_decision_immutable BEFORE UPDATE OR DELETE ON paper_ledger_decision
FOR EACH ROW EXECUTE FUNCTION paper_ledger_immutable();
CREATE TRIGGER paper_ledger_fill_immutable BEFORE UPDATE OR DELETE ON paper_ledger_fill
FOR EACH ROW EXECUTE FUNCTION paper_ledger_immutable();
-- Link ONLY the reviewed pristine account. Missing/changed/ambiguous/history-bearing states stay unattached.
INSERT INTO paper_ledger_account (portfolio_id, opening_cash, cash, tail)
SELECT id, (current_cash * 100)::bigint, (current_cash * 100)::bigint, repeat('0',64)
FROM paper_portfolio p
WHERE p.id = 1 AND p.name = 'Default Paper Portfolio' AND p.active AND p.execution_mode = 'PAPER'
AND p.starting_cash = 100000.00 AND p.current_cash = 100000.00
AND NOT EXISTS (SELECT 1 FROM paper_portfolio other WHERE other.active AND other.id <> p.id)
AND NOT EXISTS (SELECT 1 FROM paper_order) AND NOT EXISTS (SELECT 1 FROM paper_fill);
