-- repo-health PostgreSQL target schema, migration 001.
--
-- The Elisa reference runtime currently uses src/rh_store.elisa.  This file
-- is the server-persistence contract from M02-01: it is deliberately free of
-- provider-specific secrets and keeps raw bytes in the content-addressed
-- evidence store.  Apply it inside one migration transaction.

BEGIN;

CREATE DOMAIN rh_visibility_scope AS text
    CHECK (VALUE IN (
        'public', 'tenant-private', 'restricted-personal',
        'embargoed-security', 'suppressed'
    ));

CREATE TABLE source_instance (
    id uuid PRIMARY KEY,
    kind text NOT NULL,
    base_url text NOT NULL,
    visibility_scope rh_visibility_scope NOT NULL,
    configuration_revision bigint NOT NULL CHECK (configuration_revision > 0),
    created_at timestamptz NOT NULL,
    UNIQUE (kind, base_url, visibility_scope)
);

CREATE TABLE capability_observation (
    id uuid PRIMARY KEY,
    source_instance_id uuid NOT NULL REFERENCES source_instance(id),
    capability text NOT NULL,
    state text NOT NULL CHECK (state IN ('supported', 'unsupported', 'unauthorized', 'unavailable', 'partial')),
    provider_version text,
    observed_at timestamptz NOT NULL,
    details jsonb NOT NULL DEFAULT '{}'::jsonb,
    UNIQUE (source_instance_id, capability, observed_at)
);

CREATE TABLE credential_reference (
    id uuid PRIMARY KEY,
    source_instance_id uuid NOT NULL REFERENCES source_instance(id),
    secret_locator text NOT NULL,
    declared_scope text NOT NULL,
    created_at timestamptz NOT NULL,
    revoked_at timestamptz,
    CHECK (revoked_at IS NULL OR revoked_at >= created_at),
    CHECK (secret_locator !~ '[[:space:]]')
);

CREATE TABLE evidence_object (
    id uuid PRIMARY KEY,
    visibility_scope rh_visibility_scope NOT NULL,
    digest_algorithm text NOT NULL CHECK (digest_algorithm IN ('sha256', 'sha512')),
    digest_value text NOT NULL CHECK (digest_value ~ '^[0-9a-f]+$'),
    media_type text NOT NULL,
    byte_length bigint NOT NULL CHECK (byte_length >= 0),
    storage_key text NOT NULL,
    retention_class text NOT NULL,
    transformation_kind text NOT NULL,
    created_at timestamptz NOT NULL,
    UNIQUE (visibility_scope, digest_algorithm, digest_value),
    UNIQUE (visibility_scope, storage_key)
);

CREATE TABLE evidence_access_rule (
    id uuid PRIMARY KEY,
    evidence_id uuid NOT NULL REFERENCES evidence_object(id),
    visibility_scope rh_visibility_scope NOT NULL,
    effect text NOT NULL CHECK (effect IN ('allow', 'deny')),
    reason text NOT NULL,
    expires_at timestamptz,
    created_at timestamptz NOT NULL,
    CHECK (expires_at IS NULL OR expires_at > created_at),
    UNIQUE (evidence_id, visibility_scope, effect, created_at)
);

CREATE TABLE evidence_retention_rule (
    id uuid PRIMARY KEY,
    evidence_id uuid NOT NULL REFERENCES evidence_object(id),
    retention_class text NOT NULL,
    retain_until timestamptz,
    deletion_state text NOT NULL CHECK (deletion_state IN ('retained', 'pending', 'deleted', 'blocked')),
    reason text NOT NULL,
    updated_at timestamptz NOT NULL
);

CREATE TABLE collection_run (
    id uuid PRIMARY KEY,
    source_instance_id uuid NOT NULL REFERENCES source_instance(id),
    capability text NOT NULL,
    connector_name text NOT NULL,
    connector_version text NOT NULL,
    requested_start timestamptz,
    requested_end timestamptz,
    started_at timestamptz NOT NULL,
    finished_at timestamptz,
    status text NOT NULL CHECK (status IN ('running', 'succeeded', 'partial', 'failed', 'canceled')),
    completeness text NOT NULL CHECK (completeness IN ('complete', 'partial', 'empty', 'unknown')),
    coverage_details jsonb NOT NULL DEFAULT '{}'::jsonb,
    CHECK (requested_end IS NULL OR requested_start IS NULL OR requested_end > requested_start),
    CHECK (finished_at IS NULL OR finished_at >= started_at)
);

