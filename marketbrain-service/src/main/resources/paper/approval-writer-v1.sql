-- Candidate only, NOT a Flyway migration. Install in one transaction with PUBLIC execution revoked.
-- __SCHEMA__ is a validated quoted trusted schema. Own functions with a NOLOGIN, non-owner role.
-- Trusted backend only: Java still authenticates transport and validates policy/quotes, not the LLM.
CREATE FUNCTION __SCHEMA__.paper_review_lock(p_token text, p_user bigint, p_chat bigint)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, __SCHEMA__, pg_temp AS $$
DECLARE v_proposal __SCHEMA__.paper_approval_proposal%ROWTYPE;
BEGIN
    IF p_token IS NULL OR p_token !~ '^[a-f0-9]{64}$' OR p_user IS NULL OR p_chat IS NULL THEN
        RAISE EXCEPTION 'Invalid review identity' USING ERRCODE='42501';
    END IF;
    PERFORM 1 FROM __SCHEMA__.telegram_binding
      WHERE binding_key='PRIMARY' AND active=TRUE AND telegram_user_id=p_user AND telegram_chat_id=p_chat FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Unauthorized binding' USING ERRCODE='42501'; END IF;
    SELECT p.* INTO v_proposal FROM __SCHEMA__.paper_approval_token t
      JOIN __SCHEMA__.paper_approval_proposal p ON p.id=t.proposal_id
      WHERE t.token_hash=p_token FOR UPDATE OF p;
    IF NOT FOUND OR (v_proposal.payload::jsonb->>'userId')::bigint IS DISTINCT FROM p_user
       OR (v_proposal.payload::jsonb->>'chatId')::bigint IS DISTINCT FROM p_chat THEN
        RAISE EXCEPTION 'Unauthorized proposal' USING ERRCODE='42501';
    END IF;
    -- Same account lock order as the ledger; no ledger mutation in this function.
    PERFORM 1 FROM __SCHEMA__.paper_portfolio
      WHERE id=v_proposal.portfolio_id AND active=TRUE AND execution_mode='PAPER' FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Account unavailable'; END IF;
    PERFORM 1 FROM __SCHEMA__.paper_ledger_account WHERE portfolio_id=v_proposal.portfolio_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Ledger unavailable'; END IF;
    RETURN TRUE;
END;
$$;
REVOKE ALL ON FUNCTION __SCHEMA__.paper_review_lock(text,bigint,bigint) FROM PUBLIC;

CREATE FUNCTION __SCHEMA__.paper_review_record(p_token text,p_user bigint,p_chat bigint,p_callback text,p_receipt text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, __SCHEMA__, pg_temp AS $$
DECLARE v_proposal __SCHEMA__.paper_approval_proposal%ROWTYPE;
        v_action text; v_receipt jsonb; v_status text; v_revision bigint;
BEGIN
    PERFORM __SCHEMA__.paper_review_lock(p_token,p_user,p_chat);
    SELECT p.* INTO v_proposal FROM __SCHEMA__.paper_approval_token t
      JOIN __SCHEMA__.paper_approval_proposal p ON p.id=t.proposal_id WHERE t.token_hash=p_token;
    SELECT action INTO v_action FROM __SCHEMA__.paper_approval_token WHERE token_hash=p_token;
    IF p_receipt IS NULL OR octet_length(p_receipt)>16384 OR p_callback IS NULL
       OR p_callback !~ '^[A-Za-z0-9_.:-]{1,100}$' THEN RAISE EXCEPTION 'Invalid receipt'; END IF;
    v_receipt := p_receipt::jsonb; v_status := v_receipt->>'status';
    SELECT revision INTO v_revision FROM __SCHEMA__.paper_ledger_account WHERE portfolio_id=v_proposal.portfolio_id;
    IF jsonb_typeof(v_receipt) IS DISTINCT FROM 'object'
       OR v_receipt->>'version' IS DISTINCT FROM 'PAPER_APPROVAL_REVIEW_V1'
       OR v_receipt->'actionExecutionEnabled' IS DISTINCT FROM 'false'::jsonb
       OR v_receipt->>'proposalId' IS DISTINCT FROM v_proposal.id
       OR (v_receipt->>'accountRevision')::bigint IS DISTINCT FROM v_revision
       OR v_receipt->>'policyId' IS NULL OR v_receipt->>'assessedAt' IS NULL
       OR v_status IS NULL OR v_status NOT IN ('ACCEPTED_EXECUTION_BLOCKED','REJECTED','EXPIRED','CLOCK_INVALID',
           'POLICY_CHANGED','ACCOUNT_INCONSISTENT','ACCOUNT_CHANGED','QUOTE_UNAVAILABLE','QUOTE_IDENTITY_MISMATCH',
           'QUOTE_TIME_INVALID','INSUFFICIENT_CASH','INSUFFICIENT_SHARES','RISK_BLOCKED')
       OR (v_action='REJECT' AND v_status NOT IN ('REJECTED','EXPIRED','CLOCK_INVALID'))
       OR (v_action='ACCEPT' AND v_status='REJECTED')
       OR (v_status='ACCEPTED_EXECUTION_BLOCKED' AND
           (v_receipt->>'quoteHash' IS NULL OR v_receipt->>'quoteHash' !~ '^[a-f0-9]{64}$')) THEN
        RAISE EXCEPTION 'Invalid review-only receipt';
    END IF;
    -- No rewrite, no opposing-action replay. Java returns the saved receipt before reaching here.
    IF v_proposal.receipt IS NOT NULL THEN RAISE EXCEPTION 'Proposal already decided'; END IF;
    UPDATE __SCHEMA__.paper_approval_proposal SET decided_token=p_token,callback_id=p_callback,receipt=p_receipt
      WHERE id=v_proposal.id AND receipt IS NULL;
    IF NOT FOUND THEN RAISE EXCEPTION 'Decision raced'; END IF;
    RETURN TRUE;
END;
$$;
REVOKE ALL ON FUNCTION __SCHEMA__.paper_review_record(text,bigint,bigint,text,text) FROM PUBLIC;
