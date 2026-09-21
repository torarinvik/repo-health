#!/usr/bin/env bash
# tests/test_migrations.sh — M02-01 PostgreSQL target-schema contract.
#
# PostgreSQL is intentionally not required by the deterministic local gate.
# This test checks the migration's complete table/function vocabulary and
# safety invariants without pretending that a static check is a database run.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SQL="$ROOT/db/migrations/001_initial.sql"

fail() { echo "[migrations] FAIL: $1" >&2; exit 1; }
[[ -f "$SQL" ]] || fail "initial migration is missing"

python3 - "$SQL" <<'PY'
import re
import sys
from pathlib import Path

sql = Path(sys.argv[1]).read_text(encoding="utf-8")
clean = re.sub(r"--[^\n]*", "", sql)
tables = set(re.findall(r"CREATE TABLE\s+([a-z_][a-z0-9_]*)", clean, re.I))
functions = set(re.findall(r"CREATE FUNCTION\s+([a-z_][a-z0-9_]*)", clean, re.I))

required_tables = {
    "source_instance", "capability_observation", "credential_reference",
    "collection_run", "collection_page", "collection_cursor", "job", "job_attempt",
    "entity", "project", "repository", "repository_location", "repository_snapshot",
    "revision", "revision_membership", "ref_observation", "account",
    "actor_cluster_revision", "identity_assertion", "role_assertion",
    "change_proposal", "change_revision", "review_event", "issue_state", "issue_event",
    "package", "package_version", "artifact", "artifact_location",
    "project_package_assertion", "dependency_requirement", "resolution_snapshot",
    "resolved_dependency_edge", "graph_projection", "projection_membership",
    "advisory_record", "advisory_alias_assertion", "affected_version_assertion",
    "evidence_object", "evidence_access_rule", "evidence_retention_rule",
    "canonical_event", "metric_definition", "metric_run", "metric_observation",
    "metric_input_manifest", "finding", "finding_revision", "policy_definition",
    "policy_evaluation", "exception", "correction_case", "publication_record",
    "audit_event", "outbox_event",
}
missing = sorted(required_tables - tables)
assert not missing, f"missing tables: {missing}"
assert {"rh_register_evidence_object", "rh_begin_collection_run", "rh_claim_next_job", "rh_heartbeat_job", "rh_finish_job", "rh_commit_collection_page", "rh_commit_collection_page_events"} <= functions
assert clean.lstrip().startswith("BEGIN;") and clean.rstrip().endswith("COMMIT;")
assert "FOR UPDATE SKIP LOCKED" in clean
assert "fencing_token" in clean and "lease_expires_at" in clean
assert "ON CONFLICT (collection_run_id, page_number) DO NOTHING" in clean
assert "jsonb_array_elements(p_events)" in clean
assert "jsonb_array_elements(p_subjects)" in clean
assert "jsonb_array_elements(p_actors)" in clean
assert "page subjects must be a JSON array" in clean
assert "page actors must be a JSON array" in clean
assert "page subject identity is already registered with different immutable metadata" in clean
assert "page actor identity is already registered with different immutable metadata" in clean
assert "source instance identity is already registered with different immutable metadata" in clean
assert "collection run identity is already registered with different immutable metadata" in clean
assert "source base URL must be absolute and free of credentials, query, fragment, and whitespace" in clean
assert "evidence digest must be a lowercase SHA-256 value" in clean
assert "evidence digest is already registered with different immutable metadata" in clean
assert "page event count does not match the declared bounded record count" in clean
assert "ON CONFLICT (" in clean and "DO NOTHING" in clean
assert "a partial page cannot advance a durable cursor" in clean
assert "UPDATE job" in clean and "fencing_token = p_fencing_token" in clean

for ref in re.findall(r"\bREFERENCES\s+([a-z_][a-z0-9_]*)", clean, re.I):
    assert ref in tables, f"foreign key target is undeclared: {ref}"

for fragment in (
    "UNIQUE (source_instance_id, source_kind, source_native_id)",
    "UNIQUE (source_instance_id, source_object_type, source_object_id, source_revision, event_kind)",
    "UNIQUE (visibility_scope, digest_algorithm, digest_value)",
    "CREATE INDEX dependency_incoming",
    "CREATE INDEX dependency_outgoing",
    "CREATE INDEX evidence_digest_lookup",
    "CREATE INDEX metric_subject_lookup",
):
    assert fragment in clean, f"missing invariant/index: {fragment}"

# The database stores only a locator for transport credentials. A migration
# must never introduce a raw secret column or a plaintext credential payload.
assert "secret_value" not in clean.lower()
assert "secret_locator" in clean
print(f"[migrations] target contract OK: {len(tables)} tables, {len(functions)} functions")
PY

if [[ "${RH_PG_MIGRATION:-0}" == "1" ]]; then
  "$ROOT/tests/test_migrations_live.sh"
else
  echo "[migrations] live PostgreSQL rehearsal skipped (RH_PG_MIGRATION!=1)"
fi

echo "test_migrations OK"
