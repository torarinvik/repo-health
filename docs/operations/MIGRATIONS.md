# Migrations and rollback

The Elisa reference implementation keeps its active durable state in a
filesystem store (`src/rh_store.elisa`). The planned server persistence
contract is captured in
[`db/migrations/001_initial.sql`](../../db/migrations/001_initial.sql): it
defines typed PostgreSQL tables, visibility scope, source-scoped identity,
evidence references, indexes, and fenced job/cursor methods. The migration is
not applied by the local CLI, so the SQL file is a target contract and not
evidence of a deployed database.

The first application method is in [`src/rh_postgres.elisa`](../../src/rh_postgres.elisa).
It dynamically loads `libpq` and commits one complete or successful-empty
collection page through `rh_commit_collection_page`, and exposes fenced job
claim, heartbeat, and finish methods. It binds values through `PQexecParams`, applies
a five-second connection timeout, and returns separate committed/duplicate or
current/stale/failure outcomes. Set `RH_LIBPQ_PATH` when
the library is outside the platform loader path; otherwise the adapter checks
the standard Homebrew paths on macOS and `libpq.so.5` on Linux. Supply the
connection string through the calling Elisa program, never through a shell
command. Remote connection strings should use `sslmode=verify-full` and a
trusted root certificate. The mock ABI gate is `tests/test_pg_adapter.sh`; set
`RH_PG_ADAPTER=1` and optionally `RH_LIBPQ_PATH` to run these operations
against an ephemeral PostgreSQL instance with `tests/test_pg_adapter_live.sh`.

## Versioned things that can change

| Artifact | Version marker | Where |
|---|---|---|
| Public schemas | `rh-jsonschema/1` dialect, per-schema `name` | `schemas/*.schema.json` |
| Dependency graph | `rh-dep-graph/1` | `fixtures/packages/*.golden.json` |
| Temporal downstream report | `rh-downstream/2` | `rh_cli downstream` with explicit projection filters |
| Canonical repo | `rh-canonical-repo/1` | `fixtures/connectors/*.canonical.json` |
| Evidence bundle | manifest schema versions | `bundle.manifest` |
| Metric definitions | `key` + `version` | `metrics/definitions/*.json` |
| Benchmark manifest | `rh-bench/3` | `build/bench-manifest.json` |
| Profile manifest | `rh-profile/3` | `build/profile-manifest.json` |
| Release packet | `rh-release-packet/1` | `build/release-packet.json` |
| Source register | `rh-source-review/1` | `ops/source-review-register.json` |
| PostgreSQL target schema | migration `001` | `db/migrations/001_initial.sql` |

## Rules

1. **No silent reinterpretation.** A format change ships under a new
   version string. Readers must reject or report `unsupported` for a
   version they do not know (e.g. CycloneDX and SPDX parsers report
   `spec_unsupported`), never guess.
2. **Schema tests are independent of generated code.** `tools/schema-check.sh`
   validates the checked-in fixtures directly; `tests/test_schemas.sh`
   includes a negative control so an over-permissive checker cannot pass.
3. **Replayability is explicit.** After a change, any report whose pinned
   inputs no longer verify is labelled `not_replayable`
   (`rh_replay_label`), and no live data is substituted into a pinned
   report.
4. **Backup before migration.** Use `rh_backup_write` + `rh_backup_verify`
   to record a verified object set, restore into a clean directory, and
   replay a sample; a restore that skips corrupt objects is expected
   (`rh_backup_restore`).
5. **Rollback = restore + replay, not reverse-patching.** Because derived
   results carry their revision and inputs, rollback is: restore the prior
   evidence set, recompute, and compare against the pinned expected output.
   If the prior inputs are gone, the correct outcome is `not_replayable`,
   not a recomputation from current data.
6. **Toolchain pinning.** `TOOLCHAIN.md` pins the Elisa stage1 snapshot and
   no automation uses `latest`. A toolchain change is a migration: rebuild,
   re-run the suite, and record the compiler revision in the release packet.
7. **PostgreSQL target validation is explicit.** `tests/test_migrations.sh`
   checks the migration vocabulary, foreign-key targets, fencing primitives,
   source-scoped uniqueness, and secret-locator boundary without claiming a
   live PostgreSQL execution. A deployment must run the migration in a
   disposable database and add an integration rehearsal before switching the
   canonical store.

## What is not guaranteed yet

- There is no automatic migration runner; migrations are operator-led using
  the runbooks.
- The active CLI has no database transaction layer yet. Collection-page commit
  and job claim/heartbeat/finish have native methods; canonical event/evidence
  persistence, configuration, and `rh_cli ingest` wiring remain open.
  Filesystem fencing continues to govern the active runtime.
- No migration has been performed across a format change in this repository
  yet; the rules above are the contract, and the first real migration must
  add a rehearsal to `tests/`.
