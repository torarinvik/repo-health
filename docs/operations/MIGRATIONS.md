# Migrations and rollback

The reference implementation keeps its durable state in a filesystem store
(`src/rh_store.elisa`) rather than a database, so "migration" here means
changing on-disk formats, schema versions, and toolchain versions without
losing replayability or silently reinterpreting old data.

## Versioned things that can change

| Artifact | Version marker | Where |
|---|---|---|
| Public schemas | `rh-jsonschema/1` dialect, per-schema `name` | `schemas/*.schema.json` |
| Dependency graph | `rh-dep-graph/1` | `fixtures/packages/*.golden.json` |
| Canonical repo | `rh-canonical-repo/1` | `fixtures/connectors/*.canonical.json` |
| Evidence bundle | manifest schema versions | `bundle.manifest` |
| Metric definitions | `key` + `version` | `metrics/definitions/*.json` |
| Benchmark manifest | `rh-bench/1` | `build/bench-manifest.json` |
| Release packet | `rh-release-packet/1` | `build/release-packet.json` |
| Source register | `rh-source-review/1` | `ops/source-review-register.json` |

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

## What is not guaranteed yet

- There is no automatic migration runner; migrations are operator-led using
  the runbooks.
- There is no database transaction layer (`P11` remains a reference, not an
  implementation). Concurrency is handled by the fencing lease in the store.
- No migration has been performed across a format change in this repository
  yet; the rules above are the contract, and the first real migration must
  add a rehearsal to `tests/`.
