-- Catalog inspection only. HBA options, raw errors, file paths and password verifiers are excluded.
WITH db AS (
 SELECT oid, datname, datallowconn, datistemplate
 FROM pg_catalog.pg_database ORDER BY oid LIMIT 129
), hba AS (
 SELECT rule_number, line_number, type, database, user_name, address, netmask,
        auth_method, coalesce(cardinality(options),0)>0 AS options_present,
        error IS NOT NULL AS has_error
 FROM pg_catalog.pg_hba_file_rules
 ORDER BY rule_number NULLS LAST, line_number LIMIT 257
)
SELECT jsonb_build_object(
 'version','PAPER_WRITER_CONNECTION_REVIEW_V1',
 'database',current_database(),
 'databaseOid',(SELECT oid::text FROM pg_catalog.pg_database WHERE datname=current_database()),
 'clusterId',(SELECT system_identifier::text FROM pg_catalog.pg_control_system()),
 'serverVersion',current_setting('server_version_num')::integer,
 'adminSuperuser',(SELECT rolsuper FROM pg_catalog.pg_roles WHERE rolname=current_user),
 'writerLoginEnabled',(SELECT rolcanlogin FROM pg_catalog.pg_roles WHERE rolname='marketbrain_paper_review_writer'),
 'passwordEncryption',current_setting('password_encryption'),
 'ssl',current_setting('ssl'),
 'listenAddresses',current_setting('listen_addresses'),
 'serverPort',current_setting('port')::integer,
 'configurationLoadedAt',pg_catalog.pg_conf_load_time(),
 'hbaEvidence','CURRENT_FILE_NOT_PROOF_OF_LOADED_RULES_OR_CLIENT_ROUTE',
 'databases',coalesce((SELECT jsonb_agg(jsonb_build_object(
    'name',datname,'oid',oid::text,'allowsConnections',datallowconn,'template',datistemplate,
    'writerConnect',pg_catalog.has_database_privilege('marketbrain_paper_review_writer',oid,'CONNECT'),
    'writerCreate',pg_catalog.has_database_privilege('marketbrain_paper_review_writer',oid,'CREATE'),
    'writerTemp',pg_catalog.has_database_privilege('marketbrain_paper_review_writer',oid,'TEMP')) ORDER BY oid) FROM db),'[]'::jsonb),
 'hbaRules',coalesce((SELECT jsonb_agg(jsonb_build_object(
    'ruleNumber',rule_number,'lineNumber',line_number,'type',type,'databases',database,
    'users',user_name,'address',address,'netmask',netmask,'authMethod',auth_method,
    'optionsPresent',options_present,'hasError',has_error) ORDER BY rule_number NULLS LAST,line_number) FROM hba),'[]'::jsonb),
 'databaseWritesPerformed',false,'credentialsSaved',false,
 'applicationWriterActivated',false,'actionExecutionEnabled',false);
