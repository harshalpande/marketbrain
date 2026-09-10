CREATE TABLE news_source_permission_register (
    source_key VARCHAR(64) PRIMARY KEY,
    display_name VARCHAR(255) NOT NULL,
    source_type VARCHAR(32) NOT NULL,
    source_url TEXT NOT NULL,
    permission_status VARCHAR(32) NOT NULL,
    permission_evidence_reference TEXT NOT NULL,
    requested_on DATE,
    decided_on DATE,
    retention_days INTEGER,
    headline_storage_allowed BOOLEAN NOT NULL DEFAULT FALSE,
    snippet_storage_allowed BOOLEAN NOT NULL DEFAULT FALSE,
    full_text_storage_allowed BOOLEAN NOT NULL DEFAULT FALSE,
    local_ai_processing_allowed BOOLEAN NOT NULL DEFAULT FALSE,
    derived_data_retention_allowed BOOLEAN NOT NULL DEFAULT FALSE,
    attribution_required BOOLEAN NOT NULL DEFAULT FALSE,
    permitted_fields TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    integration_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ck_news_source_type
        CHECK (source_type IN ('NEWS_API', 'RSS', 'OFFICIAL_DISCLOSURE')),
    CONSTRAINT ck_news_permission_status
        CHECK (permission_status IN (
            'AWAITING_RESPONSE',
            'TERMS_REVIEW_REQUIRED',
            'APPROVED',
            'REJECTED',
            'API_LICENSE_ACCEPTED',
            'PUBLIC_TERMS_ALLOWED',
            'PAID_ONLY'
        )),
    CONSTRAINT ck_news_decision_dates
        CHECK (decided_on IS NULL OR requested_on IS NULL OR decided_on >= requested_on),
    CONSTRAINT ck_news_retention_days
        CHECK (retention_days IS NULL OR retention_days BETWEEN 0 AND 3650),
    CONSTRAINT ck_news_integration_requires_permission
        CHECK (
            integration_enabled = FALSE
            OR (
                permission_status IN ('APPROVED', 'API_LICENSE_ACCEPTED', 'PUBLIC_TERMS_ALLOWED')
                AND decided_on IS NOT NULL
                AND retention_days IS NOT NULL
                AND cardinality(permitted_fields) > 0
            )
        ),
    CONSTRAINT ck_news_unapproved_has_no_usage_rights
        CHECK (
            permission_status IN ('APPROVED', 'API_LICENSE_ACCEPTED', 'PUBLIC_TERMS_ALLOWED')
            OR (
                headline_storage_allowed = FALSE
                AND snippet_storage_allowed = FALSE
                AND full_text_storage_allowed = FALSE
                AND local_ai_processing_allowed = FALSE
                AND derived_data_retention_allowed = FALSE
                AND attribution_required = FALSE
                AND retention_days IS NULL
                AND cardinality(permitted_fields) = 0
            )
        )
);

CREATE TABLE news_source_checkpoint (
    source_key VARCHAR(64) PRIMARY KEY REFERENCES news_source_permission_register(source_key),
    etag TEXT,
    last_modified TEXT,
    last_seen_provider_item_id TEXT,
    last_polled_at TIMESTAMPTZ,
    next_allowed_poll_at TIMESTAMPTZ,
    request_count_today INTEGER NOT NULL DEFAULT 0,
    quota_date DATE,
    last_success_at TIMESTAMPTZ,
    last_failure_at TIMESTAMPTZ,
    last_failure_reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ck_news_checkpoint_request_count CHECK (request_count_today >= 0)
);

CREATE TABLE news_story_cluster (
    id UUID PRIMARY KEY,
    cluster_key VARCHAR(128) NOT NULL UNIQUE,
    primary_source_key VARCHAR(64) NOT NULL REFERENCES news_source_permission_register(source_key),
    first_seen_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    latest_seen_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    verification_state VARCHAR(32) NOT NULL DEFAULT 'UNVERIFIED',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ck_news_cluster_verification
        CHECK (verification_state IN ('VERIFIED_PRIMARY', 'CORROBORATED', 'UNVERIFIED', 'CONFLICTED'))
);

CREATE TABLE news_article (
    id UUID PRIMARY KEY,
    source_key VARCHAR(64) NOT NULL REFERENCES news_source_permission_register(source_key),
    provider_item_id TEXT NOT NULL,
    canonical_url TEXT NOT NULL,
    source_domain VARCHAR(255) NOT NULL,
    title TEXT,
    snippet TEXT,
    provider_published_at TIMESTAMPTZ,
    first_seen_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    content_hash VARCHAR(64) NOT NULL,
    story_cluster_id UUID REFERENCES news_story_cluster(id),
    permitted_payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    attribution JSONB NOT NULL DEFAULT '{}'::jsonb,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_news_article_provider_item UNIQUE (source_key, provider_item_id),
    CONSTRAINT uk_news_article_content_hash UNIQUE (source_key, content_hash)
);

CREATE INDEX idx_news_article_source_published
    ON news_article (source_key, provider_published_at DESC);

