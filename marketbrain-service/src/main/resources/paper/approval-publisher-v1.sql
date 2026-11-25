-- Candidate only, not a migration. Install atomically; replace reviewed schema/policy placeholders.
-- Functions belong to a NOLOGIN non-owner helper, never the publisher login. PUBLIC gets no execution.
CREATE FUNCTION __SCHEMA__.paper_publish_enqueue(p_payload text,p_policy text,p_accept text,p_reject text,p_sealed text,p_now timestamptz)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,__SCHEMA__,pg_temp AS $$
DECLARE p jsonb; a jsonb; old_payload text; old_state text; v_revision bigint; v_cash bigint; v_reserved bigint;
BEGIN
 IF p_payload IS NULL OR octet_length(p_payload)>16384 OR p_policy IS NULL OR octet_length(p_policy)>4096
    OR p_sealed IS NULL OR octet_length(p_sealed)>4096 OR octet_length(p_sealed)<40 OR p_now IS NULL
    OR p_accept IS NULL OR p_reject IS NULL OR p_accept !~ '^[a-f0-9]{64}$' OR p_reject !~ '^[a-f0-9]{64}$'
    OR p_accept=p_reject THEN RAISE EXCEPTION 'Invalid publication'; END IF;
 p:=p_payload::jsonb; a:=p->'terms';
 IF p_policy::jsonb IS DISTINCT FROM '__POLICY_JSON__'::jsonb OR NOT COALESCE(
    p->>'id' ~ '^PAYTM_TEST_[a-f0-9]{32}_(ACCEPT|REJECT|EXPIRE)$'
    AND p->>'policyId'='PAPER_PAYTM_TEST_100S_V1' AND a->>'approvalId'=p->>'id' AND a->>'orderId'=p->>'id'
    AND a->>'side'='BUY' AND (a->>'quantity')::bigint=1 AND (a->>'feeBudgetPaise')::bigint=0
    AND (a->>'referencePaise')::bigint BETWEEN 1 AND 500000
    AND (a->>'zoneMinPaise')::bigint BETWEEN 1 AND (a->>'referencePaise')::bigint
    AND (a->>'zoneMaxPaise')::bigint BETWEEN (a->>'referencePaise')::bigint AND 500000
    AND (a->>'expiresAt')::timestamptz=(a->>'createdAt')::timestamptz+interval '100 seconds'
    AND (p->>'portfolioId')::bigint>0 AND (p->>'instrumentId')::bigint>0
    AND (p->>'expectedRevision')::bigint>=0 AND (p->>'userId')::bigint>0 AND (p->>'chatId')::bigint>0,false)
 THEN RAISE EXCEPTION 'Publication policy rejected'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p->>'id',0));
 PERFORM 1 FROM __SCHEMA__.telegram_binding WHERE binding_key='PRIMARY' AND active
    AND telegram_user_id=(p->>'userId')::bigint AND telegram_chat_id=(p->>'chatId')::bigint FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Unauthorized binding' USING ERRCODE='42501'; END IF;
 SELECT q.payload,d.state INTO old_payload,old_state FROM __SCHEMA__.paper_approval_proposal q
    JOIN __SCHEMA__.paper_approval_delivery d ON d.proposal_id=q.id WHERE q.id=p->>'id';
 IF FOUND THEN
    IF old_payload IS DISTINCT FROM p_payload THEN RAISE EXCEPTION 'Publication identity conflict'; END IF;
    RETURN old_state;
 END IF;
 IF p_now<(a->>'createdAt')::timestamptz OR p_now>=(a->>'expiresAt')::timestamptz THEN RAISE EXCEPTION 'Publication expired'; END IF;
 PERFORM 1 FROM __SCHEMA__.paper_portfolio WHERE id=(p->>'portfolioId')::bigint AND active AND execution_mode='PAPER' FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Paper account absent'; END IF;
 SELECT revision,cash,reserved INTO v_revision,v_cash,v_reserved FROM __SCHEMA__.paper_ledger_account
    WHERE portfolio_id=(p->>'portfolioId')::bigint FOR UPDATE;
 IF NOT FOUND OR v_revision IS DISTINCT FROM (p->>'expectedRevision')::bigint OR v_cash<v_reserved
    OR v_reserved<0 OR v_cash-v_reserved<(a->>'zoneMaxPaise')::bigint THEN RAISE EXCEPTION 'Account changed'; END IF;
 PERFORM 1 FROM __SCHEMA__.paper_portfolio WHERE id=(p->>'portfolioId')::bigint AND current_cash*100=v_cash;
 IF NOT FOUND THEN RAISE EXCEPTION 'Account inconsistent'; END IF;
 PERFORM 1 FROM __SCHEMA__.instrument WHERE id=(p->>'instrumentId')::bigint AND active AND symbol=a->>'symbol';
 IF NOT FOUND THEN RAISE EXCEPTION 'Instrument changed'; END IF;
 INSERT INTO __SCHEMA__.paper_approval_proposal(id,portfolio_id,instrument_id,recipient_hash,expected_revision,payload,payload_hash,policy_hash)
 VALUES(p->>'id',(p->>'portfolioId')::bigint,(p->>'instrumentId')::bigint,
    encode(sha256(convert_to((p->>'userId')||':'||(p->>'chatId'),'UTF8')),'hex'),v_revision,p_payload,
    encode(sha256(convert_to(p_payload,'UTF8')),'hex'),encode(sha256(convert_to(p_policy,'UTF8')),'hex'));
 INSERT INTO __SCHEMA__.paper_approval_token VALUES(p_accept,p->>'id','ACCEPT'),(p_reject,p->>'id','REJECT');
 INSERT INTO __SCHEMA__.paper_approval_delivery(proposal_id,encrypted_tokens,state,created_at) VALUES(p->>'id',p_sealed,'PENDING',p_now);
 RETURN 'PENDING';
