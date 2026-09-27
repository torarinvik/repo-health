-- Bind projection-backed graph requests to the graph-query job's visibility.
-- A worker reads the immutable descriptor later, so its projection scope must
-- already match the scope under which the result will be stored and published.

BEGIN;

CREATE OR REPLACE FUNCTION rh_enqueue_graph_query_job(
    p_job_id uuid,
    p_visibility_scope rh_visibility_scope,
    p_request jsonb,
    p_priority integer,
    p_next_attempt_at timestamptz,
    p_created_at timestamptz
) RETURNS boolean
LANGUAGE plpgsql
AS $$
DECLARE
    v_existing job%ROWTYPE;
    v_projection jsonb;
BEGIN
    IF p_request IS NULL OR jsonb_typeof(p_request) IS DISTINCT FROM 'object'
       OR p_request->>'schema' IS DISTINCT FROM 'rh-query-input/1'
       OR jsonb_typeof(p_request->'ids') IS DISTINCT FROM 'array'
       OR pg_column_size(p_request) > 1048576 THEN
        RAISE EXCEPTION 'graph query request is malformed or exceeds the bounded payload limit';
    END IF;

    v_projection := p_request #> '{graph,projection}';
    IF v_projection IS NOT NULL THEN
        IF jsonb_typeof(p_request->'graph') IS DISTINCT FROM 'object'
           OR jsonb_typeof(v_projection) IS DISTINCT FROM 'object'
           OR COALESCE(v_projection->>'id', '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
           OR COALESCE(v_projection->>'subject_entity_id', '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
           OR length(btrim(COALESCE(v_projection->>'edge_kind', ''))) NOT BETWEEN 1 AND 64
           OR v_projection->>'visibility_scope' IS DISTINCT FROM p_visibility_scope::text THEN
            RAISE EXCEPTION 'projection query descriptor is malformed or crosses job visibility scope';
        END IF;
    END IF;

    IF p_created_at > p_next_attempt_at THEN
        RAISE EXCEPTION 'graph query job cannot be scheduled before its creation time';
    END IF;

    SELECT * INTO v_existing FROM job WHERE id = p_job_id FOR UPDATE;
    IF FOUND THEN
        IF v_existing.source_instance_id IS NOT NULL
           OR v_existing.kind IS DISTINCT FROM 'graph_query'
           OR v_existing.visibility_scope IS DISTINCT FROM p_visibility_scope
           OR v_existing.priority IS DISTINCT FROM p_priority
           OR v_existing.next_attempt_at IS DISTINCT FROM p_next_attempt_at
           OR v_existing.created_at IS DISTINCT FROM p_created_at
           OR NOT EXISTS (
               SELECT 1 FROM graph_query_job AS g
               WHERE g.job_id = p_job_id AND g.request = p_request
           ) THEN
            RAISE EXCEPTION 'graph query job identity is already registered with different immutable metadata';
        END IF;
        RETURN false;
    END IF;

    INSERT INTO job (
        id, source_instance_id, kind, visibility_scope, state, priority,
        next_attempt_at, created_at, input_manifest
    ) VALUES (
        p_job_id, NULL, 'graph_query', p_visibility_scope, 'queued', p_priority,
        p_next_attempt_at, p_created_at,
        jsonb_build_object('schema', 'rh-graph-query-job/1', 'job_id', p_job_id::text)
    );
    INSERT INTO graph_query_job (job_id, request) VALUES (p_job_id, p_request);
    RETURN true;
END;
$$;

COMMIT;