CREATE INDEX idx_news_article_cluster
    ON news_article (story_cluster_id);

CREATE TABLE news_article_instrument_match (
    id BIGSERIAL PRIMARY KEY,
    news_article_id UUID NOT NULL REFERENCES news_article(id),
    instrument_id BIGINT REFERENCES instrument(id),
    exchange VARCHAR(12) NOT NULL DEFAULT 'NSE',
    symbol VARCHAR(64) NOT NULL,
    isin VARCHAR(16),
    match_basis VARCHAR(64) NOT NULL,
    match_confidence NUMERIC(5,2) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ck_news_match_confidence CHECK (match_confidence >= 0 AND match_confidence <= 100),
    CONSTRAINT uk_news_article_symbol_match UNIQUE (news_article_id, exchange, symbol)
);

CREATE TABLE news_event_feature (
    id UUID PRIMARY KEY,
    news_article_id UUID NOT NULL REFERENCES news_article(id),
    instrument_id BIGINT REFERENCES instrument(id),
    event_class VARCHAR(64) NOT NULL,
    direction VARCHAR(16) NOT NULL,
    materiality_score NUMERIC(5,2) NOT NULL,
    expected_horizon VARCHAR(32) NOT NULL,
    verification_state VARCHAR(32) NOT NULL,
    model_version VARCHAR(64) NOT NULL,
    prompt_version VARCHAR(64) NOT NULL,
    rule_version VARCHAR(64) NOT NULL,
    rationale JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ck_news_event_direction CHECK (direction IN ('POSITIVE', 'NEGATIVE', 'NEUTRAL', 'MIXED')),
    CONSTRAINT ck_news_event_materiality CHECK (materiality_score >= 0 AND materiality_score <= 100),
    CONSTRAINT ck_news_event_verification
        CHECK (verification_state IN ('VERIFIED_PRIMARY', 'CORROBORATED', 'UNVERIFIED', 'CONFLICTED'))
);

INSERT INTO news_source_permission_register (
    source_key,
    display_name,
    source_type,
    source_url,
    permission_status,
    permission_evidence_reference,
    requested_on
)
VALUES
    ('MARKETAUX_API', 'Marketaux API', 'NEWS_API', 'https://www.marketaux.com/tos',
        'AWAITING_RESPONSE', 'EMAIL_REQUEST_SENT', DATE '2026-09-09'),
    ('ECONOMIC_TIMES_RSS', 'Economic Times RSS', 'RSS', 'https://economictimes.indiatimes.com/rss.cms',
        'AWAITING_RESPONSE', 'EMAIL_AND_X_REQUEST_SENT', DATE '2026-09-09'),
    ('LIVEMINT_RSS', 'Mint RSS', 'RSS', 'https://www.livemint.com/rss',
        'AWAITING_RESPONSE', 'EMAIL_REQUEST_SENT', DATE '2026-09-09'),
    ('BUSINESS_STANDARD_RSS', 'Business Standard RSS', 'RSS', 'https://www.business-standard.com/rss-feeds/listing',
        'AWAITING_RESPONSE', 'EMAIL_REQUEST_SENT', DATE '2026-09-09'),
    ('NSE_DISCLOSURES', 'NSE corporate disclosures', 'OFFICIAL_DISCLOSURE',
        'https://www.nseindia.com/companies-listing/corporate-filings-announcements',
        'TERMS_REVIEW_REQUIRED', 'PUBLISHED_TERMS_PENDING_REVIEW', NULL),
    ('BSE_DISCLOSURES', 'BSE corporate announcements', 'OFFICIAL_DISCLOSURE',
        'https://www.bseindia.com/corporates/ann.html',
        'TERMS_REVIEW_REQUIRED', 'PUBLISHED_TERMS_PENDING_REVIEW', NULL),
    ('SEBI_PUBLIC_UPDATES', 'SEBI public updates', 'OFFICIAL_DISCLOSURE',
        'https://www.sebi.gov.in/',
        'TERMS_REVIEW_REQUIRED', 'PUBLISHED_TERMS_PENDING_REVIEW', NULL),
    ('RBI_PRESS_RELEASES', 'RBI press releases', 'OFFICIAL_DISCLOSURE',
        'https://www.rbi.org.in/Scripts/BS_PressReleaseDisplay.aspx',
        'TERMS_REVIEW_REQUIRED', 'PUBLISHED_TERMS_PENDING_REVIEW', NULL);

INSERT INTO news_source_checkpoint (source_key)
SELECT source_key
FROM news_source_permission_register;

COMMENT ON TABLE news_source_permission_register IS
    'Governed source-level permission register. Implemented connectors remain disabled until permission and terms gates are satisfied.';

COMMENT ON TABLE news_article IS
    'Permission-scoped article metadata and permitted payload. Full text must not be stored unless the source licence explicitly permits it.';

COMMENT ON TABLE news_event_feature IS
    'Point-in-time derived news feature records. These do not create signals, orders, broker actions, or model training rows by themselves.';
