-- Stage bounded graph batches privately, then publish one immutable projection.

BEGIN;

CREATE TABLE graph_projection_stage (
    projection_id uuid PRIMARY KEY,
    projection_kind text NOT NULL,
    visibility_scope rh_visibility_scope NOT NULL,
    input_cutoff timestamptz NOT NULL,
    as_of timestamptz NOT NULL,
    identity_revision text NOT NULL,
    mapping_revision text NOT NULL,
    completeness text NOT NULL CHECK (completeness IN ('complete', 'partial', 'truncated', 'failed')),
    manifest_digest text NOT NULL,
    expected_edge_count integer NOT NULL CHECK (expected_edge_count BETWEEN 0 AND 200000),
    chunk_count integer NOT NULL CHECK (chunk_count BETWEEN 1 AND 20),
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE graph_projection_stage_chunk (
    projection_id uuid NOT NULL REFERENCES graph_projection_stage(projection_id) ON DELETE CASCADE,
    chunk_index integer NOT NULL CHECK (chunk_index BETWEEN 0 AND 19),
    edge_count integer NOT NULL CHECK (edge_count BETWEEN 0 AND 10000),
    edges jsonb NOT NULL CHECK (jsonb_typeof(edges) = 'array'),
    PRIMARY KEY (projection_id, chunk_index)
);

CREATE FUNCTION rh_stage_graph_projection_chunk(p_document jsonb)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
    v_projection jsonb;
    v_edges jsonb;
    v_id uuid;
    v_kind text;
    v_scope rh_visibility_scope;
    v_input_cutoff timestamptz;
    v_as_of timestamptz;
    v_identity_revision text;
    v_mapping_revision text;
    v_completeness text;
    v_digest text;
    v_expected_edges integer;
    v_chunk_index integer;
    v_chunk_count integer;
    v_expected_chunks integer;
    v_existing graph_projection_stage%ROWTYPE;
    v_existing_chunk graph_projection_stage_chunk%ROWTYPE;
    v_loaded_edges jsonb;
    v_loaded_bytes bigint;
    v_final graph_projection%ROWTYPE;
    v_chunk_rows integer;
BEGIN
    IF p_document IS NULL OR jsonb_typeof(p_document) IS DISTINCT FROM 'object'
       OR p_document->>'schema' IS DISTINCT FROM 'rh-postgres-projection-chunk/1'
       OR jsonb_typeof(p_document->'projection') IS DISTINCT FROM 'object'
       OR jsonb_typeof(p_document->'edges') IS DISTINCT FROM 'array'
       OR pg_column_size(p_document) > 4194304 THEN
        RAISE EXCEPTION 'graph projection chunk is malformed or exceeds its 4 MiB bound'
            USING ERRCODE = '22023';
    END IF;

    v_projection := p_document->'projection';
    v_edges := p_document->'edges';
    v_id := (v_projection->>'id')::uuid;
    v_kind := v_projection->>'projection_kind';
    v_scope := (v_projection->>'visibility_scope')::rh_visibility_scope;
    v_input_cutoff := (v_projection->>'input_cutoff')::timestamptz;
    v_as_of := (v_projection->>'as_of')::timestamptz;
    v_identity_revision := v_projection->>'identity_revision';
    v_mapping_revision := v_projection->>'mapping_revision';
    v_completeness := v_projection->>'completeness';
    v_digest := v_projection->>'manifest_digest';
    v_expected_edges := (p_document->>'expected_edge_count')::integer;
    v_chunk_index := (p_document->>'chunk_index')::integer;
    v_chunk_count := (p_document->>'chunk_count')::integer;

    IF v_kind IS NULL OR length(btrim(v_kind)) NOT BETWEEN 1 AND 64
       OR v_identity_revision IS NULL OR length(v_identity_revision) > 256
       OR v_mapping_revision IS NULL OR length(v_mapping_revision) > 256
       OR v_completeness NOT IN ('complete', 'partial', 'truncated', 'failed')
       OR v_digest !~ '^[0-9a-f]{64}$'
       OR v_expected_edges IS NULL OR v_expected_edges NOT BETWEEN 0 AND 200000
       OR v_chunk_count IS NULL OR v_chunk_count NOT BETWEEN 1 AND 20
       OR v_chunk_index IS NULL OR v_chunk_index < 0 OR v_chunk_index >= v_chunk_count THEN
        RAISE EXCEPTION 'graph projection chunk metadata is invalid' USING ERRCODE = '22023';
    END IF;

    v_expected_chunks := greatest(1, (v_expected_edges + 9999) / 10000);
    IF v_chunk_count <> v_expected_chunks
       OR jsonb_array_length(v_edges) > 10000
       OR jsonb_array_length(v_edges) <> least(10000, greatest(0, v_expected_edges - v_chunk_index * 10000))
       OR (v_completeness = 'failed' AND v_expected_edges <> 0) THEN
        RAISE EXCEPTION 'graph projection chunk bounds or position are inconsistent' USING ERRCODE = '22023';
    END IF;
    PERFORM pg_advisory_xact_lock(hashtextextended(v_id::text, 0));

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
        RAISE EXCEPTION 'graph projection chunk contains a malformed edge' USING ERRCODE = '22023';
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
        RAISE EXCEPTION 'graph projection chunk contains an invalid identity or interval' USING ERRCODE = '22023';
    END IF;

    IF EXISTS (
        SELECT 1 FROM jsonb_to_recordset(v_edges) AS edge(
            from_entity_id uuid, to_entity_id uuid, edge_kind text,
            valid_from timestamptz, valid_to timestamptz, known_at timestamptz
        ) GROUP BY edge.from_entity_id, edge.to_entity_id, edge.edge_kind HAVING count(*) > 1
    ) THEN
        RAISE EXCEPTION 'graph projection chunk contains duplicate edges' USING ERRCODE = '22023';
    END IF;
    IF EXISTS (
        SELECT 1
        FROM jsonb_to_recordset(v_edges) AS edge(
            from_entity_id uuid, to_entity_id uuid, edge_kind text,
            valid_from timestamptz, valid_to timestamptz, known_at timestamptz
        )
        LEFT JOIN entity AS source_entity ON source_entity.id = edge.from_entity_id
        LEFT JOIN entity AS target_entity ON target_entity.id = edge.to_entity_id
        WHERE source_entity.id IS NULL OR target_entity.id IS NULL
           OR source_entity.visibility_scope <> v_scope OR target_entity.visibility_scope <> v_scope
    ) THEN
        RAISE EXCEPTION 'graph projection chunk has a missing or cross-scope entity' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_final FROM graph_projection WHERE id = v_id FOR UPDATE;
    IF FOUND THEN
        IF v_final.projection_kind IS DISTINCT FROM v_kind
           OR v_final.visibility_scope IS DISTINCT FROM v_scope
           OR v_final.input_cutoff IS DISTINCT FROM v_input_cutoff
           OR v_final.as_of IS DISTINCT FROM v_as_of
           OR v_final.identity_revision IS DISTINCT FROM v_identity_revision
           OR v_final.mapping_revision IS DISTINCT FROM v_mapping_revision
           OR v_final.completeness IS DISTINCT FROM v_completeness
           OR v_final.manifest_digest IS DISTINCT FROM v_digest THEN
            RAISE EXCEPTION 'final graph projection ID is bound to different metadata';
        END IF;
        IF (SELECT count(*) FROM projection_membership WHERE projection_id = v_id) <> v_expected_edges THEN
            RAISE EXCEPTION 'final graph projection edge count differs from chunk manifest';
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
        ) THEN
            RAISE EXCEPTION 'final graph projection does not match replayed chunk';
        END IF;
        RETURN 'replay';
    END IF;

    INSERT INTO graph_projection_stage (
        projection_id, projection_kind, visibility_scope, input_cutoff, as_of,
        identity_revision, mapping_revision, completeness, manifest_digest,
        expected_edge_count, chunk_count
    ) VALUES (
        v_id, v_kind, v_scope, v_input_cutoff, v_as_of,
        v_identity_revision, v_mapping_revision, v_completeness, v_digest,
        v_expected_edges, v_chunk_count
    ) ON CONFLICT (projection_id) DO NOTHING;

    SELECT * INTO v_existing FROM graph_projection_stage WHERE projection_id = v_id FOR UPDATE;
    IF v_existing.projection_kind IS DISTINCT FROM v_kind
       OR v_existing.visibility_scope IS DISTINCT FROM v_scope
       OR v_existing.input_cutoff IS DISTINCT FROM v_input_cutoff
       OR v_existing.as_of IS DISTINCT FROM v_as_of
       OR v_existing.identity_revision IS DISTINCT FROM v_identity_revision
       OR v_existing.mapping_revision IS DISTINCT FROM v_mapping_revision
       OR v_existing.completeness IS DISTINCT FROM v_completeness
       OR v_existing.manifest_digest IS DISTINCT FROM v_digest
       OR v_existing.expected_edge_count IS DISTINCT FROM v_expected_edges
       OR v_existing.chunk_count IS DISTINCT FROM v_chunk_count THEN
        RAISE EXCEPTION 'staged graph projection ID is already bound to different metadata';
    END IF;

    SELECT * INTO v_existing_chunk FROM graph_projection_stage_chunk
    WHERE projection_id = v_id AND chunk_index = v_chunk_index;
    IF FOUND AND v_existing_chunk.edges IS DISTINCT FROM v_edges THEN
        DELETE FROM graph_projection_stage_chunk
        WHERE projection_id = v_id AND chunk_index = v_chunk_index;
    ELSIF FOUND THEN
        RETURN 'staged';
    END IF;

    INSERT INTO graph_projection_stage_chunk (projection_id, chunk_index, edge_count, edges)
    VALUES (v_id, v_chunk_index, jsonb_array_length(v_edges), v_edges);

    SELECT count(*) INTO v_chunk_rows FROM graph_projection_stage_chunk WHERE projection_id = v_id;
    IF v_chunk_rows < v_chunk_count THEN RETURN 'staged'; END IF;
    SELECT COALESCE(sum(pg_column_size(edges)), 0) INTO v_loaded_bytes
    FROM graph_projection_stage_chunk WHERE projection_id = v_id;
    IF v_loaded_bytes > 67108864 THEN
        RAISE EXCEPTION 'staged graph projection exceeds the 64 MiB assembly bound' USING ERRCODE = '22023';
    END IF;

    SELECT COALESCE(jsonb_agg(edge.value ORDER BY chunk.chunk_index, edge.ordinality), '[]'::jsonb)
    INTO v_loaded_edges
    FROM graph_projection_stage_chunk AS chunk
    CROSS JOIN LATERAL jsonb_array_elements(chunk.edges) WITH ORDINALITY AS edge(value, ordinality)
    WHERE chunk.projection_id = v_id;
    IF jsonb_array_length(v_loaded_edges) <> v_expected_edges OR pg_column_size(v_loaded_edges) > 67108864 THEN
        RETURN 'staged';
    END IF;

    IF EXISTS (
        SELECT 1 FROM jsonb_to_recordset(v_loaded_edges) AS edge(
            from_entity_id uuid, to_entity_id uuid, edge_kind text,
            valid_from timestamptz, valid_to timestamptz, known_at timestamptz
        ) GROUP BY edge.from_entity_id, edge.to_entity_id, edge.edge_kind HAVING count(*) > 1
    ) THEN
        RETURN 'staged';
    END IF;

    INSERT INTO graph_projection (
        id, projection_kind, visibility_scope, input_cutoff, as_of,
        identity_revision, mapping_revision, completeness, manifest_digest
    ) VALUES (
        v_id, v_kind, v_scope, v_input_cutoff, v_as_of,
        v_identity_revision, v_mapping_revision, v_completeness, v_digest
    );
    INSERT INTO projection_membership (
        projection_id, from_entity_id, to_entity_id, edge_kind,
        valid_from, valid_to, known_at
    )
    SELECT v_id, edge.from_entity_id, edge.to_entity_id, edge.edge_kind,
           edge.valid_from, edge.valid_to, edge.known_at
    FROM jsonb_to_recordset(v_loaded_edges) AS edge(
        from_entity_id uuid, to_entity_id uuid, edge_kind text,
        valid_from timestamptz, valid_to timestamptz, known_at timestamptz
    );
    DELETE FROM graph_projection_stage WHERE projection_id = v_id;
    RETURN 'stored';
END;
$$;

COMMIT;
