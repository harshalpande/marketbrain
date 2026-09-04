CREATE TABLE instrument_identity_alias (
    id BIGSERIAL PRIMARY KEY,
    exchange VARCHAR(12) NOT NULL,
    current_symbol VARCHAR(64) NOT NULL,
    alias_symbol VARCHAR(64) NOT NULL,
    alias_isin VARCHAR(16),
    effective_from DATE NOT NULL,
    effective_to DATE NOT NULL,
    evidence_source VARCHAR(160) NOT NULL,
    identity_evidence_url TEXT NOT NULL,
    lineage_evidence_url TEXT NOT NULL,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ck_instrument_identity_alias_dates CHECK (effective_to >= effective_from),
    CONSTRAINT uk_instrument_identity_alias_period
        UNIQUE (exchange, current_symbol, alias_symbol, effective_from, effective_to)
);

INSERT INTO instrument_identity_alias
    (exchange, current_symbol, alias_symbol, alias_isin, effective_from, effective_to,
     evidence_source, identity_evidence_url, lineage_evidence_url, notes)
VALUES
    ('NSE', 'ACUTAAS', 'AMIORG', 'INE00FF01017', DATE '2025-01-29', DATE '2025-04-24',
     'NSE official BhavCopy and listing circulars',
     'https://archives.nseindia.com/content/cm/BhavCopy_NSE_CM_0_0_0_20250129_F_0000.csv.zip',
     'https://nsearchives.nseindia.com/content/circulars/CML68201.pdf',
     'The audited finding date uses the historical AMIORG symbol and pre-split ISIN. NSE changed the ISIN from 25 April 2025 and changed the symbol to ACUTAAS from 2 June 2025.'),
    ('NSE', 'ACUTAAS', 'AMIORG', 'INE00FF01025', DATE '2025-04-25', DATE '2025-06-01',
     'NSE listing circulars',
     'https://nsearchives.nseindia.com/content/circulars/CML67615.pdf',
     'https://nsearchives.nseindia.com/content/circulars/CML68201.pdf',
     'NSE changed the ISIN from 25 April 2025 while AMIORG remained the trading symbol until the ACUTAAS symbol became effective on 2 June 2025.');

COMMENT ON TABLE instrument_identity_alias IS
    'Effective-dated, evidence-backed exchange identities used only to match historical official records; entries do not rewrite instrument or candle data.';

COMMENT ON COLUMN instrument_identity_alias.identity_evidence_url IS
    'Official evidence for the historical symbol or ISIN during the effective period.';

COMMENT ON COLUMN instrument_identity_alias.lineage_evidence_url IS
    'Official evidence connecting the historical identity to the current symbol.';
