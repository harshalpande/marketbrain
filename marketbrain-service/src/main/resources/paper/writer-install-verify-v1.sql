DO $mb$
DECLARE p jsonb := __APPROVED_PLAN__; v_role jsonb; v_relation record; v_column record; f record; who text; allowed boolean;
        reader_tables text[] := ARRAY['paper_approval_proposal','paper_approval_token','telegram_binding','paper_portfolio',
                                      'paper_ledger_account','paper_ledger_command','paper_ledger_position','instrument'];
BEGIN
 IF current_database() IS DISTINCT FROM p->>'database' OR
    (SELECT oid::text FROM pg_catalog.pg_database WHERE datname=current_database()) IS DISTINCT FROM p->>'databaseOid' OR
    (SELECT system_identifier::text FROM pg_catalog.pg_control_system()) IS DISTINCT FROM p->>'clusterId'
    THEN RAISE EXCEPTION 'Verification target mismatch'; END IF;
 IF (SELECT count(*) FROM pg_catalog.pg_roles WHERE rolname IN ('marketbrain_paper_review_writer','marketbrain_paper_review_helper')
     AND NOT rolcanlogin AND NOT rolsuper AND NOT rolcreatedb AND NOT rolcreaterole AND NOT rolinherit AND NOT rolreplication AND NOT rolbypassrls)<>2
    THEN RAISE EXCEPTION 'Staged roles must remain restricted NOLOGIN'; END IF;
 IF EXISTS(SELECT 1 FROM pg_catalog.pg_auth_members m JOIN pg_catalog.pg_roles r ON r.oid=m.member OR r.oid=m.roleid
           WHERE r.rolname IN ('marketbrain_paper_review_writer','marketbrain_paper_review_helper'))
    THEN RAISE EXCEPTION 'Unexpected role membership'; END IF;
 IF pg_catalog.shobj_description((SELECT oid FROM pg_catalog.pg_roles WHERE rolname='marketbrain_paper_review_writer'),'pg_authid')
       IS DISTINCT FROM 'MarketBrain staged writer v1 __PLAN_HASH__' OR
    pg_catalog.shobj_description((SELECT oid FROM pg_catalog.pg_roles WHERE rolname='marketbrain_paper_review_helper'),'pg_authid')
       IS DISTINCT FROM 'MarketBrain staged helper v1 __PLAN_HASH__' THEN RAISE EXCEPTION 'Installation identity mismatch'; END IF;
 IF pg_catalog.has_database_privilege('public',current_database(),'TEMP') THEN RAISE EXCEPTION 'PUBLIC TEMP still present'; END IF;
 IF NOT pg_catalog.has_database_privilege('marketbrain_paper_review_writer',current_database(),'CONNECT') THEN RAISE EXCEPTION 'Writer CONNECT missing'; END IF;
 IF (SELECT count(*) FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
     WHERE n.nspname='public' AND c.relkind='r' AND NOT c.relrowsecurity AND NOT c.relforcerowsecurity
       AND c.relname IN ('paper_approval_proposal','paper_approval_token','telegram_binding','paper_portfolio',
        'paper_ledger_account','paper_ledger_command','paper_ledger_position','instrument',
        'paper_approval_delivery','paper_approval_key_binding','paper_ledger_order','paper_ledger_fill'))<>12
    THEN RAISE EXCEPTION 'Required tables changed'; END IF;
 IF (SELECT count(*) FROM pg_catalog.pg_roles)<>(p->>'roleCount')::int+2 THEN RAISE EXCEPTION 'Concurrent role inventory change'; END IF;
 FOR v_role IN SELECT value FROM jsonb_array_elements(p->'roles') LOOP
   IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_roles x WHERE x.oid=(v_role->>'roleOid')::oid AND x.rolname=v_role->>'roleName'
     AND x.rolcanlogin=(v_role->>'login')::boolean AND x.rolsuper=(v_role->>'superuser')::boolean
     AND x.rolcreaterole=(v_role->>'createRole')::boolean AND x.rolcreatedb=(v_role->>'createDatabase')::boolean
     AND x.rolinherit=(v_role->>'inherit')::boolean AND x.rolreplication=(v_role->>'replication')::boolean AND x.rolbypassrls=(v_role->>'bypassRls')::boolean)
      THEN RAISE EXCEPTION 'Existing role changed'; END IF;
   IF pg_catalog.has_database_privilege((v_role->>'roleOid')::oid,current_database(),'TEMP') IS DISTINCT FROM (v_role->>'temp')::boolean
      THEN RAISE EXCEPTION 'Existing TEMP access changed'; END IF;
 END LOOP;
 IF coalesce((SELECT jsonb_agg(to_jsonb(m) ORDER BY m.roleid,m.member,m.grantor) FROM
    (SELECT roleid,member,grantor,admin_option,inherit_option,set_option FROM pg_catalog.pg_auth_members) m),'[]'::jsonb)
    IS DISTINCT FROM p->'memberships' THEN RAISE EXCEPTION 'Role memberships changed'; END IF;
 IF (SELECT count(*) FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
     WHERE left(n.nspname,3)<>'pg_' AND n.nspname<>'information_schema' AND c.relkind IN ('r','p','v','m','f'))>512
    THEN RAISE EXCEPTION 'Relation bound exceeded'; END IF;
 FOREACH who IN ARRAY ARRAY['marketbrain_paper_review_writer','marketbrain_paper_review_helper'] LOOP
   IF pg_catalog.has_database_privilege(who,current_database(),'CREATE,TEMP') OR
      EXISTS(SELECT 1 FROM pg_catalog.pg_namespace n WHERE left(n.nspname,3)<>'pg_' AND n.nspname<>'information_schema' AND pg_catalog.has_schema_privilege(who,n.oid,'CREATE'))
      THEN RAISE EXCEPTION 'DDL authority leaked'; END IF;
   IF NOT pg_catalog.has_schema_privilege(who,'public','USAGE') THEN RAISE EXCEPTION 'Schema usage missing'; END IF;
   FOR v_relation IN SELECT c.oid,c.relname,c.relowner,n.nspname FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
            WHERE left(n.nspname,3)<>'pg_' AND n.nspname<>'information_schema' AND c.relkind IN ('r','p','v','m','f') LOOP
     allowed := v_relation.nspname='public' AND v_relation.relname=ANY(reader_tables);
     IF pg_catalog.has_any_column_privilege(who,v_relation.oid,'SELECT') IS DISTINCT FROM allowed OR
        (allowed AND NOT pg_catalog.has_table_privilege(who,v_relation.oid,'SELECT')) OR pg_catalog.pg_has_role(who,v_relation.relowner,'USAGE')
        THEN RAISE EXCEPTION 'Unexpected read or ownership authority'; END IF;
     IF pg_catalog.has_table_privilege(who,v_relation.oid,'INSERT,DELETE,TRUNCATE,TRIGGER,REFERENCES,MAINTAIN') OR
        pg_catalog.has_any_column_privilege(who,v_relation.oid,'INSERT') OR pg_catalog.has_any_column_privilege(who,v_relation.oid,'REFERENCES')
        THEN RAISE EXCEPTION 'Write authority leaked'; END IF;
     FOR v_column IN SELECT attnum,attname FROM pg_catalog.pg_attribute WHERE attrelid=v_relation.oid AND attnum>0 AND NOT attisdropped LOOP
       allowed := who='marketbrain_paper_review_helper' AND v_relation.nspname='public' AND
         ((v_relation.relname='paper_portfolio' AND v_column.attname='id') OR (v_relation.relname='paper_ledger_account' AND v_column.attname='portfolio_id') OR
          (v_relation.relname='telegram_binding' AND v_column.attname='binding_key') OR (v_relation.relname='paper_approval_proposal' AND v_column.attname IN ('id','decided_token','callback_id','receipt')));
       IF pg_catalog.has_column_privilege(who,v_relation.oid,v_column.attnum,'UPDATE') IS DISTINCT FROM allowed
          THEN RAISE EXCEPTION 'Column mutation boundary mismatch'; END IF;
     END LOOP;
   END LOOP;
 END LOOP;
 IF (SELECT count(*) FROM pg_catalog.pg_proc x JOIN pg_catalog.pg_namespace n ON n.oid=x.pronamespace
     WHERE n.nspname='public' AND x.proname IN ('paper_review_lock','paper_review_record'))<>2 THEN RAISE EXCEPTION 'Wrong function count'; END IF;
 IF to_regprocedure('public.paper_review_lock(text,bigint,bigint)') IS NULL OR
    to_regprocedure('public.paper_review_record(text,bigint,bigint,text,text)') IS NULL THEN RAISE EXCEPTION 'Wrong function signatures'; END IF;
 FOR f IN SELECT x.* FROM pg_catalog.pg_proc x JOIN pg_catalog.pg_namespace n ON n.oid=x.pronamespace
          WHERE n.nspname='public' AND x.proname IN ('paper_review_lock','paper_review_record') LOOP
   IF NOT f.prosecdef OR f.prolang<>(SELECT oid FROM pg_catalog.pg_language WHERE lanname='plpgsql') OR
      f.prorettype<>'boolean'::regtype OR f.proacl IS NULL OR
      f.proowner<>(SELECT oid FROM pg_catalog.pg_roles WHERE rolname='marketbrain_paper_review_helper') OR
      f.proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog, public, pg_temp'] OR
      NOT pg_catalog.has_function_privilege('marketbrain_paper_review_writer',f.oid,'EXECUTE') OR
      pg_catalog.has_function_privilege('public',f.oid,'EXECUTE') OR
      md5(f.prosrc) IS DISTINCT FROM CASE f.proname WHEN 'paper_review_lock' THEN '__LOCK_HASH__' ELSE '__RECORD_HASH__' END OR
      EXISTS(SELECT 1 FROM pg_catalog.aclexplode(f.proacl) x WHERE x.is_grantable OR x.grantee NOT IN
              (SELECT oid FROM pg_catalog.pg_roles WHERE rolname IN ('marketbrain_paper_review_writer','marketbrain_paper_review_helper')))
      THEN RAISE EXCEPTION 'Privileged function boundary mismatch'; END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM pg_catalog.pg_proc x JOIN pg_catalog.pg_namespace n ON n.oid=x.pronamespace
     WHERE left(n.nspname,3)<>'pg_' AND n.nspname<>'information_schema' AND x.prosecdef
       AND pg_catalog.has_schema_privilege('public',n.oid,'USAGE') AND pg_catalog.has_function_privilege('public',x.oid,'EXECUTE'))
    THEN RAISE EXCEPTION 'PUBLIC privileged function appeared'; END IF;
END $mb$;
