-- Expand a bounded graph neighborhood inside PostgreSQL so the worker uses
-- one network round trip per query instead of one per graph depth.

BEGIN;

CREATE FUNCTION rh_projection_adjacency_walk(
    p_projection_id uuid,
    p_visibility_scope rh_visibility_scope,
    p_edge_kind text,
    p_direction text,
    p_subject_id uuid,
    p_max_nodes integer,
    p_max_depth integer,
    p_edge_limit integer
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_frontier uuid[] := ARRAY[p_subject_id];
    v_seen uuid[] := ARRAY[p_subject_id];
    v_candidates uuid[];
    v_next uuid[];
    v_edges jsonb := '[]'::jsonb;
    v_batch_edges jsonb;
    v_batch_truncated boolean;
    v_projection_available boolean;
    v_depth integer := 0;
    v_remaining_edges integer;
    v_remaining_nodes integer;
    v_add_limit integer;
    v_candidate uuid;
    v_truncated boolean := false;
BEGIN
    IF p_projection_id IS NULL
       OR p_visibility_scope IS NULL
       OR p_edge_kind IS NULL
       OR length(btrim(p_edge_kind)) NOT BETWEEN 1 AND 64
       OR p_direction IS NULL
       OR p_direction NOT IN ('outgoing', 'incoming')
       OR p_subject_id IS NULL
       OR p_max_nodes IS NULL
       OR p_max_nodes NOT BETWEEN 1 AND 1000
       OR p_max_depth IS NULL
       OR p_max_depth NOT BETWEEN 1 AND 1000
       OR p_edge_limit IS NULL
       OR p_edge_limit NOT BETWEEN 1 AND 10000 THEN
        RAISE EXCEPTION 'projection adjacency walk is malformed or exceeds its bound'
            USING ERRCODE = '22023';
    END IF;

    SELECT EXISTS (
        SELECT 1
        FROM graph_projection AS gp
        WHERE gp.id = p_projection_id
          AND gp.visibility_scope = p_visibility_scope
          AND gp.completeness = 'complete'
    ) INTO v_projection_available;
    IF NOT v_projection_available THEN
        RETURN jsonb_build_object(
            'edges', '[]'::jsonb,
            'truncated', false,
            'projection_available', false
        );
    END IF;

    WHILE cardinality(v_frontier) > 0 AND v_depth <= p_max_depth LOOP
        v_remaining_edges := p_edge_limit - jsonb_array_length(v_edges);
        IF v_remaining_edges <= 0 THEN
            -- Probe one row so an exact edge-limit result is not called
            -- truncated unless more visible adjacency actually exists.
            SELECT adjacency.edges, adjacency.truncated
              INTO v_batch_edges, v_batch_truncated
            FROM rh_projection_adjacency_batch(
                p_projection_id, p_visibility_scope, p_edge_kind, p_direction,
                v_frontier, 1
            ) AS adjacency;
            v_truncated := jsonb_array_length(v_batch_edges) > 0 OR v_batch_truncated;
            EXIT;
        END IF;

        SELECT adjacency.edges, adjacency.truncated
          INTO v_batch_edges, v_batch_truncated
        FROM rh_projection_adjacency_batch(
            p_projection_id, p_visibility_scope, p_edge_kind, p_direction,
            v_frontier, v_remaining_edges
        ) AS adjacency;
        v_edges := v_edges || v_batch_edges;
        v_truncated := v_truncated OR v_batch_truncated;

        SELECT COALESCE(array_agg(candidates.entity_id ORDER BY candidates.entity_id), '{}'::uuid[])
          INTO v_candidates
        FROM (
            SELECT DISTINCT CASE p_direction
                WHEN 'outgoing' THEN (edge.value->>'to')::uuid
                ELSE (edge.value->>'from')::uuid
            END AS entity_id
            FROM jsonb_array_elements(v_batch_edges) AS edge(value)
        ) AS candidates
        WHERE NOT candidates.entity_id = ANY(v_seen);

        IF v_depth >= p_max_depth AND cardinality(v_candidates) > 0 THEN
            -- Match the in-memory evaluator: edges beyond the requested depth
            -- are retained as boundary evidence, and any unseen endpoint
            -- makes the result explicitly truncated.
            v_truncated := true;
        END IF;

        v_remaining_nodes := p_max_nodes - (cardinality(v_seen) - 1);
        v_add_limit := greatest(0, v_remaining_nodes) + 1;
        IF cardinality(v_candidates) > v_add_limit THEN
            v_truncated := true;
        END IF;

        v_next := '{}'::uuid[];
        FOREACH v_candidate IN ARRAY v_candidates[1:v_add_limit] LOOP
            v_seen := array_append(v_seen, v_candidate);
            IF cardinality(v_seen) - 1 <= p_max_nodes THEN
                v_next := array_append(v_next, v_candidate);
            ELSE
                -- Keep one probe endpoint so the local evaluator can preserve
                -- the usual max-node truncation semantics.
                v_truncated := true;
            END IF;
        END LOOP;

        EXIT WHEN v_batch_truncated
            OR cardinality(v_seen) - 1 > p_max_nodes
            OR v_depth >= p_max_depth;
        v_frontier := v_next;
        v_depth := v_depth + 1;
    END LOOP;

    SELECT COALESCE(jsonb_agg(edge.value ORDER BY edge.ordinality), '[]'::jsonb)
      INTO v_edges
    FROM jsonb_array_elements(v_edges) WITH ORDINALITY AS edge(value, ordinality)
    WHERE (edge.value->>'from')::uuid = ANY(v_seen)
      AND (edge.value->>'to')::uuid = ANY(v_seen);

    RETURN jsonb_build_object(
        'edges', v_edges,
        'truncated', v_truncated,
        'projection_available', true
    );
END;
$$;

COMMIT;
