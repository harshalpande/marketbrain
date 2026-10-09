-- Promotes previously isolated approval and delivery schemas. Does not enable runtime actions.
-- Previously verified approval persistence; application actions remain disabled.
CREATE TABLE paper_approval_proposal (
    id VARCHAR(100) PRIMARY KEY,
    portfolio_id BIGINT NOT NULL REFERENCES paper_ledger_account(portfolio_id),
    instrument_id BIGINT NOT NULL REFERENCES instrument(id),
    recipient_hash CHAR(64) NOT NULL,
    expected_revision BIGINT NOT NULL CHECK (expected_revision >= 0),
    payload TEXT NOT NULL CHECK (octet_length(payload) <= 16384),
    payload_hash CHAR(64) NOT NULL,
    policy_hash CHAR(64) NOT NULL,
    decided_token CHAR(64),
    callback_id VARCHAR(128) UNIQUE,
    receipt TEXT CHECK (octet_length(receipt) <= 16384),
    CHECK ((receipt IS NULL AND decided_token IS NULL AND callback_id IS NULL)
        OR (receipt IS NOT NULL AND decided_token IS NOT NULL AND callback_id IS NOT NULL))
);
CREATE TABLE paper_approval_token (
    token_hash CHAR(64) PRIMARY KEY,
    proposal_id VARCHAR(100) NOT NULL REFERENCES paper_approval_proposal(id),
    action VARCHAR(8) NOT NULL CHECK (action IN ('ACCEPT','REJECT')),
    UNIQUE (proposal_id,action)
);
CREATE FUNCTION paper_approval_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'Approval evidence cannot be deleted'; END IF;
    IF OLD.receipt IS NOT NULL OR
       ROW(NEW.id,NEW.portfolio_id,NEW.instrument_id,NEW.recipient_hash,NEW.expected_revision,NEW.payload,NEW.payload_hash,NEW.policy_hash)
       IS DISTINCT FROM ROW(OLD.id,OLD.portfolio_id,OLD.instrument_id,OLD.recipient_hash,OLD.expected_revision,OLD.payload,OLD.payload_hash,OLD.policy_hash)
       THEN RAISE EXCEPTION 'Approval evidence is immutable'; END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER paper_approval_guard BEFORE UPDATE OR DELETE ON paper_approval_proposal
FOR EACH ROW EXECUTE FUNCTION paper_approval_guard();
CREATE TRIGGER paper_approval_token_immutable BEFORE UPDATE OR DELETE ON paper_approval_token
FOR EACH ROW EXECUTE FUNCTION paper_ledger_immutable();

-- Previously verified delivery persistence; no active sender is registered.
CREATE TABLE paper_approval_delivery (
    proposal_id VARCHAR(100) PRIMARY KEY REFERENCES paper_approval_proposal(id),
    encrypted_tokens TEXT NOT NULL CHECK (octet_length(encrypted_tokens) <= 4096),
    state VARCHAR(16) NOT NULL CHECK (state IN ('PENDING','SENDING','SENT','UNCERTAIN','EXPIRED','REVOKED','KEY_BLOCKED')),
    attempt_id VARCHAR(36),
    message_id VARCHAR(32),
    created_at TIMESTAMPTZ NOT NULL,
    attempted_at TIMESTAMPTZ,
    CHECK ((state IN ('PENDING','EXPIRED','REVOKED','KEY_BLOCKED') AND attempt_id IS NULL AND attempted_at IS NULL AND message_id IS NULL)
       OR (state IN ('SENDING','UNCERTAIN') AND attempt_id IS NOT NULL AND attempted_at IS NOT NULL AND message_id IS NULL)
       OR (state='SENT' AND attempt_id IS NOT NULL AND attempted_at IS NOT NULL AND message_id IS NOT NULL))
);
CREATE FUNCTION paper_delivery_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP='DELETE' THEN RAISE EXCEPTION 'Delivery evidence cannot be deleted'; END IF;
    IF ROW(NEW.proposal_id,NEW.encrypted_tokens,NEW.created_at) IS DISTINCT FROM ROW(OLD.proposal_id,OLD.encrypted_tokens,OLD.created_at)
       OR NOT ((OLD.state='PENDING' AND NEW.state IN ('SENDING','EXPIRED','REVOKED','KEY_BLOCKED'))
           OR (OLD.state='SENDING' AND NEW.state IN ('SENT','UNCERTAIN') AND NEW.attempt_id=OLD.attempt_id AND NEW.attempted_at=OLD.attempted_at))
    THEN RAISE EXCEPTION 'Invalid immutable delivery transition'; END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER paper_delivery_guard BEFORE UPDATE OR DELETE ON paper_approval_delivery
FOR EACH ROW EXECUTE FUNCTION paper_delivery_guard();


CREATE TABLE paper_approval_key_binding (
    id SMALLINT PRIMARY KEY CHECK(id=1),
    fingerprint CHAR(64) NOT NULL,
    probe TEXT NOT NULL CHECK(octet_length(probe)<=4096),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TRIGGER paper_approval_key_immutable BEFORE UPDATE OR DELETE ON paper_approval_key_binding
FOR EACH ROW EXECUTE FUNCTION paper_ledger_immutable();