CREATE TABLE collection_page (
    id uuid PRIMARY KEY,
    collection_run_id uuid NOT NULL REFERENCES collection_run(id),
    page_number integer NOT NULL CHECK (page_number >= 0),
    scope_hash text NOT NULL,
    cursor_before jsonb,
    cursor_after jsonb,
    status text NOT NULL CHECK (status IN ('success', 'failed', 'partial', 'unsupported', 'unauthorized', 'rate_limited')),
    completeness text NOT NULL CHECK (completeness IN ('complete', 'partial', 'empty', 'unknown')),
    record_count integer NOT NULL CHECK (record_count >= 0),
    evidence_id uuid REFERENCES evidence_object(id),
    attempted_at timestamptz NOT NULL,
    completed_at timestamptz,
    CHECK (completed_at IS NULL OR completed_at >= attempted_at),
    UNIQUE (collection_run_id, page_number)
);

CREATE TABLE collection_cursor (
    id uuid PRIMARY KEY,
    source_instance_id uuid NOT NULL REFERENCES source_instance(id),
    capability text NOT NULL,
    scope_hash text NOT NULL,
    cursor jsonb NOT NULL,
    last_page_number integer NOT NULL CHECK (last_page_number >= 0),
    last_success_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL,
    UNIQUE (source_instance_id, capability, scope_hash)
);

CREATE TABLE job (
    id uuid PRIMARY KEY,
    source_instance_id uuid REFERENCES source_instance(id),
    kind text NOT NULL,
    visibility_scope rh_visibility_scope NOT NULL,
    state text NOT NULL CHECK (state IN ('queued', 'running', 'succeeded', 'failed', 'dead_letter', 'canceled')),
    priority integer NOT NULL DEFAULT 0,
    next_attempt_at timestamptz NOT NULL,
    attempt_count integer NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
    fencing_token bigint NOT NULL DEFAULT 0 CHECK (fencing_token >= 0),
    worker_id text,
    lease_expires_at timestamptz,
    created_at timestamptz NOT NULL,
    finished_at timestamptz,
    input_manifest jsonb NOT NULL DEFAULT '{}'::jsonb,
    CHECK (finished_at IS NULL OR finished_at >= created_at),
    CHECK ((state = 'running' AND lease_expires_at IS NOT NULL) OR state <> 'running')
);

CREATE TABLE job_attempt (
    id uuid PRIMARY KEY,
    job_id uuid NOT NULL REFERENCES job(id),
    attempt_number integer NOT NULL CHECK (attempt_number > 0),
    fencing_token bigint NOT NULL CHECK (fencing_token > 0),
    worker_id text NOT NULL,
    started_at timestamptz NOT NULL,
    finished_at timestamptz,
    outcome text,
    error_kind text,
    CHECK (finished_at IS NULL OR finished_at >= started_at),
    UNIQUE (job_id, attempt_number),
    UNIQUE (job_id, fencing_token)
);

CREATE TABLE entity (
    id uuid PRIMARY KEY,
    entity_kind text NOT NULL,
    visibility_scope rh_visibility_scope NOT NULL,
    created_at timestamptz NOT NULL
);

CREATE TABLE project (
    id uuid PRIMARY KEY REFERENCES entity(id),
    visibility_scope rh_visibility_scope NOT NULL,
    canonical_name text NOT NULL,
    namespace text,
    UNIQUE (visibility_scope, canonical_name)
);

CREATE TABLE repository (
    id uuid PRIMARY KEY REFERENCES entity(id),
    source_instance_id uuid NOT NULL REFERENCES source_instance(id),
    source_kind text NOT NULL,
    source_native_id text NOT NULL,
    project_id uuid REFERENCES project(id),
    default_branch text,
    UNIQUE (source_instance_id, source_kind, source_native_id)
);

CREATE TABLE repository_location (
    id uuid PRIMARY KEY,
    repository_id uuid NOT NULL REFERENCES repository(id),
    location_role text NOT NULL,
    canonical_url text NOT NULL,
    observed_at timestamptz NOT NULL,
    accepted boolean NOT NULL DEFAULT false,
    UNIQUE (repository_id, location_role, canonical_url)
);

