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
    CHECK (base_url ~ '^[A-Za-z][A-Za-z0-9+.-]*://[^/[:space:]@]+(/[^?#[:space:]]*)?$'),
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

-- Retain provider objects before normalization. collector_label is opaque
-- adapter-supplied context, not a source-native identity or deduplication key.
CREATE TABLE staged_source_record (
    collection_run_id uuid NOT NULL,
    page_number integer NOT NULL,
    record_ordinal integer NOT NULL CHECK (record_ordinal >= 0),
    collector_label text NOT NULL CHECK (length(collector_label) BETWEEN 1 AND 4096),
    raw_payload text NOT NULL CHECK (octet_length(raw_payload) BETWEEN 1 AND 1048576),
    captured_at timestamptz NOT NULL,
    PRIMARY KEY (collection_run_id, page_number, record_ordinal),
    FOREIGN KEY (collection_run_id, page_number)
        REFERENCES collection_page(collection_run_id, page_number)
);

CREATE INDEX staged_source_record_run_page
    ON staged_source_record (collection_run_id, page_number, record_ordinal);

-- A normalized staged run is an immutable, replayable projection of retained
-- provider records. The digest key distinguishes captured input/configuration;
-- the output digest detects an attempted rewrite of an existing projection.
CREATE TABLE staged_normalization (
    collection_run_id uuid NOT NULL REFERENCES collection_run(id),
    input_sha256 text NOT NULL CHECK (input_sha256 ~ '^[0-9a-f]{64}$'),
    configuration_sha256 text NOT NULL CHECK (configuration_sha256 ~ '^[0-9a-f]{64}$'),
    output_sha256 text NOT NULL CHECK (output_sha256 ~ '^[0-9a-f]{64}$'),
    normalizer_version text NOT NULL CHECK (length(normalizer_version) BETWEEN 1 AND 128),
    captured_at timestamptz NOT NULL,
    event_count integer NOT NULL CHECK (event_count BETWEEN 0 AND 10000),
    committed_at timestamptz NOT NULL,
    PRIMARY KEY (collection_run_id, input_sha256, configuration_sha256)
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

-- Graph queries are durable jobs with a bounded, immutable request and one
-- result published by the current fenced attempt.
CREATE TABLE graph_query_job (
    job_id uuid PRIMARY KEY REFERENCES job(id),
    request jsonb NOT NULL CHECK (jsonb_typeof(request) = 'object'),
    result jsonb CHECK (result IS NULL OR jsonb_typeof(result) = 'object'),
    result_fencing_token bigint CHECK (result_fencing_token IS NULL OR result_fencing_token > 0),
    completed_at timestamptz,
    CHECK ((result IS NULL AND result_fencing_token IS NULL AND completed_at IS NULL)
        OR (result IS NOT NULL AND result_fencing_token IS NOT NULL AND completed_at IS NOT NULL))
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

-- Register metadata only after the caller verifies the content-addressed blob.
-- The SHA-256 key is unique within visibility; retries are accepted only when
-- they present the same evidence identity and immutable metadata.
CREATE FUNCTION rh_register_evidence_object(
    p_id uuid,
    p_visibility_scope rh_visibility_scope,
    p_digest_value text,
    p_byte_length bigint,
    p_media_type text,
    p_storage_key text,
    p_retention_class text,
    p_transformation_kind text,
    p_created_at timestamptz
) RETURNS boolean
LANGUAGE plpgsql
AS $$
DECLARE
    v_existing evidence_object%ROWTYPE;
BEGIN
    IF p_digest_value IS NULL OR p_digest_value !~ '^[0-9a-f]{64}$' THEN
        RAISE EXCEPTION 'evidence digest must be a lowercase SHA-256 value';
    END IF;
    IF p_byte_length IS NULL OR p_byte_length < 0 OR p_byte_length > 67108864 THEN
        RAISE EXCEPTION 'evidence byte length is outside the bounded range';
    END IF;
    IF COALESCE(p_media_type, '') = '' OR COALESCE(p_storage_key, '') = ''
       OR COALESCE(p_retention_class, '') = '' OR COALESCE(p_transformation_kind, '') = '' THEN
        RAISE EXCEPTION 'evidence metadata fields must be non-empty';
    END IF;

    INSERT INTO evidence_object (
        id, visibility_scope, digest_algorithm, digest_value, media_type,
        byte_length, storage_key, retention_class, transformation_kind, created_at
    ) VALUES (
        p_id, p_visibility_scope, 'sha256', p_digest_value, p_media_type,
        p_byte_length, p_storage_key, p_retention_class, p_transformation_kind, p_created_at
    )
    ON CONFLICT (visibility_scope, digest_algorithm, digest_value) DO NOTHING;

    IF FOUND THEN
        RETURN true;
    END IF;

    SELECT * INTO v_existing
    FROM evidence_object
    WHERE visibility_scope = p_visibility_scope
      AND digest_algorithm = 'sha256'
      AND digest_value = p_digest_value;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'evidence digest conflict could not be read';
    END IF;
    IF v_existing.id IS DISTINCT FROM p_id
       OR v_existing.byte_length IS DISTINCT FROM p_byte_length
       OR v_existing.media_type IS DISTINCT FROM p_media_type
       OR v_existing.storage_key IS DISTINCT FROM p_storage_key
       OR v_existing.retention_class IS DISTINCT FROM p_retention_class
       OR v_existing.transformation_kind IS DISTINCT FROM p_transformation_kind
       OR v_existing.created_at IS DISTINCT FROM p_created_at THEN
        RAISE EXCEPTION 'evidence digest is already registered with different immutable metadata';
    END IF;
    RETURN false;
END;
$$;

-- Register a source configuration and its first collection run atomically.
-- Exact retries are harmless; reusing either identity with changed metadata
-- fails without leaving a half-created source or run.
CREATE FUNCTION rh_begin_collection_run(
    p_source_id uuid,
    p_source_kind text,
    p_source_base_url text,
    p_source_visibility_scope rh_visibility_scope,
    p_configuration_revision bigint,
    p_source_created_at timestamptz,
    p_run_id uuid,
    p_capability text,
    p_connector_name text,
    p_connector_version text,
    p_requested_start timestamptz,
    p_requested_end timestamptz,
    p_started_at timestamptz
) RETURNS boolean
LANGUAGE plpgsql
AS $$
DECLARE
    v_existing_source source_instance%ROWTYPE;
    v_existing_run collection_run%ROWTYPE;
BEGIN
    IF COALESCE(p_source_kind, '') = '' OR COALESCE(p_source_base_url, '') = ''
       OR COALESCE(p_capability, '') = '' OR COALESCE(p_connector_name, '') = ''
       OR COALESCE(p_connector_version, '') = '' THEN
        RAISE EXCEPTION 'collection source and connector metadata must be non-empty';
    END IF;
    IF p_source_base_url !~ '^[A-Za-z][A-Za-z0-9+.-]*://[^/[:space:]@]+(/[^?#[:space:]]*)?$' THEN
        RAISE EXCEPTION 'source base URL must be absolute and free of credentials, query, fragment, and whitespace';
    END IF;
    IF p_configuration_revision IS NULL OR p_configuration_revision <= 0 THEN
        RAISE EXCEPTION 'source configuration revision must be positive';
    END IF;
    IF p_requested_end IS NOT NULL AND p_requested_start IS NOT NULL
       AND p_requested_end <= p_requested_start THEN
        RAISE EXCEPTION 'requested collection end must follow its start';
    END IF;

    INSERT INTO source_instance (
        id, kind, base_url, visibility_scope, configuration_revision, created_at
    ) VALUES (
        p_source_id, p_source_kind, p_source_base_url, p_source_visibility_scope,
        p_configuration_revision, p_source_created_at
    ) ON CONFLICT (id) DO NOTHING;

    IF NOT FOUND THEN
        SELECT * INTO v_existing_source FROM source_instance WHERE id = p_source_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'source instance identity conflict could not be read';
        END IF;
        IF v_existing_source.kind IS DISTINCT FROM p_source_kind
           OR v_existing_source.base_url IS DISTINCT FROM p_source_base_url
           OR v_existing_source.visibility_scope IS DISTINCT FROM p_source_visibility_scope
           OR v_existing_source.configuration_revision IS DISTINCT FROM p_configuration_revision
           OR v_existing_source.created_at IS DISTINCT FROM p_source_created_at THEN
            RAISE EXCEPTION 'source instance identity is already registered with different immutable metadata';
        END IF;
    END IF;

    INSERT INTO collection_run (
        id, source_instance_id, capability, connector_name, connector_version,
        requested_start, requested_end, started_at, status, completeness
    ) VALUES (
        p_run_id, p_source_id, p_capability, p_connector_name, p_connector_version,
        p_requested_start, p_requested_end, p_started_at, 'running', 'unknown'
    ) ON CONFLICT (id) DO NOTHING;

    IF FOUND THEN
        RETURN true;
    END IF;

    SELECT * INTO v_existing_run FROM collection_run WHERE id = p_run_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'collection run identity conflict could not be read';
    END IF;
    IF v_existing_run.source_instance_id IS DISTINCT FROM p_source_id
       OR v_existing_run.capability IS DISTINCT FROM p_capability
       OR v_existing_run.connector_name IS DISTINCT FROM p_connector_name
       OR v_existing_run.connector_version IS DISTINCT FROM p_connector_version
       OR v_existing_run.requested_start IS DISTINCT FROM p_requested_start
       OR v_existing_run.requested_end IS DISTINCT FROM p_requested_end
       OR v_existing_run.started_at IS DISTINCT FROM p_started_at THEN
        RAISE EXCEPTION 'collection run identity is already registered with different immutable metadata';
    END IF;
    RETURN false;
END;
$$;

-- Queue a collection run with an immutable run binding. The worker performs
-- acquisition outside this transaction, then commits pages under the lease.
CREATE FUNCTION rh_enqueue_collection_job(
    p_run_id uuid,
    p_job_id uuid,
    p_priority integer,
    p_next_attempt_at timestamptz,
    p_created_at timestamptz
) RETURNS boolean
LANGUAGE plpgsql
AS $$
DECLARE
    v_source_instance_id uuid;
    v_visibility_scope rh_visibility_scope;
    v_run_status text;
    v_existing_job job%ROWTYPE;
BEGIN
    SELECT r.source_instance_id, s.visibility_scope, r.status
    INTO v_source_instance_id, v_visibility_scope, v_run_status
    FROM collection_run AS r
    JOIN source_instance AS s ON s.id = r.source_instance_id
    WHERE r.id = p_run_id
    FOR UPDATE OF r, s;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'collection run does not exist: %', p_run_id;
    END IF;

    SELECT * INTO v_existing_job
    FROM job
    WHERE id = p_job_id
    FOR UPDATE;
    IF FOUND THEN
        IF v_existing_job.source_instance_id IS DISTINCT FROM v_source_instance_id
           OR v_existing_job.kind IS DISTINCT FROM 'collection'
           OR v_existing_job.visibility_scope IS DISTINCT FROM v_visibility_scope
           OR v_existing_job.priority IS DISTINCT FROM p_priority
           OR v_existing_job.next_attempt_at IS DISTINCT FROM p_next_attempt_at
           OR v_existing_job.created_at IS DISTINCT FROM p_created_at
           OR v_existing_job.input_manifest IS DISTINCT FROM jsonb_build_object('collection_run_id', p_run_id::text) THEN
            RAISE EXCEPTION 'collection job identity is already registered with different immutable metadata';
        END IF;
        RETURN false;
    END IF;

    IF v_run_status IS DISTINCT FROM 'running' THEN
        RAISE EXCEPTION 'collection run is not running: %', p_run_id;
    END IF;
    IF p_created_at > p_next_attempt_at THEN
        RAISE EXCEPTION 'collection job cannot be scheduled before its creation time';
    END IF;

    INSERT INTO job (
        id, source_instance_id, kind, visibility_scope, state, priority,
        next_attempt_at, created_at, input_manifest
    ) VALUES (
        p_job_id, v_source_instance_id, 'collection', v_visibility_scope,
        'queued', p_priority, p_next_attempt_at, p_created_at,
        jsonb_build_object('collection_run_id', p_run_id::text)
    );
    RETURN true;
END;
$$;

-- These methods keep claims and cursor advancement short, fenced, and
-- idempotent. Network fetches and parsing stay outside the transaction.
CREATE FUNCTION rh_claim_next_job(
    p_worker_id text,
    p_now timestamptz,
    p_lease_seconds integer,
    p_job_id uuid DEFAULT NULL,
    p_job_kind text DEFAULT NULL
) RETURNS TABLE (job_id uuid, fencing_token bigint, lease_expires_at timestamptz)
LANGUAGE sql
AS $$
    WITH candidate AS (
        SELECT j.id
        FROM job AS j
        WHERE (j.state = 'queued' OR (j.state = 'running' AND j.lease_expires_at <= p_now))
          AND j.next_attempt_at <= p_now
          AND (p_job_id IS NULL OR j.id = p_job_id)
          AND (p_job_kind IS NULL OR j.kind = p_job_kind)
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
    ), expired AS (
        UPDATE job_attempt AS a
        SET finished_at = p_now,
            outcome = 'lease_expired',
            error_kind = 'lease_expired'
        FROM candidate AS c, claimed AS j
        WHERE a.job_id = c.id
          AND j.id = c.id
          AND a.fencing_token < j.fencing_token
          AND a.finished_at IS NULL
        RETURNING a.job_id
    ), recorded AS (
        INSERT INTO job_attempt (id, job_id, attempt_number, fencing_token, worker_id, started_at)
        SELECT md5(c.id::text || ':' || c.fencing_token::text)::uuid, c.id, c.attempt_count, c.fencing_token, p_worker_id, p_now
        FROM claimed AS c
        CROSS JOIN LATERAL (
            SELECT count(*) AS closed_attempts
            FROM expired
            WHERE expired.job_id = c.id
        ) AS prior_attempts
        WHERE prior_attempts.closed_attempts >= 0
        RETURNING job_id
    )
    SELECT c.id, c.fencing_token, c.lease_expires_at
    FROM claimed AS c
    JOIN recorded AS r ON r.job_id = c.id;
$$;

-- Claim one graph job and return its immutable input with the lease. The
-- request remains readable only through this fenced claim response.
CREATE FUNCTION rh_claim_graph_query_job(
    p_worker_id text,
    p_now timestamptz,
    p_lease_seconds integer,
    p_job_id uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_claim record;
    v_request jsonb;
BEGIN
    SELECT * INTO v_claim
    FROM rh_claim_next_job(p_worker_id, p_now, p_lease_seconds, p_job_id, 'graph_query');
    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'schema', 'rh-postgres-result/1',
            'operation', 'claim_graph_query_job',
            'status', 'empty'
        );
    END IF;

    SELECT request INTO v_request FROM graph_query_job WHERE job_id = v_claim.job_id;
    IF NOT FOUND OR v_request IS NULL THEN
        RAISE EXCEPTION 'claimed graph query job has no immutable request';
    END IF;
    RETURN jsonb_build_object(
        'schema', 'rh-postgres-result/1',
        'operation', 'claim_graph_query_job',
        'status', 'claimed',
        'job_id', v_claim.job_id::text,
        'fencing_token', v_claim.fencing_token,
        'lease_expires_at', v_claim.lease_expires_at,
        'request', v_request
    );
END;
$$;

-- A graph result can be published only by the live token returned above.
CREATE FUNCTION rh_read_graph_query_request(
    p_job_id uuid,
    p_fencing_token bigint,
    p_now timestamptz
) RETURNS jsonb
LANGUAGE sql
AS $$
    SELECT g.request
    FROM graph_query_job AS g
    JOIN job AS j ON j.id = g.job_id
    WHERE g.job_id = p_job_id
      AND j.kind = 'graph_query'
      AND j.state = 'running'
      AND j.fencing_token = p_fencing_token
      AND j.lease_expires_at > p_now
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
    WHERE id = p_job_id
      AND kind <> 'collection'
      AND (kind <> 'graph_query' OR p_state <> 'succeeded')
      AND state = 'running'
      AND fencing_token = p_fencing_token
      AND lease_expires_at > p_now;

    IF NOT FOUND THEN
        RETURN false;
    END IF;

    UPDATE job_attempt
    SET finished_at = p_now, outcome = p_outcome, error_kind = p_error_kind
    WHERE job_id = p_job_id AND fencing_token = p_fencing_token;
    RETURN true;
END;
$$;

-- Enqueue an immutable, bounded query request. Reusing a job ID is idempotent
-- only when scheduling metadata, visibility, and the complete request match.
CREATE FUNCTION rh_enqueue_graph_query_job(
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
BEGIN
    IF p_request IS NULL OR jsonb_typeof(p_request) IS DISTINCT FROM 'object'
       OR p_request->>'schema' IS DISTINCT FROM 'rh-query-input/1'
       OR jsonb_typeof(p_request->'ids') IS DISTINCT FROM 'array'
       OR pg_column_size(p_request) > 1048576 THEN
        RAISE EXCEPTION 'graph query request is malformed or exceeds the bounded payload limit';
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

-- Publish the bounded result and close the job/attempt atomically. A stale or
-- expired worker cannot overwrite a result after the job has been reclaimed.
CREATE FUNCTION rh_publish_graph_query_result(
    p_job_id uuid,
    p_fencing_token bigint,
    p_now timestamptz,
    p_result jsonb
) RETURNS boolean
LANGUAGE plpgsql
AS $$
DECLARE
    v_job job%ROWTYPE;
BEGIN
    IF p_result IS NULL OR jsonb_typeof(p_result) IS DISTINCT FROM 'object'
       OR p_result->>'schema' IS DISTINCT FROM 'rh-query-result/1'
       OR pg_column_size(p_result) > 1048576 THEN
        RAISE EXCEPTION 'graph query result is malformed or exceeds the bounded payload limit';
    END IF;

    SELECT * INTO v_job FROM job WHERE id = p_job_id FOR UPDATE;
    IF NOT FOUND OR v_job.kind IS DISTINCT FROM 'graph_query'
       OR v_job.state IS DISTINCT FROM 'running'
       OR v_job.fencing_token IS DISTINCT FROM p_fencing_token
       OR v_job.lease_expires_at <= p_now THEN
        RETURN false;
    END IF;

    UPDATE graph_query_job
    SET result = p_result,
        result_fencing_token = p_fencing_token,
        completed_at = p_now
    WHERE job_id = p_job_id AND result IS NULL;
    IF NOT FOUND THEN
        RETURN false;
    END IF;

    UPDATE job SET state = 'succeeded', lease_expires_at = NULL, finished_at = p_now
    WHERE id = p_job_id AND state = 'running' AND fencing_token = p_fencing_token;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'graph query job changed while publishing its result';
    END IF;

    UPDATE job_attempt SET finished_at = p_now, outcome = 'succeeded'
    WHERE job_id = p_job_id AND fencing_token = p_fencing_token AND finished_at IS NULL;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'graph query job attempt was not found for the current fencing token';
    END IF;
    RETURN true;
END;
$$;

-- Collection runs and their owning jobs finish together. This keeps a run from
-- appearing terminal while its lease is still active, or after that lease has
-- expired and may belong to a later worker.
CREATE FUNCTION rh_finish_collection_job(
    p_run_id uuid,
    p_job_id uuid,
    p_fencing_token bigint,
    p_job_state text,
    p_run_status text,
    p_completeness text,
    p_coverage_details jsonb,
    p_outcome text,
    p_error_kind text,
    p_now timestamptz
) RETURNS boolean
LANGUAGE plpgsql
AS $$
DECLARE
    v_source_instance_id uuid;
    v_job_source_instance_id uuid;
BEGIN
    IF p_job_state IS NULL OR p_job_state NOT IN ('succeeded', 'failed', 'dead_letter', 'canceled') THEN
        RAISE EXCEPTION 'invalid terminal job state: %', p_job_state;
    END IF;
    IF p_run_status IS NULL OR p_run_status NOT IN ('succeeded', 'partial', 'failed', 'canceled') THEN
        RAISE EXCEPTION 'invalid terminal collection run status: %', p_run_status;
    END IF;
    IF p_completeness IS NULL OR p_completeness NOT IN ('complete', 'partial', 'empty', 'unknown') THEN
        RAISE EXCEPTION 'invalid terminal collection completeness: %', p_completeness;
    END IF;
    IF p_coverage_details IS NULL OR jsonb_typeof(p_coverage_details) <> 'object'
       OR octet_length(p_coverage_details::text) > 1048576 THEN
        RAISE EXCEPTION 'collection coverage details must be a bounded JSON object';
    END IF;
    IF (p_run_status = 'succeeded' AND p_completeness NOT IN ('complete', 'empty'))
       OR (p_run_status = 'partial' AND p_completeness NOT IN ('partial', 'unknown'))
       OR (p_run_status IN ('failed', 'canceled') AND p_completeness NOT IN ('partial', 'unknown')) THEN
        RAISE EXCEPTION 'collection run status and completeness are inconsistent';
    END IF;
    IF (p_job_state = 'succeeded' AND p_run_status NOT IN ('succeeded', 'partial'))
       OR (p_job_state IN ('failed', 'dead_letter') AND p_run_status <> 'failed')
       OR (p_job_state = 'canceled' AND p_run_status <> 'canceled') THEN
        RAISE EXCEPTION 'collection job state and run status are inconsistent';
    END IF;

    SELECT source_instance_id INTO v_source_instance_id
    FROM collection_run
    WHERE id = p_run_id AND status = 'running'
    FOR UPDATE;
    IF NOT FOUND THEN
        RETURN false;
    END IF;

    SELECT source_instance_id INTO v_job_source_instance_id
    FROM job
    WHERE id = p_job_id
      AND kind = 'collection'
      AND state = 'running'
      AND fencing_token = p_fencing_token
      AND lease_expires_at > p_now
      AND input_manifest->>'collection_run_id' = p_run_id::text
    FOR UPDATE;
    IF NOT FOUND OR v_job_source_instance_id IS DISTINCT FROM v_source_instance_id THEN
        RETURN false;
    END IF;

    UPDATE collection_run
    SET status = p_run_status,
        completeness = p_completeness,
        coverage_details = p_coverage_details,
        finished_at = p_now
    WHERE id = p_run_id AND status = 'running';

    UPDATE job
    SET state = p_job_state, lease_expires_at = NULL, finished_at = p_now
    WHERE id = p_job_id AND state = 'running' AND fencing_token = p_fencing_token;

    UPDATE job_attempt
    SET finished_at = p_now, outcome = p_outcome, error_kind = p_error_kind
    WHERE job_id = p_job_id AND fencing_token = p_fencing_token;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'collection job attempt was not found for the current fencing token';
    END IF;
    RETURN true;
END;
$$;

CREATE FUNCTION rh_commit_collection_page(
    p_run_id uuid,
    p_job_id uuid,
    p_fencing_token bigint,
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
    v_job_source_instance_id uuid;
    v_capability text;
    v_page_id uuid;
BEGIN
    IF p_completeness IS NULL OR p_completeness NOT IN ('complete', 'empty') THEN
        RAISE EXCEPTION 'a partial page cannot advance a durable cursor';
    END IF;

    SELECT source_instance_id, capability
    INTO v_source_instance_id, v_capability
    FROM collection_run
    WHERE id = p_run_id AND status = 'running'
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'collection run is not running: %', p_run_id;
    END IF;
    SELECT source_instance_id INTO v_job_source_instance_id
    FROM job
    WHERE id = p_job_id
      AND kind = 'collection'
      AND state = 'running'
      AND fencing_token = p_fencing_token
      AND lease_expires_at > p_now
      AND input_manifest->>'collection_run_id' = p_run_id::text
    FOR UPDATE;
    IF NOT FOUND OR v_job_source_instance_id IS DISTINCT FROM v_source_instance_id THEN
        RAISE EXCEPTION 'collection page lease is stale, expired, or belongs to another source';
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

-- Persist an acquired page verbatim before normalization, using the same
-- fenced page/cursor transaction as normalized ingestion. The adapter label
-- remains a hint; only a normalizer may establish canonical event identity.
CREATE FUNCTION rh_commit_staged_collection_page(
    p_run_id uuid,
    p_job_id uuid,
    p_fencing_token bigint,
    p_page_number integer,
    p_scope_hash text,
    p_cursor_before jsonb,
    p_cursor_after jsonb,
    p_completeness text,
    p_evidence_id uuid,
    p_records jsonb,
    p_now timestamptz
) RETURNS boolean
LANGUAGE plpgsql
AS $$
DECLARE
    v_record jsonb;
    v_record_count integer;
    v_ordinal integer := 0;
    v_total_raw_bytes integer := 0;
    v_label text;
    v_raw_payload text;
    v_raw_object jsonb;
BEGIN
    IF p_records IS NULL OR jsonb_typeof(p_records) IS DISTINCT FROM 'array' THEN
        RAISE EXCEPTION 'staged page records must be a JSON array';
    END IF;
    v_record_count := jsonb_array_length(p_records);
    IF v_record_count > 10000 THEN
        RAISE EXCEPTION 'staged page record count exceeds the bounded record limit';
    END IF;
    IF octet_length(p_records::text) > 8388608 THEN
        RAISE EXCEPTION 'staged page envelope exceeds the bounded byte limit';
    END IF;

    FOR v_record IN SELECT value FROM jsonb_array_elements(p_records) AS records(value) LOOP
        IF jsonb_typeof(v_record) IS DISTINCT FROM 'object'
           OR jsonb_typeof(v_record->'collector_label') IS DISTINCT FROM 'string'
           OR jsonb_typeof(v_record->'raw_payload') IS DISTINCT FROM 'string' THEN
            RAISE EXCEPTION 'staged record is missing its collector label or raw payload';
        END IF;
        v_label := v_record->>'collector_label';
        v_raw_payload := v_record->>'raw_payload';
        IF length(v_label) < 1 OR length(v_label) > 4096 THEN
            RAISE EXCEPTION 'staged record collector label is outside the bounded range';
        END IF;
        IF octet_length(v_raw_payload) < 1 OR octet_length(v_raw_payload) > 1048576 THEN
            RAISE EXCEPTION 'staged record raw payload is outside the bounded range';
        END IF;
        v_total_raw_bytes := v_total_raw_bytes + octet_length(v_raw_payload);
        IF v_total_raw_bytes > 4194304 THEN
            RAISE EXCEPTION 'staged page raw payload bytes exceed the bounded aggregate limit';
        END IF;
        BEGIN
            v_raw_object := v_raw_payload::jsonb;
        EXCEPTION WHEN OTHERS THEN
            RAISE EXCEPTION 'staged record raw payload must be valid JSON';
        END;
        IF jsonb_typeof(v_raw_object) IS DISTINCT FROM 'object' THEN
            RAISE EXCEPTION 'staged record raw payload must be a JSON object';
        END IF;
    END LOOP;

    IF NOT rh_commit_collection_page(
        p_run_id, p_job_id, p_fencing_token, p_page_number, p_scope_hash,
        p_cursor_before, p_cursor_after, p_completeness, v_record_count,
        p_evidence_id, p_now
    ) THEN
        RETURN false;
    END IF;

    FOR v_record IN SELECT value FROM jsonb_array_elements(p_records) AS records(value) LOOP
        v_label := v_record->>'collector_label';
        v_raw_payload := v_record->>'raw_payload';
        INSERT INTO staged_source_record (
            collection_run_id, page_number, record_ordinal,
            collector_label, raw_payload, captured_at
        ) VALUES (
            p_run_id, p_page_number, v_ordinal,
            v_label, v_raw_payload, p_now
        );
        v_ordinal := v_ordinal + 1;
    END LOOP;
    RETURN true;
END;
$$;

-- Project a completed raw run into canonical observations. The run lock
-- serializes replay by the input/configuration key, and each event must point
-- back to an actual staged row and the page's registered evidence object.
CREATE FUNCTION rh_commit_staged_normalization(
    p_source_id uuid,
    p_run_id uuid,
    p_input_sha256 text,
    p_configuration_sha256 text,
    p_output_sha256 text,
    p_normalizer_version text,
    p_captured_at bigint,
    p_events jsonb
) RETURNS boolean
LANGUAGE plpgsql
AS $$
DECLARE
    v_source_visibility rh_visibility_scope;
    v_run_status text;
    v_run_completeness text;
    v_event jsonb;
    v_kind text;
    v_object_type text;
    v_entity_kind text;
    v_native_id text;
    v_source_revision text;
    v_page_number integer;
    v_record_ordinal integer;
    v_record_count integer;
    v_scope_hash text;
    v_source_object_id text;
    v_evidence_id uuid;
    v_page_evidence_id uuid;
    v_created_at bigint;
    v_subject_id uuid;
    v_existing_output_sha256 text;
    v_existing_normalizer_version text;
    v_existing_captured_at timestamptz;
    v_existing_event_count integer;
    v_event_count integer;
    v_manifest_exists boolean;
BEGIN
    IF p_input_sha256 IS NULL OR p_configuration_sha256 IS NULL OR p_output_sha256 IS NULL
       OR p_input_sha256 !~ '^[0-9a-f]{64}$'
       OR p_configuration_sha256 !~ '^[0-9a-f]{64}$'
       OR p_output_sha256 !~ '^[0-9a-f]{64}$' THEN
        RAISE EXCEPTION 'staged normalization digests must be lowercase SHA-256 values';
    END IF;
    IF p_normalizer_version IS NULL OR length(p_normalizer_version) < 1
       OR length(p_normalizer_version) > 128 THEN
        RAISE EXCEPTION 'staged normalization version is outside the bounded range';
    END IF;
    IF p_captured_at IS NULL OR p_captured_at < 0 OR p_captured_at > 253402300799 THEN
        RAISE EXCEPTION 'staged normalization capture time is outside the supported epoch range';
    END IF;
    IF p_events IS NULL OR jsonb_typeof(p_events) IS DISTINCT FROM 'array' THEN
        RAISE EXCEPTION 'staged normalized events must be a JSON array';
    END IF;
    v_event_count := jsonb_array_length(p_events);
    IF v_event_count > 10000 OR octet_length(p_events::text) > 16777216 THEN
        RAISE EXCEPTION 'staged normalized events exceed the bounded count or byte limit';
    END IF;

    SELECT s.visibility_scope, r.status, r.completeness
      INTO v_source_visibility, v_run_status, v_run_completeness
      FROM collection_run AS r
      JOIN source_instance AS s ON s.id = r.source_instance_id
     WHERE r.id = p_run_id AND r.source_instance_id = p_source_id
     FOR UPDATE OF r;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'staged normalization run does not belong to the declared source';
    END IF;
    IF v_run_status IS DISTINCT FROM 'succeeded'
       OR v_run_completeness NOT IN ('complete', 'empty') THEN
        RAISE EXCEPTION 'staged normalization requires a succeeded complete or empty run';
    END IF;
    IF EXISTS (
        SELECT 1 FROM collection_page AS p
         WHERE p.collection_run_id = p_run_id
           AND (p.status IS DISTINCT FROM 'success'
                OR p.completeness NOT IN ('complete', 'empty'))
    ) THEN
        RAISE EXCEPTION 'staged normalization run contains a failed or incomplete page';
    END IF;

    -- Preflight the whole projection before inserting any canonical rows.
    FOR v_event IN SELECT value FROM jsonb_array_elements(p_events) AS events(value) LOOP
        IF jsonb_typeof(v_event) IS DISTINCT FROM 'object'
           OR jsonb_typeof(v_event->'kind') IS DISTINCT FROM 'string'
           OR jsonb_typeof(v_event->'native_id') IS DISTINCT FROM 'string'
           OR jsonb_typeof(v_event->'created_at') IS DISTINCT FROM 'number'
           OR jsonb_typeof(v_event->'staged_origin') IS DISTINCT FROM 'object'
           OR jsonb_typeof(v_event->'staged_origin'->'page_number') IS DISTINCT FROM 'number'
           OR jsonb_typeof(v_event->'staged_origin'->'record_ordinal') IS DISTINCT FROM 'number'
           OR jsonb_typeof(v_event->'staged_origin'->'evidence_id') IS DISTINCT FROM 'string' THEN
            RAISE EXCEPTION 'staged normalized event is missing required canonical fields or provenance';
        END IF;
        v_kind := v_event->>'kind';
        v_native_id := v_event->>'native_id';
        IF v_kind = 'issues' THEN
            v_object_type := 'issue';
            v_entity_kind := 'forge_issue';
        ELSIF v_kind = 'proposals' THEN
            v_object_type := 'proposal';
            v_entity_kind := 'forge_proposal';
        ELSIF v_kind = 'reviews' THEN
            v_object_type := 'review';
            v_entity_kind := 'forge_review';
        ELSIF v_kind = 'releases' THEN
            v_object_type := 'release';
            v_entity_kind := 'forge_release';
        ELSE
            RAISE EXCEPTION 'staged normalized event kind is unsupported';
        END IF;
        IF length(v_native_id) < 1 OR length(v_native_id) > 512 THEN
            RAISE EXCEPTION 'staged normalized native identity is outside the bounded range';
        END IF;
        IF jsonb_typeof(v_event->'status') IS NOT NULL
           AND jsonb_typeof(v_event->'status') IS DISTINCT FROM 'string' THEN
            RAISE EXCEPTION 'staged normalized event status must be a string';
        END IF;
        IF (v_event->>'created_at') !~ '^(0|[1-9][0-9]*)$'
           OR (v_event->>'created_at')::numeric > 253402300799 THEN
            RAISE EXCEPTION 'staged normalized event creation time is outside the supported epoch range';
        END IF;
        IF (v_event->'staged_origin'->>'page_number') !~ '^(0|[1-9][0-9]*)$'
           OR (v_event->'staged_origin'->>'page_number')::numeric > 2147483647
           OR (v_event->'staged_origin'->>'record_ordinal') !~ '^(0|[1-9][0-9]*)$'
           OR (v_event->'staged_origin'->>'record_ordinal')::numeric > 2147483647 THEN
            RAISE EXCEPTION 'staged normalized source page or ordinal is outside the supported range';
        END IF;
        v_created_at := (v_event->>'created_at')::bigint;
        v_page_number := (v_event->'staged_origin'->>'page_number')::integer;
        v_record_ordinal := (v_event->'staged_origin'->>'record_ordinal')::integer;
        v_evidence_id := (v_event->'staged_origin'->>'evidence_id')::uuid;

        SELECT p.record_count, p.evidence_id, p.scope_hash
          INTO v_record_count, v_page_evidence_id, v_scope_hash
          FROM collection_page AS p
         WHERE p.collection_run_id = p_run_id
           AND p.page_number = v_page_number
           AND p.status = 'success'
           AND p.completeness IN ('complete', 'empty')
         FOR SHARE;
        IF NOT FOUND OR v_page_evidence_id IS DISTINCT FROM v_evidence_id
           OR v_record_ordinal >= v_record_count THEN
            RAISE EXCEPTION 'staged normalized event does not match a complete evidence-bearing source page';
        END IF;
        IF v_scope_hash IS NULL OR length(v_scope_hash) < 1 OR octet_length(v_scope_hash) > 4096 THEN
            RAISE EXCEPTION 'staged normalized source page has no bounded scope identity';
        END IF;
        PERFORM 1 FROM staged_source_record AS staged
         WHERE staged.collection_run_id = p_run_id
           AND staged.page_number = v_page_number
           AND staged.record_ordinal = v_record_ordinal
         FOR KEY SHARE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'staged normalized event does not match a retained source record';
        END IF;
    END LOOP;

    IF EXISTS (
        SELECT 1
          FROM jsonb_array_elements(p_events) AS events(value)
         GROUP BY value->>'kind', value->>'native_id'
        HAVING count(*) > 1
    ) THEN
        RAISE EXCEPTION 'staged normalized events contain duplicate object identities';
    END IF;

    v_source_revision := 'staged-normalization/1:' || p_input_sha256 || ':' || p_configuration_sha256;
    SELECT output_sha256, normalizer_version, captured_at, event_count
      INTO v_existing_output_sha256, v_existing_normalizer_version,
           v_existing_captured_at, v_existing_event_count
      FROM staged_normalization
     WHERE collection_run_id = p_run_id
       AND input_sha256 = p_input_sha256
       AND configuration_sha256 = p_configuration_sha256
     FOR UPDATE;
    v_manifest_exists := FOUND;
    IF v_manifest_exists THEN
        IF v_existing_output_sha256 IS DISTINCT FROM p_output_sha256
           OR v_existing_normalizer_version IS DISTINCT FROM p_normalizer_version
           OR v_existing_captured_at IS DISTINCT FROM to_timestamp(p_captured_at)
           OR v_existing_event_count IS DISTINCT FROM v_event_count THEN
            RAISE EXCEPTION 'staged normalization identity is already committed with different output metadata';
        END IF;
        IF (SELECT count(*) FROM canonical_event AS event
             WHERE event.source_instance_id = p_source_id
               AND event.source_revision = v_source_revision) <> v_event_count THEN
            RAISE EXCEPTION 'staged normalization manifest does not match its committed canonical event set';
        END IF;
        FOR v_event IN SELECT value FROM jsonb_array_elements(p_events) AS events(value) LOOP
            v_kind := v_event->>'kind';
            v_native_id := v_event->>'native_id';
            v_object_type := CASE v_kind
                WHEN 'issues' THEN 'issue'
                WHEN 'proposals' THEN 'proposal'
                WHEN 'reviews' THEN 'review'
                ELSE 'release'
            END;
            v_page_number := (v_event->'staged_origin'->>'page_number')::integer;
            v_evidence_id := (v_event->'staged_origin'->>'evidence_id')::uuid;
            SELECT p.scope_hash INTO v_scope_hash
              FROM collection_page AS p
             WHERE p.collection_run_id = p_run_id AND p.page_number = v_page_number;
            v_source_object_id := json_build_array(v_scope_hash, v_native_id)::text;
            v_subject_id := md5(p_source_id::text || ':' || v_object_type || ':' ||
                octet_length(v_scope_hash)::text || ':' || v_scope_hash || ':' || v_native_id)::uuid;
            PERFORM 1 FROM canonical_event AS event
             WHERE event.source_instance_id = p_source_id
               AND event.source_object_type = v_object_type
               AND event.source_object_id = v_source_object_id
               AND event.source_revision = v_source_revision
               AND event.event_kind = 'state_observation'
               AND event.subject_id = v_subject_id
               AND event.actor_account_id IS NULL
               AND event.occurred_at IS NULL
               AND event.observed_at = to_timestamp(p_captured_at)
               AND event.time_basis = 'observation'
               AND event.evidence_id = v_evidence_id
               AND event.parser_version = p_normalizer_version
               AND event.payload = v_event;
            IF NOT FOUND THEN
                RAISE EXCEPTION 'staged normalization replay differs from its committed canonical event payload';
            END IF;
        END LOOP;
        RETURN false;
    END IF;

    FOR v_event IN SELECT value FROM jsonb_array_elements(p_events) AS events(value) LOOP
        v_kind := v_event->>'kind';
        v_native_id := v_event->>'native_id';
        v_object_type := CASE v_kind
            WHEN 'issues' THEN 'issue'
            WHEN 'proposals' THEN 'proposal'
            WHEN 'reviews' THEN 'review'
            ELSE 'release'
        END;
        v_entity_kind := 'forge_' || v_object_type;
        v_created_at := (v_event->>'created_at')::bigint;
        v_page_number := (v_event->'staged_origin'->>'page_number')::integer;
        v_record_ordinal := (v_event->'staged_origin'->>'record_ordinal')::integer;
        v_evidence_id := (v_event->'staged_origin'->>'evidence_id')::uuid;
        SELECT p.scope_hash INTO v_scope_hash
          FROM collection_page AS p
         WHERE p.collection_run_id = p_run_id AND p.page_number = v_page_number;
        v_source_object_id := json_build_array(v_scope_hash, v_native_id)::text;
        v_subject_id := md5(p_source_id::text || ':' || v_object_type || ':' ||
            octet_length(v_scope_hash)::text || ':' || v_scope_hash || ':' || v_native_id)::uuid;

        INSERT INTO entity (id, entity_kind, visibility_scope, created_at)
        VALUES (v_subject_id, v_entity_kind, v_source_visibility, to_timestamp(v_created_at))
        ON CONFLICT (id) DO NOTHING;
        IF NOT EXISTS (
            SELECT 1 FROM entity AS e
             WHERE e.id = v_subject_id
               AND e.entity_kind = v_entity_kind
               AND e.visibility_scope = v_source_visibility
               AND e.created_at = to_timestamp(v_created_at)
        ) THEN
            RAISE EXCEPTION 'staged normalized subject identity conflicts with immutable entity metadata';
        END IF;

        INSERT INTO canonical_event (
            id, source_instance_id, source_object_type, source_object_id,
            source_revision, event_kind, subject_id, actor_account_id,
            occurred_at, observed_at, time_basis, evidence_id, parser_version, payload
        ) VALUES (
            md5(p_source_id::text || ':' || v_object_type || ':' || v_source_object_id || ':' || v_source_revision)::uuid,
            p_source_id, v_object_type, v_source_object_id, v_source_revision,
            'state_observation', v_subject_id, NULL, NULL,
            to_timestamp(p_captured_at), 'observation', v_evidence_id,
            p_normalizer_version, v_event
        );
    END LOOP;

    INSERT INTO staged_normalization (
        collection_run_id, input_sha256, configuration_sha256, output_sha256,
        normalizer_version, captured_at, event_count, committed_at
    ) VALUES (
        p_run_id, p_input_sha256, p_configuration_sha256, p_output_sha256,
        p_normalizer_version, to_timestamp(p_captured_at), v_event_count, clock_timestamp()
    );
    RETURN true;
END;
$$;

-- Commit one complete provider page together with its normalized events. The
-- run and live job rows serialize page replay and fence stale workers; event
-- uniqueness absorbs record replays, and bad input rolls back the page/cursor.
CREATE FUNCTION rh_commit_collection_page_events(
    p_run_id uuid,
    p_job_id uuid,
    p_fencing_token bigint,
    p_page_number integer,
    p_scope_hash text,
    p_cursor_before jsonb,
    p_cursor_after jsonb,
    p_completeness text,
    p_record_count integer,
    p_evidence_id uuid,
    p_events jsonb,
    p_subjects jsonb,
    p_actors jsonb,
    p_now timestamptz
) RETURNS boolean
LANGUAGE plpgsql
AS $$
DECLARE
    v_source_instance_id uuid;
    v_job_source_instance_id uuid;
    v_capability text;
    v_event jsonb;
    v_event_count integer;
    v_subject jsonb;
    v_subject_count integer;
    v_subject_id uuid;
    v_subject_kind text;
    v_subject_visibility rh_visibility_scope;
    v_subject_created_at timestamptz;
    v_existing_entity entity%ROWTYPE;
    v_actor jsonb;
    v_actor_count integer;
    v_actor_id uuid;
    v_actor_native_id text;
    v_actor_kind text;
    v_actor_display_name text;
    v_actor_evidence_id uuid;
    v_actor_visibility rh_visibility_scope;
    v_actor_matches integer;
    v_existing_account account%ROWTYPE;
BEGIN
    IF p_completeness IS NULL OR p_completeness NOT IN ('complete', 'empty') THEN
        RAISE EXCEPTION 'a partial page cannot advance a durable cursor';
    END IF;
    IF p_page_number IS NULL OR p_record_count IS NULL OR p_page_number < 0 OR p_record_count < 0 THEN
        RAISE EXCEPTION 'page number and record count must be non-negative';
    END IF;
    IF p_events IS NULL OR jsonb_typeof(p_events) <> 'array' THEN
        RAISE EXCEPTION 'page events must be a JSON array';
    END IF;
    v_event_count := jsonb_array_length(p_events);
    IF v_event_count > 10000 OR v_event_count <> p_record_count THEN
        RAISE EXCEPTION 'page event count does not match the declared bounded record count';
    END IF;
    IF p_subjects IS NULL OR jsonb_typeof(p_subjects) <> 'array' THEN
        RAISE EXCEPTION 'page subjects must be a JSON array';
    END IF;
    v_subject_count := jsonb_array_length(p_subjects);
    IF v_subject_count > 10000 THEN
        RAISE EXCEPTION 'page subject count exceeds the bounded record limit';
    END IF;
    IF p_actors IS NULL OR jsonb_typeof(p_actors) <> 'array' THEN
        RAISE EXCEPTION 'page actors must be a JSON array';
    END IF;
    v_actor_count := jsonb_array_length(p_actors);
    IF v_actor_count > 10000 THEN
        RAISE EXCEPTION 'page actor count exceeds the bounded record limit';
    END IF;

    SELECT source_instance_id, capability
    INTO v_source_instance_id, v_capability
    FROM collection_run
    WHERE id = p_run_id AND status = 'running'
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'collection run is not running: %', p_run_id;
    END IF;
    SELECT source_instance_id INTO v_job_source_instance_id
    FROM job
    WHERE id = p_job_id
      AND kind = 'collection'
      AND state = 'running'
      AND fencing_token = p_fencing_token
      AND lease_expires_at > p_now
      AND input_manifest->>'collection_run_id' = p_run_id::text
    FOR UPDATE;
    IF NOT FOUND OR v_job_source_instance_id IS DISTINCT FROM v_source_instance_id THEN
        RAISE EXCEPTION 'collection page lease is stale, expired, or belongs to another source';
    END IF;

    IF EXISTS (
        SELECT 1 FROM collection_page
        WHERE collection_run_id = p_run_id AND page_number = p_page_number
    ) THEN
        RETURN false;
    END IF;

    INSERT INTO collection_page (
        id, collection_run_id, page_number, scope_hash,
        cursor_before, cursor_after, status, completeness,
        record_count, evidence_id, attempted_at, completed_at
    ) VALUES (
        md5(p_run_id::text || ':' || p_page_number::text)::uuid,
        p_run_id, p_page_number, p_scope_hash,
        p_cursor_before, p_cursor_after, 'success', p_completeness,
        p_record_count, p_evidence_id, p_now, p_now
    );

    FOR v_subject IN SELECT value FROM jsonb_array_elements(p_subjects) AS subjects(value) LOOP
        IF jsonb_typeof(v_subject) IS DISTINCT FROM 'object'
           OR jsonb_typeof(v_subject->'id') IS DISTINCT FROM 'string'
           OR jsonb_typeof(v_subject->'entity_kind') IS DISTINCT FROM 'string'
           OR jsonb_typeof(v_subject->'visibility_scope') IS DISTINCT FROM 'string'
           OR jsonb_typeof(v_subject->'created_at') IS DISTINCT FROM 'string' THEN
            RAISE EXCEPTION 'page subject is missing a required typed field';
        END IF;
        IF COALESCE(v_subject->>'id', '') = '' OR COALESCE(v_subject->>'entity_kind', '') = '' THEN
            RAISE EXCEPTION 'page subject identity and entity kind must be non-empty';
        END IF;

        v_subject_id := (v_subject->>'id')::uuid;
        v_subject_kind := v_subject->>'entity_kind';
        v_subject_visibility := (v_subject->>'visibility_scope')::rh_visibility_scope;
        v_subject_created_at := (v_subject->>'created_at')::timestamptz;
        INSERT INTO entity (id, entity_kind, visibility_scope, created_at)
        VALUES (v_subject_id, v_subject_kind, v_subject_visibility, v_subject_created_at)
        ON CONFLICT (id) DO NOTHING;

        IF NOT FOUND THEN
            SELECT * INTO v_existing_entity FROM entity WHERE id = v_subject_id;
            IF NOT FOUND THEN
                RAISE EXCEPTION 'page subject identity conflict could not be read';
            END IF;
            IF v_existing_entity.entity_kind IS DISTINCT FROM v_subject_kind
               OR v_existing_entity.visibility_scope IS DISTINCT FROM v_subject_visibility
               OR v_existing_entity.created_at IS DISTINCT FROM v_subject_created_at THEN
                RAISE EXCEPTION 'page subject identity is already registered with different immutable metadata';
            END IF;
        END IF;
    END LOOP;

    FOR v_actor IN SELECT value FROM jsonb_array_elements(p_actors) AS actors(value) LOOP
        IF jsonb_typeof(v_actor) IS DISTINCT FROM 'object'
           OR jsonb_typeof(v_actor->'id') IS DISTINCT FROM 'string'
           OR jsonb_typeof(v_actor->'source_native_id') IS DISTINCT FROM 'string'
           OR jsonb_typeof(v_actor->'account_kind') IS DISTINCT FROM 'string'
           OR (jsonb_typeof(v_actor->'display_name') IS DISTINCT FROM 'string'
               AND jsonb_typeof(v_actor->'display_name') IS DISTINCT FROM 'null')
           OR (jsonb_typeof(v_actor->'raw_identity_evidence_id') IS DISTINCT FROM 'string'
               AND jsonb_typeof(v_actor->'raw_identity_evidence_id') IS DISTINCT FROM 'null')
           OR jsonb_typeof(v_actor->'visibility_scope') IS DISTINCT FROM 'string' THEN
            RAISE EXCEPTION 'page actor is missing a required typed field';
        END IF;
        IF COALESCE(v_actor->>'id', '') = '' OR COALESCE(v_actor->>'source_native_id', '') = ''
           OR v_actor->>'account_kind' NOT IN ('human', 'bot', 'service', 'organization', 'unknown') THEN
            RAISE EXCEPTION 'page actor identity or account kind is invalid';
        END IF;
        IF jsonb_typeof(v_actor->'raw_identity_evidence_id') = 'string'
           AND COALESCE(v_actor->>'raw_identity_evidence_id', '') = '' THEN
            RAISE EXCEPTION 'page actor evidence identity must be non-empty or null';
        END IF;

        v_actor_id := (v_actor->>'id')::uuid;
        v_actor_native_id := v_actor->>'source_native_id';
        v_actor_kind := v_actor->>'account_kind';
        v_actor_display_name := v_actor->>'display_name';
        v_actor_evidence_id := NULLIF(v_actor->>'raw_identity_evidence_id', '')::uuid;
        v_actor_visibility := (v_actor->>'visibility_scope')::rh_visibility_scope;
        INSERT INTO account (
            id, source_instance_id, source_native_id, account_kind, display_name,
            raw_identity_evidence_id, visibility_scope
        ) VALUES (
            v_actor_id, v_source_instance_id, v_actor_native_id, v_actor_kind,
            v_actor_display_name, v_actor_evidence_id, v_actor_visibility
        ) ON CONFLICT DO NOTHING;

        IF NOT FOUND THEN
            SELECT count(*) INTO v_actor_matches FROM account
            WHERE id = v_actor_id
               OR (source_instance_id = v_source_instance_id AND source_native_id = v_actor_native_id);
            IF v_actor_matches <> 1 THEN
                RAISE EXCEPTION 'page actor identity conflict could not be resolved';
            END IF;
            SELECT * INTO v_existing_account FROM account
            WHERE id = v_actor_id
               OR (source_instance_id = v_source_instance_id AND source_native_id = v_actor_native_id);
            IF NOT FOUND THEN
                RAISE EXCEPTION 'page actor identity conflict could not be read';
            END IF;
            IF v_existing_account.id IS DISTINCT FROM v_actor_id
               OR v_existing_account.source_instance_id IS DISTINCT FROM v_source_instance_id
               OR v_existing_account.source_native_id IS DISTINCT FROM v_actor_native_id
               OR v_existing_account.account_kind IS DISTINCT FROM v_actor_kind
               OR v_existing_account.display_name IS DISTINCT FROM v_actor_display_name
               OR v_existing_account.raw_identity_evidence_id IS DISTINCT FROM v_actor_evidence_id
               OR v_existing_account.visibility_scope IS DISTINCT FROM v_actor_visibility THEN
                RAISE EXCEPTION 'page actor identity is already registered with different immutable metadata';
            END IF;
        END IF;
    END LOOP;

    FOR v_event IN SELECT value FROM jsonb_array_elements(p_events) AS events(value) LOOP
        IF jsonb_typeof(v_event) IS DISTINCT FROM 'object'
           OR jsonb_typeof(v_event->'source_object_type') IS DISTINCT FROM 'string'
           OR jsonb_typeof(v_event->'source_object_id') IS DISTINCT FROM 'string'
           OR jsonb_typeof(v_event->'source_revision') IS DISTINCT FROM 'string'
           OR jsonb_typeof(v_event->'event_kind') IS DISTINCT FROM 'string'
           OR jsonb_typeof(v_event->'subject_id') IS DISTINCT FROM 'string'
           OR jsonb_typeof(v_event->'observed_at') IS DISTINCT FROM 'string'
           OR jsonb_typeof(v_event->'time_basis') IS DISTINCT FROM 'string'
           OR jsonb_typeof(v_event->'evidence_id') IS DISTINCT FROM 'string'
           OR jsonb_typeof(v_event->'parser_version') IS DISTINCT FROM 'string'
           OR jsonb_typeof(v_event->'payload') IS DISTINCT FROM 'object' THEN
            RAISE EXCEPTION 'page event is missing a required typed field';
        END IF;
        IF COALESCE(v_event->>'source_object_type', '') = ''
           OR COALESCE(v_event->>'source_object_id', '') = ''
           OR COALESCE(v_event->>'source_revision', '') = ''
           OR COALESCE(v_event->>'event_kind', '') = ''
           OR COALESCE(v_event->>'parser_version', '') = ''
           OR v_event->>'time_basis' NOT IN ('event', 'observation', 'unknown') THEN
            RAISE EXCEPTION 'page event identity, parser, or time basis is invalid';
        END IF;
        IF v_event ? 'actor_account_id'
           AND jsonb_typeof(v_event->'actor_account_id') NOT IN ('string', 'null') THEN
            RAISE EXCEPTION 'page event actor_account_id must be a UUID string or null';
        END IF;
        IF v_event ? 'occurred_at'
           AND jsonb_typeof(v_event->'occurred_at') NOT IN ('string', 'null') THEN
            RAISE EXCEPTION 'page event occurred_at must be a timestamp string or null';
        END IF;

        INSERT INTO canonical_event (
            id, source_instance_id, source_object_type, source_object_id,
            source_revision, event_kind, subject_id, actor_account_id,
            occurred_at, observed_at, time_basis, evidence_id,
            parser_version, payload
        ) VALUES (
            md5(v_source_instance_id::text || ':' || (v_event->>'source_object_type') || ':' ||
                (v_event->>'source_object_id') || ':' || (v_event->>'source_revision') || ':' ||
                (v_event->>'event_kind'))::uuid,
            v_source_instance_id,
            v_event->>'source_object_type',
            v_event->>'source_object_id',
            v_event->>'source_revision',
            v_event->>'event_kind',
            (v_event->>'subject_id')::uuid,
            NULLIF(v_event->>'actor_account_id', '')::uuid,
            NULLIF(v_event->>'occurred_at', '')::timestamptz,
            (v_event->>'observed_at')::timestamptz,
            v_event->>'time_basis',
            (v_event->>'evidence_id')::uuid,
            v_event->>'parser_version',
            v_event->'payload'
        ) ON CONFLICT (
            source_instance_id, source_object_type, source_object_id,
            source_revision, event_kind
        ) DO NOTHING;
    END LOOP;

    INSERT INTO collection_cursor (
        id, source_instance_id, capability, scope_hash, cursor,
        last_page_number, last_success_at, updated_at
    ) VALUES (
        md5(v_source_instance_id::text || ':' || v_capability || ':' || p_scope_hash)::uuid,
        v_source_instance_id, v_capability, p_scope_hash,
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
