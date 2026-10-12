-- Read-only catalog plan. Never select application data or password hashes.
SELECT jsonb_build_object(
 'version','PAPER_WRITER_INSTALL_PLAN_V1',
 'database',d.datname,'databaseOid',d.oid::text,
 'clusterId',(SELECT system_identifier::text FROM pg_catalog.pg_control_system()),
 'databaseAcl',coalesce(d.datacl::text,''),'admin',current_user,
 'adminSuperuser',(SELECT rolsuper FROM pg_catalog.pg_roles WHERE rolname=current_user),
 'serverVersion',current_setting('server_version_num')::int,
 'publicTemp',pg_catalog.has_database_privilege('public',d.oid,'TEMP'),
 'publicDatabaseCreate',pg_catalog.has_database_privilege('public',d.oid,'CREATE'),
 'schemaExists',EXISTS(SELECT 1 FROM pg_catalog.pg_namespace WHERE nspname='public'),
 'roleCount',(SELECT count(*) FROM pg_catalog.pg_roles),
 'roles',coalesce((SELECT jsonb_agg(to_jsonb(r) ORDER BY r."roleOid") FROM (
   SELECT oid AS "roleOid",rolname AS "roleName",rolcanlogin AS "login",rolsuper AS "superuser",
     rolcreaterole AS "createRole",rolcreatedb AS "createDatabase",rolinherit AS "inherit",
     rolreplication AS "replication",rolbypassrls AS "bypassRls",
     pg_catalog.has_database_privilege(oid,d.oid,'TEMP') AS "temp",
     EXISTS(SELECT 1 FROM pg_catalog.aclexplode(coalesce(d.datacl,pg_catalog.acldefault('d',d.datdba))) a
            WHERE a.grantee=pg_roles.oid AND a.privilege_type='TEMPORARY') AS "explicitTemp"
   FROM pg_catalog.pg_roles ORDER BY oid LIMIT 129) r),'[]'::jsonb),
 'membershipCount',(SELECT count(*) FROM pg_catalog.pg_auth_members),
 'memberships',coalesce((SELECT jsonb_agg(to_jsonb(m) ORDER BY m.roleid,m.member,m.grantor) FROM (
   SELECT roleid,member,grantor,admin_option,inherit_option,set_option FROM pg_catalog.pg_auth_members ORDER BY roleid,member,grantor LIMIT 257) m),'[]'::jsonb),
 'roleCollisions',(SELECT count(*) FROM pg_catalog.pg_roles WHERE rolname IN ('marketbrain_paper_review_writer','marketbrain_paper_review_helper')),
 'functionCollisions',(SELECT count(*) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
                      WHERE n.nspname='public' AND p.proname IN ('paper_review_lock','paper_review_record')),
 'publicCreateSchemas',(SELECT count(*) FROM pg_catalog.pg_namespace n WHERE left(n.nspname,3)<>'pg_'
                        AND n.nspname<>'information_schema' AND pg_catalog.has_schema_privilege('public',n.oid,'CREATE')),
 'publicDefiners',(SELECT count(*) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
                  WHERE left(n.nspname,3)<>'pg_' AND n.nspname<>'information_schema' AND p.prosecdef
                    AND pg_catalog.has_schema_privilege('public',n.oid,'USAGE') AND pg_catalog.has_function_privilege('public',p.oid,'EXECUTE')),
 'defaultFunctionAcls',(SELECT count(*) FROM pg_catalog.pg_default_acl a WHERE a.defaclrole=(SELECT oid FROM pg_catalog.pg_roles WHERE rolname=current_user)
                       AND a.defaclobjtype='f' AND (a.defaclnamespace=0 OR a.defaclnamespace=(SELECT oid FROM pg_catalog.pg_namespace WHERE nspname='public'))),
 'requiredTables',(SELECT count(*) FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
                   WHERE n.nspname='public' AND c.relkind='r' AND NOT c.relrowsecurity AND NOT c.relforcerowsecurity
                     AND c.relname IN ('paper_approval_proposal','paper_approval_token','telegram_binding','paper_portfolio',
                     'paper_ledger_account','paper_ledger_command','paper_ledger_position','instrument',
                     'paper_approval_delivery','paper_approval_key_binding','paper_ledger_order','paper_ledger_fill')),
 'relationCount',(SELECT count(*) FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
                  WHERE left(n.nspname,3)<>'pg_' AND n.nspname<>'information_schema' AND c.relkind IN ('r','p','v','m','f')),
 'relationCatalogHash',(SELECT md5(coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.oid)::text,'')) FROM (
   SELECT c.oid,c.relname,c.relowner,c.relacl,c.relkind,c.relrowsecurity,c.relforcerowsecurity,n.nspname,
     (SELECT jsonb_agg(jsonb_build_array(a.attnum,a.attname,a.atttypid,a.attacl) ORDER BY a.attnum)
      FROM pg_catalog.pg_attribute a WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped) AS columns
   FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
   WHERE left(n.nspname,3)<>'pg_' AND n.nspname<>'information_schema' AND c.relkind IN ('r','p','v','m','f') ORDER BY c.oid LIMIT 513) t)
) AS plan
FROM pg_catalog.pg_database d WHERE d.datname=current_database()