CREATE TABLE repository_snapshot (
    id uuid PRIMARY KEY,
    repository_id uuid NOT NULL REFERENCES repository(id),
    evidence_id uuid NOT NULL REFERENCES evidence_object(id),
    revision text,
    captured_at timestamptz NOT NULL,
    completeness text NOT NULL CHECK (completeness IN ('complete', 'partial', 'missing', 'failed'))
);

CREATE TABLE revision (
    id uuid PRIMARY KEY,
    repository_id uuid NOT NULL REFERENCES repository(id),
    source_revision text NOT NULL,
    authored_at timestamptz,
    committed_at timestamptz,
    observed_at timestamptz NOT NULL,
    evidence_id uuid REFERENCES evidence_object(id),
    UNIQUE (repository_id, source_revision)
);

CREATE TABLE revision_membership (
    revision_id uuid NOT NULL REFERENCES revision(id),
    repository_snapshot_id uuid NOT NULL REFERENCES repository_snapshot(id),
    PRIMARY KEY (revision_id, repository_snapshot_id)
);

CREATE TABLE ref_observation (
    id uuid PRIMARY KEY,
    repository_id uuid NOT NULL REFERENCES repository(id),
    ref_name text NOT NULL,
    target_revision_id uuid REFERENCES revision(id),
    observed_at timestamptz NOT NULL,
    state text NOT NULL CHECK (state IN ('present', 'deleted', 'unknown'))
);

CREATE TABLE account (
    id uuid PRIMARY KEY,
    source_instance_id uuid NOT NULL REFERENCES source_instance(id),
    source_native_id text NOT NULL,
    account_kind text NOT NULL CHECK (account_kind IN ('human', 'bot', 'service', 'organization', 'unknown')),
    display_name text,
    raw_identity_evidence_id uuid REFERENCES evidence_object(id),
    visibility_scope rh_visibility_scope NOT NULL,
    UNIQUE (source_instance_id, source_native_id)
);

CREATE TABLE actor_cluster_revision (
    id uuid PRIMARY KEY,
    cluster_key text NOT NULL,
    revision_number bigint NOT NULL CHECK (revision_number >= 0),
    state text NOT NULL CHECK (state IN ('proposed', 'accepted', 'rejected', 'revoked', 'conflicted')),
    valid_from timestamptz NOT NULL,
    valid_to timestamptz,
    evidence jsonb NOT NULL DEFAULT '[]'::jsonb,
    UNIQUE (cluster_key, revision_number),
    CHECK (valid_to IS NULL OR valid_to > valid_from)
);

CREATE TABLE identity_assertion (
    id uuid PRIMARY KEY,
    account_id uuid NOT NULL REFERENCES account(id),
    actor_cluster_revision_id uuid REFERENCES actor_cluster_revision(id),
    scope text NOT NULL,
    state text NOT NULL CHECK (state IN ('proposed', 'accepted', 'rejected', 'revoked', 'conflicted')),
    evidence_id uuid REFERENCES evidence_object(id),
    asserted_at timestamptz NOT NULL,
    reviewed_at timestamptz
);

CREATE TABLE role_assertion (
    id uuid PRIMARY KEY,
    project_id uuid NOT NULL REFERENCES project(id),
    account_id uuid REFERENCES account(id),
    actor_cluster_revision_id uuid REFERENCES actor_cluster_revision(id),
    role_kind text NOT NULL,
    state text NOT NULL CHECK (state IN ('proposed', 'accepted', 'rejected', 'revoked', 'unknown')),
    valid_from timestamptz,
    valid_to timestamptz,
    evidence_id uuid REFERENCES evidence_object(id),
    CHECK (account_id IS NOT NULL OR actor_cluster_revision_id IS NOT NULL),
    CHECK (valid_to IS NULL OR valid_from IS NULL OR valid_to > valid_from)
);

CREATE TABLE change_proposal (
    id uuid PRIMARY KEY,
    project_id uuid NOT NULL REFERENCES project(id),
    source_instance_id uuid NOT NULL REFERENCES source_instance(id),
    source_native_id text NOT NULL,
    author_account_id uuid REFERENCES account(id),
    state text NOT NULL,
    opened_at timestamptz,
    closed_at timestamptz,
    UNIQUE (source_instance_id, source_native_id)
);

CREATE TABLE change_revision (
    id uuid PRIMARY KEY,
    proposal_id uuid NOT NULL REFERENCES change_proposal(id),
    revision_id uuid REFERENCES revision(id),
    sequence_number integer NOT NULL CHECK (sequence_number > 0),
    observed_at timestamptz NOT NULL,
    UNIQUE (proposal_id, sequence_number)
);

