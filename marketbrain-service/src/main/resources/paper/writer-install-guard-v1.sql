DO $mb$
DECLARE v_plan jsonb;
BEGIN
 IF NOT pg_catalog.pg_try_advisory_xact_lock(814012031) THEN RAISE EXCEPTION 'Writer installer already active'; END IF;
 v_plan := (__PLAN_QUERY__);
 IF md5(v_plan::text) <> '__PLAN_HASH__' THEN RAISE EXCEPTION 'Approved catalog plan changed'; END IF;
 IF (v_plan->>'adminSuperuser')::boolean IS DISTINCT FROM true OR (v_plan->>'serverVersion')::int NOT BETWEEN 180000 AND 189999
    OR (v_plan->>'schemaExists')::boolean IS DISTINCT FROM true THEN RAISE EXCEPTION 'PostgreSQL 18 administrator and public schema required'; END IF;
 IF (v_plan->>'roleCount')::int>128 OR (v_plan->>'membershipCount')::int>256 OR (v_plan->>'relationCount')::int>512
    OR (v_plan->>'requiredTables')::int<>12 THEN RAISE EXCEPTION 'Catalog scope not supported'; END IF;
 IF (v_plan->>'roleCollisions')::int<>0 OR (v_plan->>'functionCollisions')::int<>0
    OR (v_plan->>'publicCreateSchemas')::int<>0 OR (v_plan->>'publicDefiners')::int<>0
    OR (v_plan->>'defaultFunctionAcls')::int<>0 OR (v_plan->>'publicDatabaseCreate')::boolean
    THEN RAISE EXCEPTION 'Unreviewed permissions or object collision'; END IF;
 PERFORM pg_catalog.set_config('marketbrain.writer_approved_plan',v_plan::text,true);
END $mb$;
