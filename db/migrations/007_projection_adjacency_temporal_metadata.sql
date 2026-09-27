-- Preserve edge time axes in bounded projection adjacency results.
-- Existing migration 003 remains immutable; this replacement is roll-forward safe.

BEGIN;

CREATE OR REPLACE FUNCTION rh_projection_adjacency_batch(
    p_projection_id uuid,
    p_visibility_scope rh_visibility_scope,
    p_edge_kind text,
    p_direction text,
    p_entity_ids uuid[],
    p_edge_limit integer
)
RETURNS TABLE (edges jsonb, truncated boolean)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    IF p_projection_id IS NULL
       OR p_visibility_scope IS NULL
       OR p_edge_kind IS NULL
       OR length(btrim(p_edge_kind)) NOT BETWEEN 1 AND 64
       OR p_direction IS NULL
       OR p_direction NOT IN ('outgoing', 'incoming')
       OR p_entity_ids IS NULL
       OR cardinality(p_entity_ids) NOT BETWEEN 1 AND 256
       OR p_edge_limit IS NULL
       OR p_edge_limit NOT BETWEEN 1 AND 10000 THEN
        RAISE EXCEPTION 'projection adjacency request is malformed or exceeds its bound'
            USING ERRCODE = '22023';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM graph_projection AS gp
        WHERE gp.id = p_projection_id
          AND gp.visibility_scope = p_visibility_scope
    ) THEN
        RETURN QUERY SELECT '[]'::jsonb, false;
        RETURN;
    END IF;

    IF p_direction = 'outgoing' THEN
        RETURN QUERY
        WITH candidates AS MATERIALIZED (
            SELECT pm.from_entity_id, pm.to_entity_id,
                   pm.valid_from, pm.valid_to, pm.known_at
            FROM projection_membership AS pm
            WHERE pm.projection_id = p_projection_id
              AND pm.edge_kind = p_edge_kind
              AND pm.from_entity_id = ANY (p_entity_ids)
            ORDER BY pm.from_entity_id, pm.to_entity_id
            LIMIT p_edge_limit + 1
        ), bounded AS (
            SELECT candidates.from_entity_id, candidates.to_entity_id,
                   candidates.valid_from, candidates.valid_to, candidates.known_at
            FROM candidates
            ORDER BY candidates.from_entity_id, candidates.to_entity_id
            LIMIT p_edge_limit
        )
        SELECT COALESCE(
                   jsonb_agg(jsonb_build_object(
                                 'from', bounded.from_entity_id,
                                 'to', bounded.to_entity_id,
                                 'valid_from', bounded.valid_from,
                                 'valid_to', bounded.valid_to,
                                 'known_at', bounded.known_at
                             )
                             ORDER BY bounded.from_entity_id, bounded.to_entity_id),
                   '[]'::jsonb
               ),
               (SELECT count(*) > p_edge_limit FROM candidates)
        FROM bounded;
    ELSE
        RETURN QUERY
        WITH candidates AS MATERIALIZED (
            SELECT pm.from_entity_id, pm.to_entity_id,
                   pm.valid_from, pm.valid_to, pm.known_at
            FROM projection_membership AS pm
            WHERE pm.projection_id = p_projection_id
              AND pm.edge_kind = p_edge_kind
              AND pm.to_entity_id = ANY (p_entity_ids)
            ORDER BY pm.to_entity_id, pm.from_entity_id
            LIMIT p_edge_limit + 1
        ), bounded AS (
            SELECT candidates.from_entity_id, candidates.to_entity_id,
                   candidates.valid_from, candidates.valid_to, candidates.known_at
            FROM candidates
            ORDER BY candidates.to_entity_id, candidates.from_entity_id
            LIMIT p_edge_limit
        )
        SELECT COALESCE(
                   jsonb_agg(jsonb_build_object(
                                 'from', bounded.from_entity_id,
                                 'to', bounded.to_entity_id,
                                 'valid_from', bounded.valid_from,
                                 'valid_to', bounded.valid_to,
                                 'known_at', bounded.known_at
                             )
                             ORDER BY bounded.to_entity_id, bounded.from_entity_id),
                   '[]'::jsonb
               ),
               (SELECT count(*) > p_edge_limit FROM candidates)
        FROM bounded;
    END IF;
END;
$$;

COMMIT;