CREATE TABLE review_event (
    id uuid PRIMARY KEY,
    proposal_id uuid NOT NULL REFERENCES change_proposal(id),
    reviewer_account_id uuid REFERENCES account(id),
    event_kind text NOT NULL,
    occurred_at timestamptz,
    observed_at timestamptz NOT NULL,
    source_event_key text NOT NULL,
    UNIQUE (proposal_id, source_event_key)
);

CREATE TABLE issue_state (
    id uuid PRIMARY KEY,
    project_id uuid NOT NULL REFERENCES project(id),
    source_instance_id uuid NOT NULL REFERENCES source_instance(id),
    source_native_id text NOT NULL,
    state text NOT NULL,
    observed_at timestamptz NOT NULL,
    UNIQUE (source_instance_id, source_native_id, observed_at)
);

CREATE TABLE issue_event (
    id uuid PRIMARY KEY,
    issue_state_id uuid NOT NULL REFERENCES issue_state(id),
    actor_account_id uuid REFERENCES account(id),
    event_kind text NOT NULL,
    occurred_at timestamptz,
    observed_at timestamptz NOT NULL,
    source_event_key text NOT NULL,
    UNIQUE (issue_state_id, source_event_key)
);

CREATE TABLE package (
    id uuid PRIMARY KEY REFERENCES entity(id),
    ecosystem text NOT NULL,
    namespace text,
    name text NOT NULL,
    UNIQUE (ecosystem, namespace, name)
);

CREATE TABLE package_version (
    id uuid PRIMARY KEY,
    package_id uuid NOT NULL REFERENCES package(id),
    version text NOT NULL,
    published_at timestamptz,
    yanked_state text NOT NULL CHECK (yanked_state IN ('true', 'false', 'unknown')),
    UNIQUE (package_id, version)
);

CREATE TABLE artifact (
    id uuid PRIMARY KEY,
    package_version_id uuid NOT NULL REFERENCES package_version(id),
    evidence_id uuid REFERENCES evidence_object(id),
    artifact_kind text NOT NULL,
    digest_algorithm text,
    digest_value text,
    UNIQUE (package_version_id, artifact_kind, digest_algorithm, digest_value)
);

CREATE TABLE artifact_location (
    id uuid PRIMARY KEY,
    artifact_id uuid NOT NULL REFERENCES artifact(id),
    source_instance_id uuid REFERENCES source_instance(id),
    url text NOT NULL,
    observed_at timestamptz NOT NULL,
    UNIQUE (artifact_id, url)
);

CREATE TABLE project_package_assertion (
    id uuid PRIMARY KEY,
    project_id uuid NOT NULL REFERENCES project(id),
    package_id uuid NOT NULL REFERENCES package(id),
    package_version_id uuid REFERENCES package_version(id),
    assertion_kind text NOT NULL CHECK (assertion_kind IN ('declared', 'resolved', 'vendored', 'distribution')),
    scope text NOT NULL,
    state text NOT NULL CHECK (state IN ('observed', 'missing', 'unsupported', 'conflicted')),
    evidence_id uuid REFERENCES evidence_object(id),
    observed_at timestamptz NOT NULL
);

CREATE TABLE dependency_requirement (
    id uuid PRIMARY KEY,
    project_id uuid NOT NULL REFERENCES project(id),
    package_id uuid REFERENCES package(id),
    ecosystem text NOT NULL,
    requested_name text NOT NULL,
    constraint_text text NOT NULL,
    scope text NOT NULL,
    optional boolean NOT NULL DEFAULT false,
    parser_status text NOT NULL CHECK (parser_status IN ('exact', 'range', 'unresolved', 'unsupported', 'malformed')),
    evidence_id uuid REFERENCES evidence_object(id),
    observed_at timestamptz NOT NULL
);

CREATE TABLE resolution_snapshot (
    id uuid PRIMARY KEY,
    project_id uuid NOT NULL REFERENCES project(id),
    environment text NOT NULL,
    resolver_name text NOT NULL,
    resolver_version text NOT NULL,
    observed_at timestamptz NOT NULL,
    completeness text NOT NULL CHECK (completeness IN ('complete', 'partial', 'failed', 'unsupported')),
    evidence_id uuid REFERENCES evidence_object(id)
);

