BEGIN;

-- Durable current-state reconciliation is scoped independently from event
-- history. Incomplete acquisition can weaken prior presence to unconfirmed,
-- but only a complete/empty run can mark unseen source IDs absent.
CREATE TABLE source_object_state (
    source_instance_id uuid NOT NULL REFERENCES source_instance(id),
    capability text NOT NULL,
    scope_key text NOT NULL,
    native_id text NOT NULL,
    state text NOT NULL CHECK (state IN ('present', 'absent', 'unconfirmed')),
    last_collection_run_id uuid NOT NULL REFERENCES collection_run(id),
    last_captured_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL,
    PRIMARY KEY (source_instance_id, capability, scope_key, native_id),
    CHECK (length(capability) BETWEEN 1 AND 128),
    CHECK (length(scope_key) BETWEEN 1 AND 512),
    CHECK (length(native_id) BETWEEN 1 AND 512)
);
CREATE INDEX source_object_state_scope ON source_object_state
    (source_instance_id, capability, scope_key, state, native_id);

CREATE TABLE source_state_reconciliation (
    collection_run_id uuid PRIMARY KEY REFERENCES collection_run(id),
    source_instance_id uuid NOT NULL REFERENCES source_instance(id),
    capability text NOT NULL,
    scope_key text NOT NULL,
    acquisition text NOT NULL CHECK (acquisition IN ('complete', 'empty', 'partial', 'failed', 'unsupported')),
    observed_native_ids text[] NOT NULL,
    captured_at timestamptz NOT NULL,
    applied_at timestamptz NOT NULL
);

CREATE FUNCTION rh_reconcile_source_objects(
    p_source_instance_id uuid,
    p_collection_run_id uuid,
    p_capability text,
    p_scope_key text,
    p_acquisition text,
    p_observed_ids text[],
    p_now timestamptz
) RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_run collection_run%ROWTYPE;
    v_batch source_state_reconciliation%ROWTYPE;
    v_ids text[];
    v_observed bigint;
    v_unseen bigint;
    v_bytes bigint;
    v_newer boolean;
    v_batch_inserted bigint;