END; $$;
REVOKE ALL ON FUNCTION __SCHEMA__.paper_publish_enqueue(text,text,text,text,text,timestamptz) FROM PUBLIC;

CREATE FUNCTION __SCHEMA__.paper_publish_lock(p_id text) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,__SCHEMA__,pg_temp AS $$
BEGIN
 IF p_id IS NULL OR p_id !~ '^PAYTM_TEST_[a-f0-9]{32}_(ACCEPT|REJECT|EXPIRE)$' THEN RAISE EXCEPTION 'Invalid publication identity'; END IF;
 PERFORM 1 FROM __SCHEMA__.paper_approval_delivery WHERE proposal_id=p_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Delivery absent'; END IF; RETURN true;
END; $$;
REVOKE ALL ON FUNCTION __SCHEMA__.paper_publish_lock(text) FROM PUBLIC;

CREATE FUNCTION __SCHEMA__.paper_publish_transition(p_id text,p_state text,p_attempt text,p_now timestamptz,p_message text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,__SCHEMA__,pg_temp AS $$
DECLARE d __SCHEMA__.paper_approval_delivery%ROWTYPE; p jsonb;
BEGIN
 PERFORM __SCHEMA__.paper_publish_lock(p_id);
 SELECT * INTO d FROM __SCHEMA__.paper_approval_delivery WHERE proposal_id=p_id;
 IF p_state IS NULL OR p_now IS NULL THEN RAISE EXCEPTION 'Transition required'; END IF;
 IF p_state IN ('EXPIRED','REVOKED','KEY_BLOCKED') AND d.state='PENDING' AND p_attempt IS NULL AND p_message IS NULL THEN
    UPDATE __SCHEMA__.paper_approval_delivery SET state=p_state WHERE proposal_id=p_id; RETURN true;
 END IF;
 IF p_attempt IS NULL OR p_attempt !~ '^[a-f0-9-]{36}$' THEN RAISE EXCEPTION 'Attempt required'; END IF;
 IF p_state='SENDING' AND d.state='PENDING' AND p_message IS NULL THEN
    SELECT payload::jsonb INTO p FROM __SCHEMA__.paper_approval_proposal WHERE id=p_id;
    IF p_now<(p->'terms'->>'createdAt')::timestamptz OR p_now>=(p->'terms'->>'expiresAt')::timestamptz THEN RAISE EXCEPTION 'Delivery expired'; END IF;
    PERFORM 1 FROM __SCHEMA__.telegram_binding WHERE binding_key='PRIMARY' AND active
      AND telegram_user_id=(p->>'userId')::bigint AND telegram_chat_id=(p->>'chatId')::bigint FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Recipient revoked'; END IF;
    UPDATE __SCHEMA__.paper_approval_delivery SET state='SENDING',attempt_id=p_attempt,attempted_at=p_now WHERE proposal_id=p_id;
 ELSIF d.state='SENDING' AND d.attempt_id=p_attempt AND
    ((p_state='SENT' AND p_message ~ '^[1-9][0-9]{0,18}$') OR (p_state='UNCERTAIN' AND p_message IS NULL)) THEN
    UPDATE __SCHEMA__.paper_approval_delivery SET state=p_state,message_id=p_message WHERE proposal_id=p_id;
 ELSE RAISE EXCEPTION 'Delivery transition rejected'; END IF;
 RETURN true;
END; $$;
REVOKE ALL ON FUNCTION __SCHEMA__.paper_publish_transition(text,text,text,timestamptz,text) FROM PUBLIC;