CREATE TABLE resolved_dependency_edge (
    id uuid PRIMARY KEY,
    resolution_snapshot_id uuid NOT NULL REFERENCES resolution_snapshot(id),
    consumer_package_version_id uuid NOT NULL REFERENCES package_version(id),
    dependency_package_version_id uuid REFERENCES package_version(id),
    requested_name text NOT NULL,
    scope text NOT NULL,
    resolution_status text NOT NULL CHECK (resolution_status IN ('resolved', 'unresolved', 'ambiguous', 'unsupported')),
    UNIQUE (resolution_snapshot_id, consumer_package_version_id, requested_name, scope)
);

CREATE TABLE graph_projection (
    id uuid PRIMARY KEY,
    projection_kind text NOT NULL,
    visibility_scope rh_visibility_scope NOT NULL,
    input_cutoff timestamptz NOT NULL,
    as_of timestamptz NOT NULL,
    identity_revision text NOT NULL,
    mapping_revision text NOT NULL,
    completeness text NOT NULL CHECK (completeness IN ('complete', 'partial', 'truncated', 'failed')),
    manifest_digest text NOT NULL,
    UNIQUE (projection_kind, visibility_scope, input_cutoff, as_of, identity_revision, mapping_revision)
);

CREATE TABLE projection_membership (
    projection_id uuid NOT NULL REFERENCES graph_projection(id),
    from_entity_id uuid NOT NULL REFERENCES entity(id),
    to_entity_id uuid NOT NULL REFERENCES entity(id),
    edge_kind text NOT NULL,
    valid_from timestamptz,
    valid_to timestamptz,
    known_at timestamptz NOT NULL,
    PRIMARY KEY (projection_id, from_entity_id, to_entity_id, edge_kind),
    CHECK (valid_to IS NULL OR valid_from IS NULL OR valid_to > valid_from)
);

CREATE TABLE advisory_record (
    id uuid PRIMARY KEY,
    source_instance_id uuid REFERENCES source_instance(id),
    source_native_id text NOT NULL,
    summary text,
    published_at timestamptz,
    modified_at timestamptz,
    withdrawn_at timestamptz,
    payload jsonb NOT NULL DEFAULT '{}'::jsonb,
    UNIQUE (source_instance_id, source_native_id)
);

CREATE TABLE advisory_alias_assertion (
    id uuid PRIMARY KEY,
    advisory_id uuid NOT NULL REFERENCES advisory_record(id),
    alias text NOT NULL,
    state text NOT NULL CHECK (state IN ('accepted', 'proposed', 'rejected')),
    evidence_id uuid REFERENCES evidence_object(id),
    UNIQUE (advisory_id, alias)
);

CREATE TABLE affected_version_assertion (
    id uuid PRIMARY KEY,
    advisory_id uuid NOT NULL REFERENCES advisory_record(id),
    package_version_id uuid NOT NULL REFERENCES package_version(id),
    state text NOT NULL CHECK (state IN ('affected', 'not_affected', 'unknown')),
    evidence_id uuid REFERENCES evidence_object(id),
    UNIQUE (advisory_id, package_version_id)
);

CREATE TABLE canonical_event (
    id uuid PRIMARY KEY,
    source_instance_id uuid NOT NULL REFERENCES source_instance(id),
    source_object_type text NOT NULL,
    source_object_id text NOT NULL,
    source_revision text NOT NULL,
    event_kind text NOT NULL,
    subject_id uuid NOT NULL REFERENCES entity(id),
    actor_account_id uuid REFERENCES account(id),
    occurred_at timestamptz,
    observed_at timestamptz NOT NULL,
    time_basis text NOT NULL CHECK (time_basis IN ('event', 'observation', 'unknown')),
    evidence_id uuid NOT NULL REFERENCES evidence_object(id),
    parser_version text NOT NULL,
    payload jsonb NOT NULL,
    UNIQUE (source_instance_id, source_object_type, source_object_id, source_revision, event_kind)
);

CREATE TABLE metric_definition (
    metric_key text NOT NULL,
    metric_version text NOT NULL,
    definition_digest text NOT NULL,
    definition jsonb NOT NULL,
    implementation_status text NOT NULL CHECK (implementation_status IN ('implemented', 'prototype', 'planned', 'retired')),
    PRIMARY KEY (metric_key, metric_version)
);

