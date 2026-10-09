-- Isolated integration candidate only. Not a Flyway migration or an active sender.
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
