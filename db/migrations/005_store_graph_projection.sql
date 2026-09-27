-- Store immutable, visibility-scoped graph projections for batched queries.

BEGIN;

CREATE FUNCTION rh_store_graph_projection(p_document jsonb)
RETURNS boolean
LANGUAGE plpgsql
AS $$
DECLARE
    v_projection jsonb;
    v_edges jsonb;
    v_existing graph_projection%ROWTYPE;
    v_id uuid;
    v_kind text;
    v_scope rh_visibility_scope;
    v_input_cutoff timestamptz;
    v_as_of timestamptz;
    v_identity_revision text;
    v_mapping_revision text;
    v_completeness text;
    v_digest text;
    v_inserted boolean;
BEGIN
    IF p_document IS NULL OR jsonb_typeof(p_document) IS DISTINCT FROM 'object'
       OR p_document->>'schema' IS DISTINCT FROM 'rh-postgres-projection-input/1'
       OR jsonb_typeof(p_document->'projection') IS DISTINCT FROM 'object'
       OR jsonb_typeof(p_document->'edges') IS DISTINCT FROM 'array'
       OR pg_column_size(p_document) > 20971520
       OR jsonb_array_length(p_document->'edges') > 200000 THEN
        RAISE EXCEPTION 'graph projection document is malformed or exceeds its bound'
            USING ERRCODE = '22023';
    END IF;

    v_projection := p_document->'projection';
    v_edges := p_document->'edges';
    IF jsonb_array_length(v_edges) > 0 AND p_document->'projection'->>'completeness' = 'failed' THEN
        RAISE EXCEPTION 'failed graph projections cannot contain edges' USING ERRCODE = '22023';
    END IF;
    v_id := (v_projection->>'id')::uuid;
    v_kind := v_projection->>'projection_kind';
    v_scope := (v_projection->>'visibility_scope')::rh_visibility_scope;
    v_input_cutoff := (v_projection->>'input_cutoff')::timestamptz;
    v_as_of := (v_projection->>'as_of')::timestamptz;
    v_identity_revision := v_projection->>'identity_revision';
    v_mapping_revision := v_projection->>'mapping_revision';
    v_completeness := v_projection->>'completeness';
    v_digest := v_projection->>'manifest_digest';

    IF v_kind IS NULL OR length(btrim(v_kind)) NOT BETWEEN 1 AND 64
       OR v_identity_revision IS NULL OR length(v_identity_revision) > 256
       OR v_mapping_revision IS NULL OR length(v_mapping_revision) > 256
       OR v_completeness NOT IN ('complete', 'partial', 'truncated', 'failed')
       OR v_digest !~ '^[0-9a-f]{64}$' THEN
        RAISE EXCEPTION 'graph projection metadata is malformed' USING ERRCODE = '22023';
    END IF;

    IF EXISTS (
        SELECT 1 FROM jsonb_array_elements(v_edges) AS edge(value)
        WHERE jsonb_typeof(edge.value) IS DISTINCT FROM 'object'
           OR jsonb_typeof(edge.value->'from_entity_id') IS DISTINCT FROM 'string'
           OR jsonb_typeof(edge.value->'to_entity_id') IS DISTINCT FROM 'string'
           OR jsonb_typeof(edge.value->'edge_kind') IS DISTINCT FROM 'string'
           OR jsonb_typeof(edge.value->'known_at') IS DISTINCT FROM 'string'
           OR (edge.value ? 'valid_from' AND jsonb_typeof(edge.value->'valid_from') NOT IN ('string', 'null'))
           OR (edge.value ? 'valid_to' AND jsonb_typeof(edge.value->'valid_to') NOT IN ('string', 'null'))
    ) THEN
        RAISE EXCEPTION 'graph projection contains a malformed edge' USING ERRCODE = '22023';
    END IF;

    IF EXISTS (
        SELECT 1 FROM jsonb_to_recordset(v_edges) AS edge(
            from_entity_id uuid, to_entity_id uuid, edge_kind text,
            valid_from timestamptz, valid_to timestamptz, known_at timestamptz
        )
        WHERE edge.from_entity_id IS NULL OR edge.to_entity_id IS NULL
           OR edge.from_entity_id = edge.to_entity_id
           OR edge.edge_kind IS NULL OR length(btrim(edge.edge_kind)) NOT BETWEEN 1 AND 64
           OR edge.known_at IS NULL
           OR (edge.valid_from IS NOT NULL AND edge.valid_to IS NOT NULL AND edge.valid_to <= edge.valid_from)
    ) THEN
        RAISE EXCEPTION 'graph projection edge identity or interval is invalid' USING ERRCODE = '22023';
    END IF;

    IF EXISTS (
        SELECT 1 FROM jsonb_to_recordset(v_edges) AS edge(
            from_entity_id uuid, to_entity_id uuid, edge_kind text,
            valid_from timestamptz, valid_to timestamptz, known_at timestamptz
        ) GROUP BY edge.from_entity_id, edge.to_entity_id, edge.edge_kind HAVING count(*) > 1
    ) THEN
        RAISE EXCEPTION 'graph projection contains duplicate edges' USING ERRCODE = '22023';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM jsonb_to_recordset(v_edges) AS edge(
            from_entity_id uuid, to_entity_id uuid, edge_kind text,
            valid_from timestamptz, valid_to timestamptz, known_at timestamptz
        )
        JOIN entity AS source_entity ON source_entity.id = edge.from_entity_id
        JOIN entity AS target_entity ON target_entity.id = edge.to_entity_id
        WHERE source_entity.visibility_scope <> v_scope OR target_entity.visibility_scope <> v_scope
    ) THEN
        RAISE EXCEPTION 'graph projection edge crosses visibility scope' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_existing FROM graph_projection WHERE id = v_id FOR UPDATE;
    v_inserted := NOT FOUND;
    IF v_inserted THEN
        INSERT INTO graph_projection (
            id, projection_kind, visibility_scope, input_cutoff, as_of,
            identity_revision, mapping_revision, completeness, manifest_digest
        ) VALUES (
            v_id, v_kind, v_scope, v_input_cutoff, v_as_of,
            v_identity_revision, v_mapping_revision, v_completeness, v_digest
        );
    ELSIF v_existing.projection_kind IS DISTINCT FROM v_kind
       OR v_existing.visibility_scope IS DISTINCT FROM v_scope
       OR v_existing.input_cutoff IS DISTINCT FROM v_input_cutoff
       OR v_existing.as_of IS DISTINCT FROM v_as_of
       OR v_existing.identity_revision IS DISTINCT FROM v_identity_revision
       OR v_existing.mapping_revision IS DISTINCT FROM v_mapping_revision
       OR v_existing.completeness IS DISTINCT FROM v_completeness
       OR v_existing.manifest_digest IS DISTINCT FROM v_digest THEN
        RAISE EXCEPTION 'graph projection ID is already bound to different metadata';
    END IF;

    IF v_inserted THEN
        INSERT INTO projection_membership (
            projection_id, from_entity_id, to_entity_id, edge_kind,
            valid_from, valid_to, known_at
        )
        SELECT v_id, edge.from_entity_id, edge.to_entity_id, edge.edge_kind,
               edge.valid_from, edge.valid_to, edge.known_at
        FROM jsonb_to_recordset(v_edges) AS edge(
            from_entity_id uuid, to_entity_id uuid, edge_kind text,
            valid_from timestamptz, valid_to timestamptz, known_at timestamptz
        );
        RETURN true;
    END IF;

    IF EXISTS (
        (SELECT edge.from_entity_id, edge.to_entity_id, edge.edge_kind,
                edge.valid_from, edge.valid_to, edge.known_at
         FROM jsonb_to_recordset(v_edges) AS edge(
             from_entity_id uuid, to_entity_id uuid, edge_kind text,
             valid_from timestamptz, valid_to timestamptz, known_at timestamptz
         )
         EXCEPT
         SELECT membership.from_entity_id, membership.to_entity_id, membership.edge_kind,
                membership.valid_from, membership.valid_to, membership.known_at
         FROM projection_membership AS membership WHERE membership.projection_id = v_id)
        UNION ALL
        (SELECT membership.from_entity_id, membership.to_entity_id, membership.edge_kind,
                membership.valid_from, membership.valid_to, membership.known_at
         FROM projection_membership AS membership WHERE membership.projection_id = v_id
         EXCEPT
         SELECT edge.from_entity_id, edge.to_entity_id, edge.edge_kind,
                edge.valid_from, edge.valid_to, edge.known_at
         FROM jsonb_to_recordset(v_edges) AS edge(
             from_entity_id uuid, to_entity_id uuid, edge_kind text,
             valid_from timestamptz, valid_to timestamptz, known_at timestamptz
         ))
    ) THEN
        RAISE EXCEPTION 'graph projection replay changed immutable edges';
    END IF;
    RETURN false;
END;
$$;

COMMIT;