CREATE TABLE metric_run (
    id uuid PRIMARY KEY,
    visibility_scope rh_visibility_scope NOT NULL,
    input_cutoff timestamptz NOT NULL,
    configuration_digest text NOT NULL,
    identity_revision text NOT NULL,
    started_at timestamptz NOT NULL,
    finished_at timestamptz,
    status text NOT NULL CHECK (status IN ('running', 'succeeded', 'partial', 'failed')),
    CHECK (finished_at IS NULL OR finished_at >= started_at)
);

CREATE TABLE metric_input_manifest (
    id uuid PRIMARY KEY,
    metric_run_id uuid NOT NULL REFERENCES metric_run(id),
    evidence_id uuid REFERENCES evidence_object(id),
    input_kind text NOT NULL,
    input_digest text NOT NULL,
    UNIQUE (metric_run_id, input_kind, input_digest)
);

CREATE TABLE metric_observation (
    id uuid PRIMARY KEY,
    visibility_scope rh_visibility_scope NOT NULL,
    subject_id uuid NOT NULL REFERENCES entity(id),
    metric_key text NOT NULL,
    metric_version text NOT NULL,
    run_id uuid NOT NULL REFERENCES metric_run(id),
    status text NOT NULL CHECK (status IN ('observed', 'not_observed', 'unavailable', 'unauthorized', 'partial', 'stale', 'not_applicable', 'error', 'conflicted', 'suppressed', 'unsupported')),
    value jsonb,
    unit text NOT NULL,
    window_start timestamptz,
    window_end timestamptz,
    input_manifest_digest text NOT NULL,
    configuration_digest text NOT NULL,
    identity_revision text NOT NULL,
    graph_projection_id uuid REFERENCES graph_projection(id),
    quality_dimensions jsonb NOT NULL DEFAULT '{}'::jsonb,
    computed_at timestamptz NOT NULL,
    FOREIGN KEY (metric_key, metric_version) REFERENCES metric_definition(metric_key, metric_version),
    CHECK (window_end IS NULL OR window_start IS NULL OR window_end > window_start),
    CHECK ((status = 'observed' AND value IS NOT NULL) OR status IN ('partial', 'stale') OR (status <> 'observed' AND value IS NULL))
);

CREATE TABLE finding (
    id uuid PRIMARY KEY,
    subject_id uuid NOT NULL REFERENCES entity(id),
    visibility_scope rh_visibility_scope NOT NULL,
    finding_kind text NOT NULL,
    state text NOT NULL CHECK (state IN ('open', 'resolved', 'suppressed', 'unknown')),
    created_at timestamptz NOT NULL
);

CREATE TABLE finding_revision (
    id uuid PRIMARY KEY,
    finding_id uuid NOT NULL REFERENCES finding(id),
    revision_number bigint NOT NULL CHECK (revision_number >= 0),
    reason text NOT NULL,
    evidence_id uuid REFERENCES evidence_object(id),
    metric_observation_id uuid REFERENCES metric_observation(id),
    created_at timestamptz NOT NULL,
    UNIQUE (finding_id, revision_number)
);

CREATE TABLE policy_definition (
    id uuid PRIMARY KEY,
    policy_key text NOT NULL,
    policy_version text NOT NULL,
    visibility_scope rh_visibility_scope NOT NULL,
    definition jsonb NOT NULL,
    definition_digest text NOT NULL,
    UNIQUE (policy_key, policy_version, visibility_scope)
);

CREATE TABLE policy_evaluation (
    id uuid PRIMARY KEY,
    policy_id uuid NOT NULL REFERENCES policy_definition(id),
    subject_id uuid NOT NULL REFERENCES entity(id),
    input_cutoff timestamptz NOT NULL,
    result text NOT NULL CHECK (result IN ('allow', 'deny', 'warn', 'unknown')),
    evidence jsonb NOT NULL DEFAULT '[]'::jsonb,
    evaluated_at timestamptz NOT NULL
);

CREATE TABLE exception (
    id uuid PRIMARY KEY,
    policy_id uuid NOT NULL REFERENCES policy_definition(id),
    subject_id uuid NOT NULL REFERENCES entity(id),
    rationale text NOT NULL,
    approver text NOT NULL,
    created_at timestamptz NOT NULL,
    expires_at timestamptz NOT NULL,
    CHECK (expires_at > created_at)
);

