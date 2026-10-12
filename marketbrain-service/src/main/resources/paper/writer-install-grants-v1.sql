-- Apply only after approved plan guard, inside the same transaction.
DO $mb$
DECLARE p jsonb := current_setting('marketbrain.writer_approved_plan')::jsonb; r jsonb;
BEGIN
 -- Preserve effective TEMP for every pre-existing role; operator approves this exact list.
 FOR r IN SELECT value FROM jsonb_array_elements(p->'roles') LOOP
   IF (r->>'temp')::boolean AND NOT (r->>'explicitTemp')::boolean THEN
     EXECUTE format('GRANT TEMPORARY ON DATABASE %I TO %I',current_database(),r->>'roleName');
   END IF;
 END LOOP;
 EXECUTE format('REVOKE TEMPORARY ON DATABASE %I FROM PUBLIC RESTRICT',current_database());
END $mb$;
CREATE ROLE marketbrain_paper_review_writer NOLOGIN PASSWORD NULL NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS;
CREATE ROLE marketbrain_paper_review_helper NOLOGIN PASSWORD NULL NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS;
COMMENT ON ROLE marketbrain_paper_review_writer IS 'MarketBrain staged writer v1 __PLAN_HASH__';
COMMENT ON ROLE marketbrain_paper_review_helper IS 'MarketBrain staged helper v1 __PLAN_HASH__';
DO $mb$ BEGIN EXECUTE format('GRANT CONNECT ON DATABASE %I TO marketbrain_paper_review_writer',current_database()); END $mb$;
GRANT USAGE ON SCHEMA public TO marketbrain_paper_review_writer,marketbrain_paper_review_helper;
GRANT SELECT ON public.paper_approval_proposal,public.paper_approval_token,public.telegram_binding,
 public.paper_portfolio,public.paper_ledger_account,public.paper_ledger_command,public.paper_ledger_position,public.instrument
 TO marketbrain_paper_review_writer,marketbrain_paper_review_helper;
GRANT UPDATE(id) ON public.paper_portfolio TO marketbrain_paper_review_helper;
GRANT UPDATE(portfolio_id) ON public.paper_ledger_account TO marketbrain_paper_review_helper;
GRANT UPDATE(binding_key) ON public.telegram_binding TO marketbrain_paper_review_helper;
GRANT UPDATE(id,decided_token,callback_id,receipt) ON public.paper_approval_proposal TO marketbrain_paper_review_helper;