BEGIN
    IF p_source_instance_id IS NULL OR p_collection_run_id IS NULL
       OR p_capability IS NULL OR length(p_capability) NOT BETWEEN 1 AND 128
       OR p_scope_key IS NULL OR length(p_scope_key) NOT BETWEEN 1 AND 512
       OR p_now IS NULL OR p_observed_ids IS NULL THEN
        RAISE EXCEPTION 'current-state reconciliation identity is invalid';
    END IF;
    IF p_acquisition IS NULL OR p_acquisition NOT IN ('complete', 'empty', 'partial', 'failed', 'unsupported') THEN
        RAISE EXCEPTION 'current-state acquisition state is invalid';
    END IF;
    IF cardinality(p_observed_ids) > 100000 THEN
        RAISE EXCEPTION 'current-state observed identifier count exceeds the limit';
    END IF;
    SELECT COALESCE(sum(octet_length(id)), 0) INTO v_bytes
    FROM unnest(p_observed_ids) AS observed(id);
    IF v_bytes > 4194304 THEN
        RAISE EXCEPTION 'current-state observed identifier bytes exceed the limit';
    END IF;
    IF EXISTS (
        SELECT 1 FROM unnest(p_observed_ids) AS observed(id)
        WHERE id IS NULL OR length(id) NOT BETWEEN 1 AND 512
    ) OR cardinality(p_observed_ids) <> (
        SELECT count(DISTINCT id) FROM unnest(p_observed_ids) AS observed(id)
    ) THEN
        RAISE EXCEPTION 'current-state identifiers are empty, oversized, or duplicated';
    END IF;
    SELECT COALESCE(array_agg(id ORDER BY id), ARRAY[]::text[]) INTO v_ids
    FROM unnest(p_observed_ids) AS observed(id);

    PERFORM pg_advisory_xact_lock(hashtextextended(
        p_source_instance_id::text || ':' || p_capability || ':' || p_scope_key, 0));
    SELECT * INTO v_run FROM collection_run
    WHERE id = p_collection_run_id
      AND source_instance_id = p_source_instance_id
      AND capability = p_capability
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'current-state collection run scope does not match';
    END IF;
    IF (p_acquisition IN ('complete', 'empty') AND
        (v_run.status <> 'succeeded' OR v_run.completeness <> p_acquisition))
       OR (p_acquisition = 'partial' AND
        (v_run.status <> 'partial' OR v_run.completeness NOT IN ('partial', 'unknown')))
       OR (p_acquisition = 'failed' AND
        (v_run.status NOT IN ('failed', 'canceled') OR v_run.completeness NOT IN ('partial', 'unknown')))
       OR (p_acquisition = 'unsupported' AND
        (v_run.status <> 'partial' OR v_run.completeness <> 'unknown')) THEN
        RAISE EXCEPTION 'current-state acquisition disagrees with terminal collection run';
    END IF;
    IF p_acquisition IN ('empty', 'failed', 'unsupported') AND cardinality(v_ids) <> 0 THEN
        RAISE EXCEPTION 'empty, failed, or unsupported acquisition cannot assert observed identifiers';
    END IF;
    IF p_acquisition = 'complete' AND cardinality(v_ids) = 0 THEN
        RAISE EXCEPTION 'successful empty acquisition must use the empty state';
    END IF;
    INSERT INTO source_state_reconciliation (
        collection_run_id, source_instance_id, capability, scope_key,
        acquisition, observed_native_ids, captured_at, applied_at
    ) VALUES (
        p_collection_run_id, p_source_instance_id, p_capability, p_scope_key,
        p_acquisition, v_ids, p_now, p_now
    ) ON CONFLICT (collection_run_id) DO NOTHING;
    GET DIAGNOSTICS v_batch_inserted = ROW_COUNT;
    IF v_batch_inserted = 0 THEN
        SELECT * INTO v_batch FROM source_state_reconciliation
        WHERE collection_run_id = p_collection_run_id;
        IF v_batch.source_instance_id <> p_source_instance_id
           OR v_batch.capability <> p_capability
           OR v_batch.scope_key <> p_scope_key
           OR v_batch.acquisition <> p_acquisition
           OR v_batch.observed_native_ids <> v_ids
           OR v_batch.captured_at <> p_now THEN
            RAISE EXCEPTION 'current-state replay differs from its committed reconciliation';
        END IF;
        RETURN jsonb_build_object(
            'schema', 'rh-postgres-current-state-result/1',
            'status', 'duplicate',
            'source_instance_id', p_source_instance_id,
            'collection_run_id', p_collection_run_id,
            'capability', p_capability,
            'scope', p_scope_key,
            'acquisition', p_acquisition,
            'observed_upserts', 0,
            'unseen_state_changes', 0,
            'absence_inferred', p_acquisition IN ('complete', 'empty')
        );
    END IF;
    SELECT EXISTS (
        SELECT 1 FROM source_object_state AS state_row
        JOIN collection_run AS prior ON prior.id = state_row.last_collection_run_id
        WHERE state_row.source_instance_id = p_source_instance_id
          AND state_row.capability = p_capability
          AND state_row.scope_key = p_scope_key
          AND prior.started_at > v_run.started_at
    ) INTO v_newer;
    IF v_newer THEN
        RAISE EXCEPTION 'current-state reconciliation is older than committed state';
    END IF;

    INSERT INTO source_object_state (
        source_instance_id, capability, scope_key, native_id, state,
        last_collection_run_id, last_captured_at, updated_at
    )
    SELECT p_source_instance_id, p_capability, p_scope_key, observed.id, 'present',
           p_collection_run_id, p_now, p_now
    FROM unnest(v_ids) AS observed(id)
    ON CONFLICT (source_instance_id, capability, scope_key, native_id)
    DO UPDATE SET state = 'present',
                  last_collection_run_id = EXCLUDED.last_collection_run_id,
                  last_captured_at = EXCLUDED.last_captured_at,
                  updated_at = EXCLUDED.updated_at;
    GET DIAGNOSTICS v_observed = ROW_COUNT;

    UPDATE source_object_state AS prior_state
    SET state = CASE WHEN p_acquisition IN ('complete', 'empty') THEN 'absent' ELSE 'unconfirmed' END,
        last_collection_run_id = p_collection_run_id,
        last_captured_at = p_now,
        updated_at = p_now
    WHERE prior_state.source_instance_id = p_source_instance_id
      AND prior_state.capability = p_capability
      AND prior_state.scope_key = p_scope_key
      AND prior_state.native_id <> ALL(v_ids);
    GET DIAGNOSTICS v_unseen = ROW_COUNT;
    RETURN jsonb_build_object(
        'schema', 'rh-postgres-current-state-result/1',
        'status', 'applied',
        'source_instance_id', p_source_instance_id,
        'collection_run_id', p_collection_run_id,
        'capability', p_capability,
        'scope', p_scope_key,
        'acquisition', p_acquisition,
        'observed_upserts', v_observed,
        'unseen_state_changes', v_unseen,
        'absence_inferred', p_acquisition IN ('complete', 'empty')
    );
END;
$$;


COMMIT;