CREATE TABLE correction_case (
    id uuid PRIMARY KEY,
    subject_id uuid NOT NULL REFERENCES entity(id),
    requester text NOT NULL,
    case_kind text NOT NULL CHECK (case_kind IN ('identity', 'measurement', 'suppression', 'deletion')),
    state text NOT NULL CHECK (state IN ('open', 'accepted', 'rejected', 'withdrawn')),
    submitted_at timestamptz NOT NULL,
    resolved_at timestamptz
);

CREATE TABLE publication_record (
    id uuid PRIMARY KEY,
    subject_id uuid REFERENCES entity(id),
    visibility_scope rh_visibility_scope NOT NULL,
    report_schema text NOT NULL,
    report_digest text NOT NULL,
    evidence_cutoff timestamptz NOT NULL,
    replayability text NOT NULL CHECK (replayability IN ('fully_replayable', 'external_retrieval', 'partially_replayable', 'not_replayable')),
    published_at timestamptz NOT NULL,
    evidence_id uuid REFERENCES evidence_object(id),
    UNIQUE (report_schema, report_digest, visibility_scope)
);

CREATE TABLE audit_event (
    id uuid PRIMARY KEY,
    visibility_scope rh_visibility_scope NOT NULL,
    actor text,
    action text NOT NULL,
    subject_type text NOT NULL,
    subject_id uuid,
    details jsonb NOT NULL DEFAULT '{}'::jsonb,
    occurred_at timestamptz NOT NULL
);

CREATE TABLE outbox_event (
    id uuid PRIMARY KEY,
    topic text NOT NULL,
    aggregate_type text NOT NULL,
    aggregate_id uuid NOT NULL,
    payload jsonb NOT NULL,
    created_at timestamptz NOT NULL,
    published_at timestamptz,
    UNIQUE (topic, aggregate_type, aggregate_id, created_at)
);

CREATE INDEX collection_page_run_order ON collection_page (collection_run_id, page_number);
CREATE INDEX event_subject_time ON canonical_event (subject_id, occurred_at, id);
CREATE INDEX event_source_lookup ON canonical_event (source_instance_id, source_object_type, source_object_id, source_revision);
CREATE INDEX dependency_incoming ON projection_membership (to_entity_id, edge_kind, projection_id);
CREATE INDEX dependency_outgoing ON projection_membership (from_entity_id, edge_kind, projection_id);
CREATE INDEX metric_subject_lookup ON metric_observation (visibility_scope, subject_id, metric_key, metric_version, computed_at);
CREATE INDEX evidence_digest_lookup ON evidence_object (visibility_scope, digest_algorithm, digest_value);
CREATE INDEX identity_current ON identity_assertion (account_id, scope, state, reviewed_at);
CREATE INDEX finding_open ON finding (subject_id, visibility_scope) WHERE state = 'open';
CREATE INDEX job_runnable ON job (priority DESC, next_attempt_at, created_at)
    WHERE state = 'queued' OR (state = 'running' AND lease_expires_at IS NOT NULL);
CREATE INDEX outbox_pending ON outbox_event (created_at) WHERE published_at IS NULL;

-- These methods keep claims and cursor advancement short, fenced, and
-- idempotent. Network fetches and parsing stay outside the transaction.
CREATE FUNCTION rh_claim_next_job(
    p_worker_id text,
    p_now timestamptz,
    p_lease_seconds integer
) RETURNS TABLE (job_id uuid, fencing_token bigint, lease_expires_at timestamptz)
LANGUAGE sql
AS $$
    WITH candidate AS (
        SELECT j.id
        FROM job AS j
        WHERE (j.state = 'queued' OR (j.state = 'running' AND j.lease_expires_at <= p_now))
          AND j.next_attempt_at <= p_now
        ORDER BY j.priority DESC, j.next_attempt_at, j.created_at, j.id
        FOR UPDATE SKIP LOCKED
        LIMIT 1
    ), claimed AS (
        UPDATE job AS j
        SET state = 'running',
            worker_id = p_worker_id,
            fencing_token = j.fencing_token + 1,
            lease_expires_at = p_now + (p_lease_seconds * interval '1 second'),
            attempt_count = j.attempt_count + 1
        FROM candidate AS c
        WHERE j.id = c.id
        RETURNING j.id, j.fencing_token, j.lease_expires_at, j.attempt_count
    ), recorded AS (
        INSERT INTO job_attempt (id, job_id, attempt_number, fencing_token, worker_id, started_at)
        SELECT md5(id::text || ':' || fencing_token::text)::uuid, id, attempt_count, fencing_token, p_worker_id, p_now
        FROM claimed
        RETURNING job_id
    )
    SELECT c.id, c.fencing_token, c.lease_expires_at
    FROM claimed AS c
    JOIN recorded AS r ON r.job_id = c.id;
$$;

CREATE FUNCTION rh_heartbeat_job(
    p_job_id uuid,
    p_fencing_token bigint,
    p_now timestamptz,
    p_lease_seconds integer
) RETURNS boolean
LANGUAGE sql
AS $$
    WITH renewed AS (
        UPDATE job
        SET lease_expires_at = p_now + (p_lease_seconds * interval '1 second')
        WHERE id = p_job_id
          AND state = 'running'
          AND fencing_token = p_fencing_token
          AND lease_expires_at > p_now
        RETURNING id
    )
    SELECT EXISTS (SELECT 1 FROM renewed);
$$;

CREATE FUNCTION rh_finish_job(
    p_job_id uuid,
    p_fencing_token bigint,
    p_state text,
    p_now timestamptz,
    p_outcome text DEFAULT NULL,
    p_error_kind text DEFAULT NULL
) RETURNS boolean
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_state NOT IN ('succeeded', 'failed', 'dead_letter', 'canceled') THEN
        RAISE EXCEPTION 'invalid terminal job state: %', p_state;
    END IF;

    UPDATE job
    SET state = p_state, lease_expires_at = NULL, finished_at = p_now
    WHERE id = p_job_id AND state = 'running' AND fencing_token = p_fencing_token;

    IF NOT FOUND THEN
        RETURN false;
    END IF;

    UPDATE job_attempt
    SET finished_at = p_now, outcome = p_outcome, error_kind = p_error_kind
    WHERE job_id = p_job_id AND fencing_token = p_fencing_token;
    RETURN true;
END;
$$;

CREATE FUNCTION rh_commit_collection_page(
    p_run_id uuid,
    p_page_number integer,
    p_scope_hash text,
    p_cursor_before jsonb,
    p_cursor_after jsonb,
    p_completeness text,
    p_record_count integer,
    p_evidence_id uuid,
    p_now timestamptz
) RETURNS boolean
LANGUAGE plpgsql
AS $$
DECLARE
    v_source_instance_id uuid;
    v_capability text;
    v_page_id uuid;
BEGIN
    IF p_completeness NOT IN ('complete', 'empty') THEN
        RAISE EXCEPTION 'a partial page cannot advance a durable cursor';
    END IF;

    SELECT source_instance_id, capability
    INTO v_source_instance_id, v_capability
    FROM collection_run
    WHERE id = p_run_id AND status = 'running';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'collection run is not running: %', p_run_id;
    END IF;

    INSERT INTO collection_page (
        id, collection_run_id, page_number, scope_hash,
        cursor_before, cursor_after, status, completeness,
        record_count, evidence_id, attempted_at, completed_at
    ) VALUES (
        md5(p_run_id::text || ':' || p_page_number::text)::uuid, p_run_id, p_page_number, p_scope_hash,
        p_cursor_before, p_cursor_after, 'success', p_completeness,
        p_record_count, p_evidence_id, p_now, p_now
    )
    ON CONFLICT (collection_run_id, page_number) DO NOTHING
    RETURNING id INTO v_page_id;

    IF v_page_id IS NULL THEN
        RETURN false;
    END IF;

    INSERT INTO collection_cursor (
        id, source_instance_id, capability, scope_hash, cursor,
        last_page_number, last_success_at, updated_at
    ) VALUES (
        md5(v_source_instance_id::text || ':' || v_capability || ':' || p_scope_hash)::uuid, v_source_instance_id, v_capability, p_scope_hash,
        COALESCE(p_cursor_after, '{}'::jsonb), p_page_number, p_now, p_now
    )
    ON CONFLICT (source_instance_id, capability, scope_hash)
    DO UPDATE SET cursor = EXCLUDED.cursor,
                  last_page_number = EXCLUDED.last_page_number,
                  last_success_at = EXCLUDED.last_success_at,
                  updated_at = EXCLUDED.updated_at
    WHERE collection_cursor.last_page_number < EXCLUDED.last_page_number;

    RETURN true;
END;
$$;

COMMIT;
