# Implementation status — honest baseline

**Rule:** an item is `implemented` only when contract + code on the real
execution path + positive/negative tests pass. Everything else states its
true stage. **226 of the 360 Architecture metric keys lack an implemented definition;
134 Architecture keys have at least one implemented definition. The runtime
catalog below contains 209 implemented definitions across 208 distinct keys.**

## Milestones

| Milestone | Stage | Evidence |
|---|---|---|
| M00 contracts/oracles | `implemented` | `src/rh_*.elisa`, `build/test_oracles` (`ORACLES OK`), `tests/test_m00.sh` |
| M01 safe Git scan | `implemented` | `build/rh_cli` (scan/replay/registry), `tests/test_m01.sh`; one tracked gap (see below) |
| M02 ingestion/hosts | `in_progress` | `RhJson`/`RhForge`/`RhForgeEvents`/`rh_store`/`rh_connector`/`rh_job`, `test_forge`/`test_store`/`test_job`, `tests/test_m02.sh`, `rh_cli store put|verify`, `rh_cli store lease` (`tests/test_lease_cli.sh`), `rh_cli ops backup|verify|restore` (`tests/test_store_cli.sh`), `rh_cli forge normalize` (`tests/test_forge_cli.sh`), bounded captured issues/proposals/reviews/releases through `rh_cli forge events` (`rh-forge-events-result/1`, `tests/test_forge_events_cli.sh`), `rh_cli connector check` (`tests/test_connector_cli.sh`, `rh-connector-instance/1`), `rh_cli job classify|run` (`tests/test_job_cli.sh`, `rh-job-next/1`+`rh-sched-result/1`) with a bounded scheduler (enqueue/claim/succeed/fail/cancel/reclaim), host quota and backoff; `rh_cli reconcile` (`tests/test_reconcile_cli.sh`, `rh-reconcile-result/1`) full-reconcile scheduling (due/horizon/debt/overlap), `rh_cli worker tick` (`tests/test_worker_cli.sh`, `rh-worker-plan/1`) one bounded deterministic scheduling pass, `tools/worker-daemon.sh` digest-gated process wrapper (`tests/test_worker_daemon.sh`), and `rh_cli ingest` (`tests/test_ingest_conformance_cli.sh`, `rh-ingest-result/1`) durable event-before-cursor replay with fencing and explicit empty/failure/partial states; the captured event boundary preserves provider identity for GitHub, GitLab, Gitea, Forgejo, and Bitbucket, replaces duplicate page observations by native identity, and retains validated opaque pagination state, while live auth and pagination advancement remain open |
| M03 packages/advisories | `in_progress` | `src/rh_package.elisa` (Cargo + npm + PyPI requirements/PEP 621 + Go modules + RubyGems + Composer + NuGet `packages.config` + Maven `pom.xml`) + `src/rh_inventory.elisa` + `src/rh_inventory_report.elisa` + `src/rh_registry_meta.elisa` + `src/rh_registry_pypi.elisa` + `src/rh_registry_npm.elisa` + `src/rh_registry_crates.elisa` + `src/rh_registry_rubygems.elisa` + `src/rh_registry_nuget.elisa` + `src/rh_registry_meta_report.elisa` + `src/rh_depsdev.elisa` + `src/rh_ecosystem_lookup.elisa` + `src/rh_resolution.elisa` + `src/rh_parser_diff.elisa` + `src/rh_adapter_manifest.elisa`, `test_package` (`PACKAGE OK`), `rh_cli deps` publishes `dependencies.unsupported_range_count`, `rh_cli inventory` publishes `rh-inventory/1`, `rh_cli registry-meta` publishes `rh-registry-meta-result/1` for canonical, PyPI, npm, crates.io, RubyGems, and bounded NuGet registration metadata, `rh_cli depsdev` publishes `rh-depsdev-enrichment/1`, `rh_cli ecosystem lookup` publishes `rh-ecosystem-lookup-result/1` from bounded captured ecosyste.ms package lookups with candidate mapping/provenance and rejection accounting, `rh_cli resolution` publishes `rh-resolution-instance/1`, `rh_cli parser-diff` publishes `rh-parser-diff/1`, and `rh_cli adapter-manifest` publishes `rh-adapter-manifest-result/1`; `tests/test_m03.sh`, `tests/test_deps_cli.sh`, `tests/test_inventory_cli.sh`, `tests/test_registry_meta_cli.sh`, `tests/test_depsdev_cli.sh`, `tests/test_ecosystem_lookup_cli.sh`, `tests/test_resolution_cli.sh`, `tests/test_parser_diff_cli.sh`, `tests/test_adapter_manifest_cli.sh`; live OSV, live ecosyste.ms transport and further provider adapters remain pending (see below) |
| M04 continuity/identity | `in_progress` | `src/rh_identity.elisa` + `src/rh_identity_report.elisa` + `src/rh_roles.elisa` + `src/rh_roles_report.elisa` + `src/rh_roles_provider.elisa` + `src/rh_continuity.elisa` + `src/rh_continuity_scan.elisa` + `src/rh_role_grain.elisa`, `test_continuity` (`CONTINUITY OK`)/`test_continuity_scan`, `rh_cli identity`/`roles`/`roles-import`/`continuity` publish `rh-identity-result/1`/`rh-roles-result/1`/`rh-provider-roles-input/1`/`persistence.retained_90d`+`concentration.change_*`, and `rh_cli role-grain` publishes `rh-role-grain-result/1` with one-event/one-role cardinality plus as-known/current-corrected replay; `tests/test_m04.sh`, `tests/test_continuity_cli.sh`, `tests/test_identity_cli.sh`, `tests/test_roles_cli.sh`, `tests/test_roles_provider_cli.sh`, `tests/test_role_grain_cli.sh`; bounded captured GitHub/GitLab permission imports are implemented with duplicate replacement and opaque pagination retention, while live authenticated collection and cursor advancement remain open; static and server-rendered continuity UI is covered by M06 tests |
| M05 temporal/downstream | `in_progress` | `src/rh_graph.elisa` + `src/rh_downstream.elisa` + `src/rh_downstream_report.elisa` + `src/rh_projection_store.elisa` + `src/rh_mapping.elisa` + `src/rh_coverage.elisa` + `src/rh_adoption.elisa` + `src/rh_population.elisa`, `test_m05` (`M05 OK`), `rh_cli downstream` publishes `rh-downstream/1` (mirror dedup R012 + per-metric intrinsic join R011) and optionally persists `rh-projection-snapshot/1` IDs; `rh_cli mapping` publishes `rh-mapping-result/1` and `--mapping` carries reviewed revision into the projection; `rh_cli population` publishes `rh-population-result/1` with bounded selected dependents, family deduplication, path witnesses, per-metric coverage/distributions, unresolved mappings, and policy unknowns; `tests/test_m05.sh`, `tests/test_downstream_cli.sh`, `tests/test_mapping_cli.sh`, `tests/test_coverage_cli.sh`, `tests/test_adoption_cli.sh`, `tests/test_population_cli.sh`; source-specific validity intervals now publish `rh-coverage-result/1` with explicit null endpoints and source capability states, while `rh-adoption-result/1` publishes staged introduction/removal evidence with right-censoring |
| M06 API/policy/corrections | `in_progress` | `src/rh_policy.elisa` + `src/rh_policy_parse.elisa` + `src/rh_correction.elisa` + `src/rh_correction_report.elisa` + `src/rh_notify.elisa` + `src/rh_notify_report.elisa` + `src/rh_query.elisa` + `src/rh_query_report.elisa` + `src/rh_render.elisa` + `src/rh_findings.elisa` + `src/rh_lineage.elisa` + `src/rh_drilldown.elisa`, `test_m06`/`test_m06b`, `rh_cli policy`/`correct`/`notify`/`query`/`render`/`findings`/`lineage`/`drilldown` publish `rh-policy-result/1`/`rh-policy-state/1`/`rh-corrections-result/1`/`rh-corrections-state/1`/`rh-notify-result/1`+`rh-notify-state/1`/`rh-query-result/1`/`repo-health-report-html/1`/`rh-findings-result/1`/`rh-lineage-result/1`/`rh-evidence-drilldown/1`, `rh_cli serve /_report.html` is server-rendered; `tests/test_m06.sh`, `tests/test_policy_cli.sh`, `tests/test_correction_cli.sh`, `tests/test_notify_cli.sh`, `tests/test_query_cli.sh`, `tests/test_render_cli.sh`, `tests/test_findings_cli.sh`, `tests/test_lineage_cli.sh`, `tests/test_drilldown_cli.sh`; dynamic UI tables, fixed report-backed API resource routes, capped upstream/downstream query traversal with truncation metadata, verified `/api/store/<16-hex-digest>` evidence lookup, structured findings, lineage-preserving evidence drill-down, and durable state-store wiring are implemented |
| M07 beta gate | `in_progress` | `src/rh_ops.elisa` + `src/rh_ops_report.elisa` (`rh_cli ops monitor|quota`) + `src/rh_privacy.elisa` + `src/rh_privacy_report.elisa` (`rh_cli privacy`) + `src/rh_sha256.elisa` (SHA-256/HMAC, M07-04 sign/verify) + transport guard (`src/rh_git.elisa`) + `ops/source-review-register.json`, `test_m07` (`M07 OK`), `test_m07_sha`, `tests/test_m07.sh`/`test_m07_sha.sh`/`test_ops_cli.sh`/`test_privacy_cli.sh`; independent review/pilot pending (see below) |
| M08 expanded coverage | `in_progress` | `src/rh_vcs_hg.elisa` (Mercurial) + `src/rh_vcs_svn.elisa` (Subversion) + `src/rh_vcs_fossil.elisa` (Fossil) + `src/rh_patch.elisa` (non-PR patch series) + `src/rh_release_feed.elisa`/`src/rh_release_feed_report.elisa` (release-only, `rh_cli release-feed`) + `src/rh_pep440.elisa`/`src/rh_pep440_report.elisa` (Python version semantics, `rh_cli pep440`) + `src/rh_gerrit.elisa` (Gerrit review-workflow, `rh_cli vcs --format gerrit`, folds N patch-sets into one change, R025) + `src/rh_spdx.elisa` (SPDX 2.3 inventory, exposed via `rh_cli inventory --format spdx`) + `src/rh_vcs_report.elisa` (`rh_cli vcs --format hg|svn|fossil|patch`, native `--repo` capture) + `src/rh_registry_pypi.elisa`/`src/rh_registry_npm.elisa`/`src/rh_registry_crates.elisa`/`src/rh_registry_rubygems.elisa` (bounded provider metadata normalization) + PyPI `requirements.txt`/PEP 621, NuGet `packages.config`, and Maven `pom.xml` parsing in `src/rh_package.elisa` (`rh_cli deps`) + bounded Debian `debian/control` distribution metadata (`src/rh_distribution.elisa`, `rh_cli distribution`, `rh-distribution-result/1`, `tests/test_distribution_cli.sh`) + bounded RPM spec preamble metadata (`src/rh_rpm.elisa`, `rh_cli rpm-spec`, `rh-rpm-spec-result/1`, `tests/test_rpm_spec_cli.sh`) + bounded archive metadata (`src/rh_archive.elisa`, `rh_cli archive`, `rh-archive-result/1`, `tests/test_archive_cli.sh`) + bounded Homebrew formula metadata (`src/rh_homebrew.elisa`, `rh_cli homebrew`, `rh-homebrew-result/1`, `tests/test_homebrew_cli.sh`) + bounded Arch `PKGBUILD` assignment metadata (`src/rh_arch.elisa`, `rh_cli arch-pkgbuild`, `rh-arch-pkgbuild-result/1`, `tests/test_arch_pkgbuild_cli.sh`), `connectors/manifests/{mercurial,subversion,fossil,release-feed}.json`, `fixtures/vcs/{svn-log.xml,fossil-timeline.txt}`, `test_m08` (`M08 OK`), `tests/test_m08.sh`, `tests/test_inventory_cli.sh`, `tests/test_vcs_cli.sh`, `tests/test_release_feed_cli.sh`, `tests/test_pep440_cli.sh`; Bitbucket Cloud forge connector (`rh_cli forge normalize --connector bitbucket`, `tests/test_forge_cli.sh`, guarded `--url` capture); more distribution ecosystems and other forge APIs remain (see below) |
| M09 catalog expansion | `in_progress` | admission lint (`tools/metric-lint.sh`) over 211 definitions (209 `implemented`, 2 `prototype`, 0 `planned`); experimental prototypes remain outside the runtime registry (see below) |
| M10 proven scaling | `in_progress` | `src/bench_runner.elisa` + `tools/bench.sh` + `tools/profile.sh` + `src/rh_columnar.elisa` + `src/rh_aggregates.elisa` + `src/rh_index.elisa` + `tests/test_bench.sh` + `tests/test_profile_bench.sh` + `tests/test_snapshot_cli.sh` + `tests/test_aggregate_cli.sh` + `tests/test_index_cli.sh` (deterministic datasets, stage profiles, machine-specific timings, perf manifests, rebuildable `rh-columnar-snapshot/1` exports, validated daily/weekly `rh-aggregate-result/1` projections with correction invalidation, and digest-bound incoming/outgoing `rh-index-manifest/1` CSR indexes) (see below) |
| M11 experimental/advanced | `in_progress` | `src/rh_experimental.elisa` + `src/rh_experimental_report.elisa` (`rh_cli experimental`) + `src/rh_proof.elisa` (`rh_cli proof`) + `src/rh_forecast.elisa` (`rh_cli forecast`) + `src/rh_intervention.elisa` (`rh_cli intervention`) + cadence adapter and definitions; `test_m11` (`M11 OK`), `tests/test_m11.sh`, `tests/test_experimental_cli.sh`, `tests/test_proof_cli.sh`, `tests/test_forecast_cli.sh`, `tests/test_intervention_cli.sh`; all currently scoped M11 adapters are opt-in and experimental |
| M12 stable 1.0 | `in_progress` | `ops/public-contracts.json` (76 public contracts, version tokens, compat rules) + `ops/research-conformance.json` (48-case RP-F01–F48 crosswalk) + `rh_cli pilot-review` (`rh-pilot-review-result/1`) + governance/migration/release docs + `test_contracts`/`test_research_conformance`/`test_pilot_review_cli` (`OK`); governance sign-off pending (see below) |

**M02 scope (in progress):** `db/migrations/001_initial.sql` target schema
contract (55 typed PostgreSQL tables, visibility/source-scoped constraints,
evidence and graph indexes, fenced lease/cursor SQL methods) with the static
`tests/test_migrations.sh` contract gate; capability manifests (5 connectors),
the opt-in `RH_PG_MIGRATION=1 tests/test_migrations_live.sh` rehearsal applies
the migration to PostgreSQL 16 and exercises stale fencing, terminal finish,
complete-only cursor advancement, and duplicate-page idempotence; capability
manifests (5 connectors),
bounded JSON parser, ISO8601, fetch guard + curl transport, GitHub/GitLab/Gitea/Forgejo
normalizers with goldens, per-capability status mapping, durable
filesystem store (content-addressed blobs with tamper-blocked publication,
JSONL events with id-based dedup, commit-after-verify cursors with
one-page overlap, coverage intervals), fencing job leases (monotonic
tokens, recorded-ttl expiry, stale-release refusal, terminal phases) —
all exercised by `test_store` selftest plus a real kill -9 crash-injection
sequence. The store now has a real CLI surface: `rh_cli store put --root
<dir> --file <path>` (idempotent for identical bytes, refuses to overwrite
a different blob under the same digest) and `rh_cli store verify --root
<dir> --name <hex>` (recomputes the digest; missing/corrupt evidence exits
5 and blocks publication). `rh_cli ops backup|verify|restore` wraps the
M07-10 drill: a canonical `rh-backup/1` manifest, a verify that counts
verified/missing/corrupt separately (missing was previously conflated with
corrupt — fixed), and a restore that copies only digest-verified objects.
`tests/test_store_cli.sh` covers all of it, including a corrupt object
being skipped by restore. Job leasing is a real path too: `rh_cli store
lease --root <dir> --job <name> --input <file> --out <file>` applies a
claim/heartbeat/release/status sequence to a real `<root>/leases/<job>.lease`
(+ attempt `.log`) and enforces fencing — a live lease is held, an expired
one is reclaimable with a new token, a terminal phase refuses further
claims, and a stale worker (wrong token) cannot heartbeat or release
(`tests/test_lease_cli.sh`). The forge normalizers are now a product path
too: `rh_cli forge normalize --connector github|gitlab|gitea|forgejo --input
<file> --out <file> [--fetched-at N]` reproduces the checked-in
`rh-canonical-repo/1` goldens byte-for-byte at a pinned time for four
forge payload shapes (GitHub repo JSON, GitLab project JSON, and the
Gitea/Forgejo repo JSON shape — Forgejo shares Gitea's field layout but
keeps its own connector id, fixture and validation); an unknown
connector with no normalizer (bitbucket/generic-git/mercurial)
is rejected (exit 3) rather than guessed, and a payload that does not
match the connector shape fails closed (exit 4). `tests/test_forge_cli.sh`
covers all four connections, determinism, connector-distinctness, the
default collection time, and the negatives. Connector *instances* are now a
product path as well (R006/R007): `rh_cli connector check --instance <file>
--out <file>` reads an `rh-connector-instance/1` document (connector id,
arbitrary base URL, approval flag, declared capabilities) and writes
`rh-connector-instance-result/1` with the connector's full capability table
(an unsupported capability is *stated*, never omitted), the declared
capabilities, and a usability verdict. Approval and transport are separate
gates: an arbitrary approved public self-hosted base URL is `usable` with no
code change, but a URL in loopback/private/link-local space, a non-https
scheme, a userinfo-smuggled URL, or a bare single-label host is
`transport-rejected` even when approved (`rh_fetch_guard` policy, S002) —
approval never overrides transport. An unapproved instance is `unapproved`.
Unknown connector ids, unknown capability keys, and capabilities the
connector does not declare (e.g. Gitea `traffic`, which has no traffic API)
fail closed (exit 4). `tests/test_connector_cli.sh` covers the controlled
self-hosted fixture, the transport gate across six hostile URLs, per-
connector capability tables (GitHub `traffic: windowed` vs Gitea
`traffic: unsupported`), determinism, and the negatives. The ingestion job
machine is a real path too (M02-03): `src/rh_job.elisa` classifies failures
into distinct kinds (transient, rate_limit, auth, unsupported, malformed,
budget, canceled — never collapsed to one "error"), routes them by
disposition (auth/unsupported terminal, malformed dead-letter,
transient/rate_limit/budget retry), applies integer exponential backoff
(larger base for rate-limit so a hammered host is respected), and
dead-letters an exhausted retry rather than turning it into success.
`rh_cli job classify --input <file> --out <file>` reads an `rh-job-event/1`
and writes `rh-job-next/1` with kind, disposition, next phase, wake time and
next attempt; an unknown kind or malformed event fails closed (exit 4).
`src/test_job.elisa` (`JOB OK`) plus `tests/test_job_cli.sh` cover the
classification, disposition, backoff monotonicity/caps, every transition,
and the negatives. Live GitHub fetch
verified opt-in. The digest-gated `tools/worker-daemon.sh` wrapper now runs
the bounded worker pass only when its input contract changes and supports a
finite pilot bound; webhook freshness stays out of the Elisa slice by
threat-model decision, and periodic full-reconcile automation remains a
producer-owned input refresh. No M02 work invents metrics: the catalog table
above is unchanged.

The bounded workflow-event adapter now accepts captured GitHub, GitLab,
Gitea, and Forgejo issues, proposals, reviews, and releases through
`rh-forge-events-input/1`. It preserves provider-native status strings and
IDs (`github:<id>`/`gitlab:<id>`), emits explicit `observed` or `unsupported`
capability states, reports malformed records per capability, and retains no
titles or bodies. It does not perform live authentication, pagination, or
role inference; those remain separate admission work.

**RP-03 ingestion conformance path:** `rh_cli ingest --root <dir> --input
<rh-ingest-input/1> --out <file>` pins `collection_start`, writes immutable
events before cursor advancement, reports updates arriving after the start
watermark and backdated observations requiring reconciliation, separates page
attempts from successful acquisition, and retains typed `rate_limit`,
`authorization`, `unsupported`, and `transient` failure counts. A stale
fencing token, malformed failure kind, failed page, or partial page cannot
publish a cursor. The path is exercised by
`tests/test_ingest_conformance_cli.sh` and contributes to the RP-F01–F09
crosswalk.

**M03 scope (in progress):** implemented — ecosystem-native semver
(strict, prerelease precedence, build ignored), Cargo name normalization
(case/dash-insensitive), lockfile-only resolution for Cargo (`[[package]]`
tables incl. source kind + checksum-as-digest, unknown keys counted) and
npm (`lockfileVersion` 2/3 `packages` with Node walk-up nested-version
preference, v1 legacy `requires` trees, dev/optional/peer scopes,
integrity digests), explicit unresolved reasons (`missing` / `ambiguous` /
`context` — a declared requirement never becomes an exact edge without
resolution evidence), bounded forward/reverse BFS with truncation flags,
bounded witness paths, offline OSV matching (id/alias merge counted,
withdrawn excluded from current matches, fixed-only ranges treated as
vulnerable-from-start per OSV semantics, unsupported ranges unknown),
canonical `rh-dep-graph/1` JSON with byte-checked goldens. The standalone
`rh_cli resolution --input <rh-dep-graph/1> --out <file>` adapter now emits
`rh-resolution-instance/1`, separating package identity from graph-local
provider node IDs and retaining the deterministic input digest. A third
ecosystem now has a real parser: Python `requirements.txt` (PEP 508
subset). Only an exact `==`/`===` pin with no extras, environment marker
or direct URL becomes a package node and a root edge; plain ranges become
`missing` unresolved entries, while extras (`pkg[extra]`), markers
(`pkg; python_version<...`), direct URLs (`git+https://...`) and pip
options (`-r`/`-e`) stay `context` unresolved with their original text
preserved — a declared requirement never becomes an exact edge (R009).
Names use PEP 503 normalization (case-insensitive, `-`/`_`/`.` equivalent).
A fourth ecosystem now has a real parser: Go modules (`go.mod`). Two further
M08 lanes now have real lockfile parsers: RubyGems (`Gemfile.lock`) and
Composer (`composer.lock`), preserving runtime/dev scopes and platform/context
requirements. Only a
`require <module/path> vX.Y.Z` directive with a plain release version
(`v` MAJOR.MINOR.PATCH) becomes a package node and a root edge;
pseudo-versions and `+incompatible` stay `missing` unresolved, while
`replace`/`exclude`/`retract` directives stay `context` unresolved (a
rewrite target is not a registry version). Single-line and parenthesized
`require` blocks are handled, `// indirect` is a comment, and the root
identity is the `module` path; names are byte-exact.
`rh_cli deps
--repo <dir> --out <dir> [--osv <file>]` is now the real execution path:
it reads a local project's `Cargo.lock`, `package.json` +
`package-lock.json`, `requirements.txt`, bounded PEP 621 `pyproject.toml`,
`go.mod`, `Gemfile.lock`, `composer.lock`, `packages.config`, and/or bounded
`pom.xml`, writes one
`rh-dep-graph/1` report per ecosystem, and
publishes `dependencies.unsupported_range_count` in `deps-metrics.json`
(`rh-deps-metrics/1`) with per-ecosystem components against a **declared**
supported syntax subset
(semver operators/identifiers only); protocol/alias/workspace/path forms
and dist-tags count as unsupported-by-declaration, explicitly distinct from
a missing dependency. A malformed lockfile/requirements/go.mod file fails closed
with no partial graph; advisories are only collected from a provided
offline OSV file or a guarded `--osv-url` capture,
never fabricated. `tests/test_deps_cli.sh` checks the supported Cargo, npm,
PyPI, Go, RubyGems, Composer, NuGet, and Maven lanes, the
exact unsupported count, an empty witness for an advisory not reachable
from the root (presence != reachability), the extras-not-resolved rule, and
the fail-closed branches. One inventory
interchange format is now pinned: `src/rh_inventory.elisa` parses
CycloneDX JSON with a **declared** supported spec set (1.4/1.5/1.6) —
an unrecognized version is reported `unsupported`, never guessed at;
component identity (type/name/version/purl) and SHA-256 artifact hashes
are extracted, a hash that is not 64 lowercase hex is not counted as a
known digest, and the module states that `valid != complete` (a valid
document proves it is well-formed, not that it lists every dependency).
That is now a real path: `rh_cli inventory --format cyclonedx|spdx (--input
<file> | --url <https-or-file-url>) --out <file>` emits `rh-inventory/1` with the declared spec version,
exact component/package counts, and per-component name/version/purl and
`digest_known` (only valid SHA-256 counts). A declared spec version outside
the supported set is reported `unsupported` with the reason and exits 3 —
never interpreted; a document of the wrong format fails closed (exit 4);
both formats report `unknown_top_keys` (top-level fields the parser does
not model are **counted**, not silently dropped). `tests/test_inventory_cli.sh` covers
both formats, determinism, the unsupported-version branch, and the
negatives.
Registry metadata is parsed by `src/rh_registry_meta.elisa`: version
labels, yanked flags, published times (epoch or raw string), declared
dependency counts, and a declared source link. Invariants held: a yanked
version is **retained**, not deleted; an absent yank field is unknown, not
false; a declared source link is an assertion, not identity (F023); and
declared dependencies are counts, not resolved edges. Registry enrichment
is a real path too: `src/rh_registry_meta_report.elisa` + `rh_cli
registry-meta --input <file> --out <file>` emit `rh-registry-meta-result/1`
with a yanked version retained (not deleted), an absent yank field as
`null` (unknown, never false), numeric and ISO published times preserved,
the declared repository link labelled an assertion, and exact
declared/optional/dev dependency counts; `tests/test_registry_meta_cli.sh`
covers canonical and PyPI project shapes plus the fail-closed negatives.
`go.sum` module checksums now attach exact `h1:` artifact evidence to matching
Go nodes while `/go.mod` metadata checksums stay separate; malformed checksum
records fail closed. Registry metadata now also has a bounded `https`/`file`
capture path with retained body/status/error evidence, and the optional
deps.dev adapter emits a separate origin/coverage record without changing the
local graph. PyPI project JSON now has a provider-shaped adapter at the
registry boundary; npm project metadata, crates.io's `crate` envelope, and
RubyGems versions endpoint/wrapper now have the same bounded provider adapters
and canonical normalization path. Bounded NuGet registration pages now use
`src/rh_registry_nuget.elisa`: `items`/`catalogEntry` entries retain
listed/yanked state, publication time, project URL assertions, and declared
dependency counts without package resolution;
further provider-specific query
adapters remain pending beyond these adapters and the generic bounded URL capture,
git/path dependency resolution (recorded as context-unresolved), and
non-requirements PyPI source metadata (`setup.py` is not parsed). The bounded
PEP 621 `project.dependencies` / `project.optional-dependencies` subset now
preserves exact and optional declared requirements. The bounded NuGet
`packages.config` parser preserves exact package IDs and versions,
development dependency scope, and explicit unresolved version ranges;
malformed package entries fail closed without a partial graph. The bounded
Maven POM parser preserves `groupId:artifactId` coordinates, exact literal
versions, test/optional scopes, and excludes dependency-management entries;
property and range versions remain explicit unresolved requirements.
The
catalog table above is unchanged:
these are graph/advisory observations, not new published metric keys.

**M04 role declarations (R013):** `src/rh_roles.elisa` parses declared
forge/project roles (owner/maintainer/triager/member) and permission bits
into time-scoped declarations with a source stratum (provider document /
project file / operator). Declarations are **kept strictly separate from
observed actions** — they never become observed facts, an unknown role
string is never guessed into maintainer, and revocation/effective-time are
honored. Live permission-inventory import still needs owner authorization
the M02 slice lacks, so this operates on captured documents.

**M04 scope (in progress):** implemented — persistence cohorts over an
actor-by-complete-month presence matrix (one active day is one month;
component measures returned alongside membership), a coverage basis
(`rh_coverage_basis`: full/windowed/shallow; shallow wins) published with
the continuity report so a coverage-limited scan declares
`activity_change_claims_supported:false` and never presents a coverage
gap as an activity change (R029), continuity concern
defined on the persistence core only (fixture A: 200 one-off actors plus
a 6-actor core → no concern; fixture B: one release actor among three →
concern), retention with right-censoring taking precedence over
unobservability (`retained`/`not_retained`/`censored`/`unobservable`,
fixtures E/F), exact concentration via the shared rational core
(oracles: `[9,3]` → HHI 5/8, effective 8/5, 50% 1, 80% 2; `[25×4]` →
HHI 1/4, effective 4, 50% 2, 80% 4; fixture A → 50% 70, 80% 152),
handover overlap and primary-actor transition measurement without motive
attribution (fixture C), role visibility for a review-only maintainer
(fixture D), reversible identity links with revisioned clusters
(accept/chain/reject/revoke/recompute: revisions 0→1→2→1→0 and cluster
counts 4→3→2→3→4), automation stratification with `unresolved` never
forced human, and an `rh-continuity/1` report carrying cohort rule,
coverage, identity revision, concentration components, retention tallies
and event-type totals (empty populations serialize as `null`, never 0).
The identity module takes no event ledger at all, so revocation is
structurally unable to alter raw evidence (asserted in the harness).
Product integration now exists: `rh_cli continuity --bundle <manifest>
--out <dir>` parses the pinned `evidence/git-log.bin` into raw
project-local author-identity events (`src/rh_continuity_scan.elisa`),
writes `continuity.json` (`rh-continuity/1`) and publishes
`persistence.retained_90d` in `continuity-metrics.json`
(`rh-continuity-metrics/1`). A windowed or shallow scan cannot establish
an actor's first observation, so retention is reported `unsupported`
there, never as a misleading rate; `tests/test_continuity_cli.sh` proves
the exact 1/3 retained ratio for full history, the `unsupported` branch
for a windowed scan, and that no raw email leaks into published output.
Raw actor ids are assigned by first appearance; no cross-source or
name/domain merge is performed. Reversible identity links are a real path
too: `src/rh_identity_report.elisa` + `rh_cli identity --input <file> --out
<file>` process an `rh-identity-input/1` ledger into `rh-identity-result/1`
with the identity revision, clusters over ACCEPTED links only, a per-actor
cluster map, and actor-kind stratification; rejecting/proposing changes
nothing and revoking recomputes clusters and changes the revision with no
raw record rewritten (`tests/test_identity_cli.sh`). Declared roles are a
real path too: `src/rh_roles_report.elisa` + `rh_cli roles --input <file>
--out <file>` emit `rh-roles-result/1` with time-scoped role/permission
queries (a revoked or not-yet-effective declaration is inactive, an
unrecognized role string stays `unknown`), an exact permission check, and a
declaration-source tally (provider/file/operator), and an explicit
authorization state (authorized/unauthorized/not_requested/unknown).
`--url` additionally
captures a bounded file/HTTPS permission document with retained body/status/
error evidence (`rh-roles-fetch/1`) before parsing; no credentials are sent.
Declared roles remain separate from observed actions (`tests/test_roles_cli.sh`).
The bounded `rh_cli roles-import` path and `src/rh_roles_provider.elisa`
normalize captured GitHub collaborator and GitLab project-member documents
into `rh-roles-input/1`; documented permission levels map to known roles,
unknown provider roles remain `unknown`, and non-authorized captures emit no
declarations (`tests/test_roles_provider_cli.sh`).
Project-focused restricted identity publication is now a real path:
`src/rh_identity_publication.elisa` + `rh_cli identity-publish` emit
`rh-identity-publication-result/1` with actor-kind/cluster-size/correction
aggregates only; source-native IDs, aliases, display names, and cluster
membership are omitted, raw identity is labelled restricted, and the output
cannot become a personal leaderboard. `tests/test_identity_publication_cli.sh`
covers the public scope, unknown-kind, duplicate-correction, secret-absence,
and malformed-input gates. Restricted role publication is also a real path:
`src/rh_role_publication.elisa` + `rh_cli roles-publish` emit
`rh-role-publication-result/1` with authorization, role/source, and query
coverage aggregates only; actor IDs, permission documents, and personal
rankings are omitted (`tests/test_role_publication_cli.sh`). The static and
server-rendered M06 paths now expose continuity reports as accessible tables.
NOT yet:
live authenticated M04 role *declaration* collection from forge permissions
(needs M02 auth flows), succession overlap published as a metric only with
explicit handover evidence (currently `not_applicable` without it), and an
additional human governance review of the contributor-protection policy.

**M05 scope (in progress):** implemented — labeled projections
(`rh_projection_make`: edge scope, platform, valid/known time cutoffs,
identity/mapping revisions, public-only visibility, node/depth budgets;
every traversal returns under that label and sets a truncation flag
instead of inventing a total), bitemporal edge visibility where a
2024-introduced dependency first collected in 2026 is invisible to a
2025 known-time query and visible retrospectively (S009), unique
direct/transitive reverse enumeration with structural root exclusion and
dedup, iterative (non-recursive) Kosaraju SCC over the filtered
projection with bounds guards, mirror/family dedup that groups only on
ACCEPTED assertions (proposed/rejected/revoked never group), scenario
queries for simulated unavailability, per-metric downstream covered
denominators (a dependent may have history coverage without review
coverage — coverage is never collapsed to one number), histograms,
adoption staged as first-seen vs confirmed-introduction/removal with
right-censored durations and observed-upgrade (not migration) semantics,
and observed actor-overlap for shared-maintenance exposure. The
anti-circularity test adds 500 dependents and asserts intrinsics do not
change. Persisted projection snapshots now use the M02 immutable blob store:
`rh_cli downstream --snapshot-root <dir>` records the graph and complete
projection manifest under a deterministic `rh-projection-snapshot/1` ID, and
the report carries that ID for replay/verification. Reviewed mapping imports
now have a real path: `rh_cli mapping --input <file> --out <file>` emits
`rh-mapping-result/1`, and `rh_cli downstream --mapping <file>` carries the
mapping revision into the projection while only accepted mirror/migration
relations group nodes; component and release-line assertions remain evidence
(`tests/test_mapping_cli.sh`). Source-specific coverage-gap intervals now have a bounded execution path: `rh_cli coverage --input <file> --out <file>` emits `rh-coverage-result/1` with per-capability state, known-as-of time, and nullable validity endpoints; unknown endpoints stay unknown and are never epoch sentinels. A real execution path now exists:
`rh_cli downstream --graph <dep-graph.json> --subject <id> --out <dir>`
reads an `rh-dep-graph/1` document, applies a labeled public projection,
and writes an `rh-downstream/1` report with direct/transitive dependents,
SCC count, an optional simulated-unavailability scenario, an explicit
`truncated` flag (a truncated result is never a total), private-node
exclusion (`--private`), accepted mirror/family grouping
(`--mirror a:b`) that collapses only ACCEPTED assertions while forks stay
distinct, and an optional per-metric intrinsic join (`--intrinsics
<file>`) where the caller supplies independently computed measurements and
the report emits a covered denominator per metric (never one collapsed
number; anti-circularity). `tests/test_downstream_cli.sh` proves diamond
direct=2/transitive=3, cycle termination with body exclusion, truncation,
private exclusion, scenario, mirror dedup (2/3 → one family) plus fork
distinctness, per-metric intrinsic coverage, an end-to-end `deps` graph,
and fail-closed negatives. The default downstream report remains
`rh-downstream/1`; explicit scope, platform, valid-as-of, and known-as-of
filters select `rh-downstream/2`. Its input edges preserve optional platform,
introduction, removal, and first-seen times, and the output labels all four
projection filters plus visible edge count. Temporal snapshot IDs are stable
on replay and change when valid-time projection changes. R011/R012 are now
implemented on the product path. No new metric keys are published.

**M06 scope (in progress):** implemented — four-valued policy evaluator
with an explicit lattice (deny > unknown > warn > allow) so unknown can
never be spent as permission and warn never overrides deny; exact rational
comparisons for every operator with overflow -> unknown (never a guessed
answer); freshness and minimum-sample gates, and a required-completeness
gate that returns unknown for an incomplete inventory; policy exceptions
that suppress a rule only when approved, unexpired, and digest-matched
(expired exceptions authorize nothing); binding digests over subject,
context, artifact digest, rule thresholds, and time (TOCTOU: a decision
cached under one version/digest/scope is not reusable for another); a
structured explanation built only from typed fields, and an agent contract
test proving repository prose cannot change a decision; and a correction
core where accepting a correction advances the revision, supersedes only
that subject's derived results (raw ledger untouched), and replay from the
same ledger produces the corrected value. Also implemented: the query
contract (`src/rh_query.elisa`: request kinds, stable cursor pagination
with a page cap, per-capability scan-status breakdown that localizes a
failed fetch to its capability rather than the project, and bounded graph
jobs with a fenced in-memory lease) and notification policy
(`src/rh_notify.elisa`: upstream maintainers are refused unless explicitly
subscribed, suppressed decisions record nothing so a cooldown cannot
silence a first real alert, digest change is a new key, acknowledged and
resolved findings stay quiet, and source outages suppress
coverage-derived alerts). The query contract is a real surface too:
`src/rh_query_report.elisa` + `rh_cli query --input <file> --out <file>`
process an `rh-query-input/1` request into `rh-query-result/1` with cursor
pagination (a replayed cursor is idempotent), a per-capability scan-status
breakdown, and a bounded-job lease sequence (claim/renew/finish/budget with
fencing tokens); `tests/test_query_cli.sh` covers pages/cursors,
scan-status, the lease state machine, and fail-closed negatives. The notification policy is now a real surface
too: `src/rh_notify_report.elisa` + `rh_cli notify --input <file> --out
<file>` process an `rh-notify-input/1` event stream (notify/ack/resolve)
into `rh-notify-result/1`, where an upstream maintainer is refused unless
explicitly subscribed, a refusal records nothing (no phantom cooldown),
a changed artifact digest is a new key, and ack/resolve silence a key;
`tests/test_notify_cli.sh` proves all of it plus the fail-closed negatives.
The policy engine now has a real surface:
`src/rh_policy_parse.elisa` parses a versioned `rh-policy/1` rule set and
an `rh-policy-input/1` observation file, aligns inputs to rules by id
(missing input -> `unavailable` -> UNKNOWN), and `rh_cli policy
--policy <file> --input <file> --out <dir>` writes `rh-policy-result/1`
with the four-valued decision, fired/excepted/missing rule ids, a
structured explanation, and the subject/context/artifact/time binding
digests. Unknown schema/op/status or a non-positive threshold denominator
fails closed (exit 4). `tests/test_policy_cli.sh` proves observed
violation -> deny, partial -> unknown, missing-input -> unknown, deny
beats unknown, digest-bound exceptions only when approved+unexpired
(expired or artifact-digest change -> deny, TOCTOU), prose in the input
cannot flip a decision, and malformed inputs fail closed. The correction
workflow also has a real surface: `src/rh_correction_report.elisa` parses
a versioned `rh-corrections/1` document and `rh_cli correct
--corrections <file> --out <dir>` writes `rh-corrections-result/1` where
accepted corrections advance the revision and supersede only the target's
older derived results (counted once, never re-counted), rejected/open
corrections change nothing, replay recomputes from unchanged raw inputs,
and unknown kind/state/combine fails closed. `tests/test_correction_cli.sh`
covers all of these. The server-rendered UI is now real:
`src/rh_render.elisa` renders a `report.json` into a self-contained
accessible HTML page (scoped metric/capabilities tables — the text
alternative — plus the mandatory caveats), `rh_cli render --report
<report.json> --out <file.html>` exposes it offline, and `rh_cli serve`
answers `/_report.html` by rendering the report at request time (no static
fixture). Every dynamic string is HTML-escaped, and the page adds no
verdict; `tests/test_render_cli.sh` covers structure, escaping of a hostile
source name, determinism, and negatives. Notification state is now durable:
`rh_cli notify --state <file>` loads a prior `rh-notify-state/1` and writes
the updated rows back (a missing file is a fresh state), so cooldowns,
acknowledgements and resolutions survive across runs; a corrupt state file
fails closed (exit 4). `tests/test_notify_cli.sh` proves the cross-run
cooldown/ack/resolve sequence. All three state surfaces also accept an
opt-in `--state-store <dir>` backed by `src/rh_state_store.elisa`: immutable
state blobs are verified through the M02 store and a digest-checked `current`
pointer advances only after publication; malformed pointers or blobs fail
closed. The notify, policy, and correction CLI harnesses cover replay from
that store. Policy exceptions are now durable too:
`rh_cli policy --policy <file> --input <file> --out <dir> [--state
<file>]` loads an `rh-policy-state/1` document of
`rule_id`/`subject_id`/`digest`/`expires_at`/`state` rows and writes the
merged set back, so an approved waiver survives process restarts and an
*expired* waiver is re-evaluated rather than silently renewed (the emitters
round-trip byte-stably). A persisted row is dropped when the same
`(rule_id, subject_id, digest)` is declared inline in the current policy
document, so current intent wins over stale state; a corrupt or
wrong-schema state file fails closed (exit 4), never default-allow.
`tests/test_policy_cli.sh` proves cross-run persistence, deterministic
write-back, expiry -> deny, revoked -> deny, inline-over-state precedence,
and malformed-state exit 4. Public contract `policy-state` added
(`rh-policy-state/1`, additive; 32 contracts total). Corrections are durable
as well: `rh_cli correct --corrections <file> --out <dir> [--state <file>]`
loads an `rh-corrections-state/1` document carrying the revision floor, the
last-correction ordinal already folded in (watermark), and the subjects
superseded so far, and rewrites it after the run; replaying the same
corrections file is therefore idempotent (no second revision advance, no
re-supersede), a persisted revision floor is honoured even with no new
corrections, and a corrupt/wrong-schema state file fails closed (exit 4).
`tests/test_correction_cli.sh` proves idempotent replay across runs,
deterministic write-back, the revision floor, and malformed-state exit 4.
Public contract `corrections-state` added (`rh-corrections-state/1`,
additive; 33 contracts total). The report page now also renders optional
escaped timeline and bounded neighborhood tables, and `rh_cli findings`
emits typed external assessments with assessment time and delivery-path
provenance. No new metric keys are published.

**M07 scope (in progress):** implemented in this slice — a source-review
register (`ops/source-review-register.json`, schema-validated in
`tests/test_m07.sh`, with GitHub traffic explicitly unauthorized per
[P01] and no credential fields), a publication suppression gate
(`src/rh_privacy.elisa`: unknown-visibility withholds before private
withholds before the small-cell threshold; suppression is explicitly *not*
anonymization). The gate is a real path too: `src/rh_privacy_report.elisa` +
`rh_cli privacy --input <file> --out <file>` emit `rh-privacy-result/1`
where a cell publishes only when every contributing subject is public and
the threshold is met, unknown-visibility withholds before private, a small
public cell suppresses, and each decision carries the "suppression is not
anonymization" explanation (`tests/test_privacy_cli.sh`). operational
runbooks (`docs/operations/runbooks.md`,
M07-13), and a deterministic release evidence packet generator
(`tools/release-packet.sh` + `tests/test_release_packet.sh`). A deletion
drill exists (`rh_store_delete_blob` + `rh_replay_label`): removing a raw
payload is idempotent, and a report whose referenced inputs are gone is
labelled **not replayable** rather than silently recomputed (M07-08).
Adversarial
transport policy hardened (`src/rh_git.elisa`: loopback/private/link-local/
CGNAT/benchmark/multicast/unspecified v4, IPv6 brackets/ULA/link-local,
userinfo/credentials, percent-encoding, non-standard ports, decimal/hex/
octal-obfuscated hosts, and a post-DNS `rh_addr_guard` for rebinding),
parser hardening tests (bounded JSON depth, malformed JSON/semver/lockfile
fail structured, no trap), monitoring with **separate service and project
series** and an unknown-rate that reports -1 rather than 0 when there is no
denominator, per-host token-bucket quota with exponential capped backoff,
operator stop, and cancel refund (`src/rh_ops.elisa`), and a backup/
restore drill where corruption is detected and corrupt objects are
**refused at restore** (`test_m07`, `tests/test_m07.sh`); the same drill is
now a product path (`rh_cli ops backup|verify|restore`, `tests/test_store_cli.sh`,
with missing and corrupt counted separately). Monitoring and source-respect
are also product paths: `rh_cli ops monitor --input <file> --out <file>`
emits `rh-monitor-result/1` with service and project series **separate** and
a rate with no denominator as `null` (unknown, not 0); `rh_cli ops quota
--input <file> --out <file>` emits `rh-quota-result/1` running a per-host
token bucket with exponential capped backoff, operator stop, and cancel
refund (`tests/test_ops_cli.sh`). M07-04 release
signing is now implemented: `src/rh_sha256.elisa` provides SHA-256
(FIPS 180-4) and HMAC-SHA256 (RFC 2104), pinned to published vectors in
`test_m07_sha` / `tests/test_m07_sha.sh`, and `rh_cli sign|verify` emits and
checks a signature object over the release packet with a raw key held
separately from workers (`tools/release-packet.sh` signs only when
`RH_SIGNING_KEY_FILE` names a key; keys are gitignored). Verification
establishes subject integrity and possession of the shared key — it is
symmetric, not a public-key signature, and is never presented as code
safety (S011). NOT yet: M07-01 independent threat-model review (an internal
`ops/threat-model-review.json` exists; independence is a human attestation)
and the opt-in pilot. The beta gate is **not** passed; `M07` stays
`in_progress`.

**M08 scope (in progress):** bounded native non-Git adapters. `src/rh_vcs_report.elisa`
parses the documented machine formats of `hg log -Tjson`, `svn log --xml -v`,
and `fossil timeline -F` into normalized changes: the Mercurial `node` is
preserved verbatim (40-hex, and a 64-hex SHA-256 shape is rejected), the
integer `rev` is kept as repository-local and explicitly not identity, the
author string stays raw evidence rather than an account or a person, the
date is kept as UTC plus the recorded offset, tags are counted but never
called releases, and `public`/`draft`/`secret` phases are preserved.
Malformed JSON and a non-array payload fail closed; entries with a missing
or malformed node are counted as rejects, never guessed; a change cap
`connectors/manifests/{mercurial,subversion,fossil}.json` record the
capability shapes (history only; issues/reviews/releases/permissions/traffic
`unsupported`) and `ops/source-review-register.json` records their rights.
All three native lanes are now product paths: `rh_cli vcs --format hg|svn|fossil
--repo <path> --out <file>` invokes a bounded local native command, retains
source and stderr evidence beside the report, and parses it through the same
fail-closed path as `--input`. The deterministic gate uses controlled command
shims because those tools are not installed in the local environment. The
fixture form remains available. The non-PR lane is also a product path:
`rh_cli vcs --format hg|patch
--input <file> --out <file>` emits `rh-vcs/1` (Mercurial changes) and
`rh-patch/1` (mbox series), so R025's native non-Git history and non-PR
workflow are both exercised off the test binary (`tests/test_vcs_cli.sh`;
wrong shape/format fails closed, rejected entries are never guessed).
The non-PR workflow lane exists as `src/rh_patch.elisa`: a logical change
is keyed by (base subject, patch index), so three revisions (v1/v2/v3) of
one patch collapse to **one** change with `max_version` 3, while a
1/2+2/2 series is **two** changes; non-patch messages are each their own
change and are never forced into a series. An earlier revision left trailers out of scope; they are now parsed
(`rh_trailer_parse_line`/`rh_trailers_scan`): Reviewed-by/Acked-by/Tested-by
/`Fixes:`/`Link:` become declared role/provenance evidence, distinct
approvers are deduped, `Fixes:` is labelled a claim not confirmed
reachability (R019), and the body is never executed or interpolated.
A Gerrit review-workflow lane, `src/rh_gerrit.elisa` + `rh_cli vcs --format
gerrit`, folds N re-pushed patch-sets into **one** logical change keyed by
the stable Gerrit `_number` (so a 3x-revised series is one change with
`revision_count` 3, never three changes), keeps created/updated times from
the RFC-style Gerrit timestamp (fractional seconds dropped, unparseable
time fails closed), and preserves non-PR semantics without demanding a
GitHub merge request (R025). The count only walks value nodes in the
object so key text is never mistaken for an entry. `fixtures/vcs/
gerrit-changes.json` is the golden fixture and `tests/test_vcs_cli.sh`
covers the fold, determinism, and the fail-closed timestamp.
A third lane, release-only sources, is `src/rh_release_feed.elisa`: it
parses a release feed into releases with their published time (valid time)
and the collector's first-seen time (known time, both retained), counts
artifacts and how many carry a digest, and derives **no** history or author
identity — its manifest marks history/identity `unsupported` and a missing
published time stays unknown rather than being replaced by first-seen; a
tag is a label, so the record is keyed by (tag, first-seen) and a
re-published tag is a new observation. The release-only lane is now a real
path: `src/rh_release_feed_report.elisa` + `rh_cli release-feed --input
<file> --out <file>` emit `rh-release-feed-result/1` with published (valid)
and first-seen (known) time kept separate, a missing published time staying
`null`, exact asset/digest counts, and `history_supported`/`identity_supported`
both false (`tests/test_release_feed_cli.sh`).
An ecosystems lane begins with `src/rh_pep440.elisa`: Python/PEP 440
version parsing and ordering, deliberately not SemVer — epoch, arbitrary
release segments, a/b/rc pre-releases (with alpha/beta/c/pre aliases),
post, dev and local are ordered per PEP 440 (e.g. `1.0.dev1 < 1.0a1 < 1.0
< 1.0.post1 < 1.0.1`, and an epoch dominates). Declared subset: local
versions are compared by presence only; invalid versions have `ok=0` and
must not be compared. This is version semantics only — no PyPI manifest or
requirements parser yet. It is now a real path: `src/rh_pep440_report.elisa`
+ `rh_cli pep440 --input <file> --out <file>` emit `rh-pep440-result/1` with
per-version details (epoch, release, a/b/rc/dev/post, local presence) and
an ascending order over VALID versions only — invalid versions are reported
`valid:false` and never compared or sorted (`tests/test_pep440_cli.sh`).
A second inventory format is pinned: `src/rh_spdx.elisa` parses SPDX 2.3
JSON (declared supported version; anything else is `unsupported`), extracts
package identity and SHA-256 checksums, and **counts top-level keys it does
not model** (`unknown_top_keys`) instead of pretending it understood them.
NOT yet: provider-hosted collection and live authenticated forge permissions,
more distribution ecosystems and other forge APIs. Debian, RPM spec, and
Homebrew metadata are supported as bounded declaration paths; archive metadata
is supported without archive expansion or extraction. The M07 public-beta gate is not
passed. (The PyPI dependency lane landed in M03: `requirements.txt` and the
bounded PEP 621 `pyproject.toml` declared-requirement parsers, see above.)

**M09 scope (in progress):** the metric catalog backlog is now governed
mechanically. `tools/metric-lint.sh` requires every definition to carry the
base contract fields and, for anything not yet `implemented`, the full
admission template (`inputs`, ratio `numerator`/`denominator` where
applicable, `params`, `missing_behavior`, `confounders`) so a planned
metric cannot be a bare name. The last `planned` definition,
`succession.handover_overlap_months`, is now `implemented` on a real path:
`rh_cli succession --input <file> --out <file>` publishes the count of
complete months in which a **declared** predecessor/successor pair are both
active, and an absent pair is `not_applicable` (never zero overlap) so an
activity-derived primary change is never passed off as a declared handover.
`persistence.retained_90d` and `dependencies.unsupported_range_count` are
`implemented` on the real `rh_cli continuity` and `rh_cli deps` paths.
`tests/test_m00.sh` proves that an unpublished (`planned`/experimental)
metric is **absent** from the runtime registry (never advertised as
available) while published definitions are present. Catalog state: 211
definitions = 209 `implemented`, 2 `prototype`, 0 `planned`; the 360 target
is unchanged and nothing unpublished is computed or published.

**Fixture coverage (F001–F040):** `fixtures/fixture-catalog.json` lists all
forty plan fixtures with an honest status and a pointer to the test that
proves it. `tools/fixture-lint.sh` (run by `tests/test_fixtures.sh`) fails
if a `covered`/`partial` entry names a file/token that does not exist, so a
green suite cannot imply coverage that is absent. All **40 fixtures are
now `covered`**: the last one, F004, became testable once the scanner
detected partial clones (`extensions.partialClone`) and labelled
blob-derived metrics **partial** while history stays observed. The M04 fixtures A–E are mapped explicitly (F012,
F013, F014, F015, F017), along with F021 optional-context exclusion, F006
distinct cherry-pick-like revisions, F007 force-push retention, F023
repository claims staying unverified or conflicted, F024 same-label bytes
changing to a new artifact, and F033 orphan GC (`rh_store_gc`).

**M06-01 HTTP wire protocol:** `src/rh_http.elisa` adds a minimal,
single-threaded, **loopback-only** listener. It binds 127.0.0.1 (never a
wildcard interface), caps request size and body size, allows GET/HEAD report
files and fixed JSON API resources plus bounded POST `/api/query` requests, rejects `..`/NUL/control/
absolute paths, serves only an allowlisted set of report files or the query
resources (never a directory listing), reads split requests through a bounded
header/body framing step, validates methods before paths, and never echoes
request bytes into a response. `rh_http_route` is
testable without a socket; a separate run served a real `report.json`
(200, `application/json`). The CLI exposes `rh_cli serve --root <dir>
[--port N] [--max N]`; a live end-to-end run answered `/health` 200,
`/report.json` 200 `application/json`, `/` 200 `text/html`, an unknown path
404, and a traversal path 400. The live test is opt-in (RH_LIVE_TESTS=1) so
the default gate stays offline. `src/test_http.elisa` covers the
parse/route/status matrix including traversal, unknown paths, wrong methods,
query JSON success/failure, NUL, and CRLF response heads.

**M06-03 accessible renderer:** `tools/render-project.sh` turns a produced
report directory into a single static HTML page whose every value is a
semantic table row — no chart, no color-only encoding, no image — so the
text/table is the primary, keyboard- and screen-reader-navigable
representation. Tables carry `<caption>` and `scope` header cells, the
document declares its language, unknown metrics render their status/reason
never `0`, and the page states it is a render of a pinned report with no
health or trust judgement. `tests/test_m06_ui.sh` renders a real report and
an empty repo (to force a genuinely unknown metric), asserts valid HTML
parse, semantic structure, unknown-not-zero, and absence of verdict
language. When present, `continuity.json` and `continuity-metrics.json` are
rendered as separate accessible continuity tables with coverage and identity
context; absent artifacts remain absent. `tests/test_render_cli.sh` covers
that path. The loopback-only HTTP listener serves this page and pinned report
artifacts through the same allowlisted route; its live socket check is opt-in.

**M06 report explanation:** `rh_cli explain --input <report.json> --out
<file.md>` emits `repo-health-explain/1`, a deterministic Markdown projection
of the pinned M01 report. It repeats source/cutoff/digest metadata, every
metric's typed status/reason/value/evidence fields, and capability states;
unknown and unavailable remain explicit and no verdict is added
(`tests/test_explain_cli.sh`).

**Resource-limit termination (S012):** `tests/test_m07_resource_limits.sh`
exercises the history bound with a small fixture via the documented
`RH_SCAN_MAX_COMMITS` hook (it can only *lower* the real 20000 bound,
never remove it), asserting the scan terminates promptly and reports
`history.coverage_state = truncated` with window completeness `partial`
rather than an unbounded total; verifies the oversized-evidence read cap
(`RH_MAX_READ`) is enforced on the real read path and the CLI fails closed
with exit 4; and checks the fetch byte/time/redirect caps.

**Publication review (S010/R030):** `tools/publication-review.sh` scans the
**actual generated report directory** for prohibited language — universal
health/trust score, trustworthiness, safety/certification verdicts, medical
or moral inference, maintainer-worth verdicts, letter grades/ratings, and
an unsupported "all metrics available" claim. It allows caveat lines that
merely name and deny the forbidden thing. `tests/test_m07_publication.sh`
scans a real repo, asserts the output is clean, and injects verdict
language into a copy to prove the reviewer rejects it (negative control).

**M12 public-contract stability:** `ops/public-contracts.json` registers
64 public machine-readable contracts, including the research lineage,
population, ingestion, drill-down, role-grain, adapter-manifest, and
conformance-ledger contracts, each with its version token, a stability class
(frozen/additive), and a compatibility rule; the version token must literally
appear in the artifact and each contract cites a test token that must exist.
`rh_cli pilot-review` records mapping-review, correction-turnaround,
decision-usefulness, provider-outage, and measured-cost inputs as
`rh-pilot-review-result/1`; it does not turn supplied observations into an
independent audit or release verdict. `tests/test_contracts.sh` enforces this,
checks that an unknown registry
version has no fallback, and that schema tests are independent of generated
code. This is the machine-checkable half of the release packet's stability
guarantee.

**Threat-model & dependency review (M07-01/M07-05):**
`ops/threat-model-review.json` records seven boundaries (url-argument,
subprocess, transport, archive-parser, publication, http-listener,
public-private) each with assets, attack, tested control, and residual risk,
plus explicit not-covered areas and the statement that it is not an
independent audit. `ops/dependency-review.json` names every external surface
(Elisa stage1, libc, git, curl, python3) with pinning, isolation, and update
procedure, and calls out the libc native surface. `tests/test_m07_reviews.sh`
requires each boundary's cited test token to exist, the native surface to be
named, the uncovered areas to be stated, and no safety verdict in the claim
fields.

**Provider-dependency review (M07-09):**
`ops/provider-dependency-review.json` records every external feed/tool the
implementation depends on (`git-cli`, `osv-data`, `deps-dev`,
`criticality-score`, `ecosyste-ms`, `reproducible-builds`) with lifecycle
(`active`/`not_enabled`/`retired`), failure mode, assumption, and rights.
`tests/test_providers.sh` enforces it: the retired Criticality Score and
the not-enabled deps.dev and live ecosyste.ms transport are explicitly **not**
claimed in use; the captured ecosyste.ms adapter is limited to reviewed
fixtures, and every failure mode states unknown/stale/fail-closed rather than
silent success.

**Requirements/safety index:** `ops/requirements-index.json` maps every
R001-R030 requirement and S001-S012 safety rule to concrete evidence (a
file plus a token that must be present), with an honest status and an
explicit `gap` for anything not fully implemented. `tools/requirements-audit.sh`
fails if an evidence file or token is missing; `tests/test_requirements.sh`
includes a negative control proving a bogus token fails. Current state:
**30 implemented, 0 partial** — R011 is implemented because
`rh_cli downstream --intrinsics <file>` joins caller-supplied,
independently computed intrinsic measurements to the dependent set with a
per-metric covered denominator (never one collapsed coverage number), and
R012 is implemented because `rh_cli downstream --mirror a:b` feeds
accepted grouping assertions into `rh_family_dedup` on the product path
(both tested in `tests/test_downstream_cli.sh`) — plus 12 safety rules.
Every `partial` entry carried an explicit `gap`; none remain.

**Governance / migrations / release (M12):** `docs/GOVERNANCE.md`
(definition-first metric process with the tests that enforce each rule,
version-not-rewrite for changed denominators, correction/dispute handling,
human-review and paywall boundaries), `docs/operations/MIGRATIONS.md`
(versioned artifacts table, rollback = restore + replay, no silent
reinterpretation, schema tests independent of generated code, and an
explicit list of what is *not* guaranteed), and `docs/operations/RELEASE.md`
(release checklist and recovery, with roadmap-as-released and hidden-score
prohibitions). `tests/test_docs.sh` verifies the documents exist, that
every file/command path they cite resolves, that they name the enforced
mechanisms, and that they contain no safety/trust verdict language.

**Metric availability profile:** `metrics/profiles/per-project.json`
(regenerated by `tools/metric-profile.sh`, checked by
`tests/test_profile.sh`) derives the reachable set mechanically from
`metrics/definitions`: **reachable means `implementation_status ==
"implemented"`** (computed on the real scan path). It lists 209 reachable
and 2 prototypes not available, carries a per-entry `status_note`, and includes the
per-source availability matrix (public/authorized/unauthorized/unsupported)
so "why is this metric absent" has a mechanical answer. No not-available
metric can appear in the reachable list (asserted).

**Public schemas (M00-05):** `schemas/` holds versioned public schemas
(`rh-jsonschema/1` dialect, six families: connector-manifest,
canonical-repo, dep-graph, cyclonedx, spdx, registry-meta), each declaring
its target fixture globs. `tools/schema-check.sh` validates the real
checked-in fixtures independently of generated code, and
`tests/test_schemas.sh` runs it plus a negative control that proves a
malformed document is rejected. This is the named `schemas/` + schema-check
tooling from the repo-structure section.

**M11 scope (in progress):** `src/rh_experimental.elisa` is the isolation
gateway R024 requires: a metric may enter the experimental group only with
an opt-in flag, wave G, a medium/high cost class, and at least one stated
limit (`rh_exp_admissible`); `tools/metric-lint.sh` enforces the same on the
definition and rejects verdict language. One sample advanced metric,
`discontinuity.no_qualifying_release_in_horizon`, reports an **observable
horizon outcome** among subjects with complete follow-up (incomplete
follow-up is censored, excluded from the denominator; zero-observable ⇒
not_applicable) and carries the mandatory label `rh_exp_label()`; it is
never a reliability or project verdict and is excluded from the runtime
registry and default policy path. It is a real path too:
`src/rh_experimental_report.elisa` + `rh_cli experimental --input <file>
--out <file>` emit `rh-experimental-result/1` — each spec's admissibility
(opt-in, wave G, costed, limited) with a reason when rejected, and the
discontinuity aggregate where a censored subject is excluded from the
denominator and zero-observable is `not_applicable`; the mandatory label
travels with the result (`tests/test_experimental_cli.sh`). A second M11
adapter is a concrete first-level cadence-deviation surface:
`rh_exp_cadence_outcome`/`rh_exp_cadence_baseline`/`rh_exp_cadence_findings`
report per-window indices at or below a caller-declared floor after a
caller-declared baseline (exact sum/baseline rational; unobservable windows
excluded, never zero), registered as
`anomaly.cadence_deviation_windows` (wave G, opt-in, costed, limited). It
emits concrete findings, never an aggregated suspicion score, and is
explicitly not a maliciousness/health judgement
(`src/test_m11.elisa`, `tests/test_m11.sh`). A formal-proof evidence adapter
is now available: `rh_cli proof --input <file> --out <file>` consumes
`rh-proof-input/1` and emits `rh-proof-result/1`, retaining proposition id,
source revision, checker version, proof digest, replay result, assumptions,
trusted computing base, and a separate bound/conflicted/unbound artifact
status (`tests/test_proof_cli.sh`). It never runs a checker and never calls
replay a whole-application safety claim. Forecast evidence is now covered by
`rh_cli forecast --input <file> --out <file>`, which validates temporal,
family-separated, censoring-aware splits and exact calibration fields in
`rh-forecast-result/1`; it is labelled experimental and cannot change policy
(`tests/test_forecast_cli.sh`). Benchmark evidence is covered by the M10
profile manifest. Intervention evaluation is
now available through `rh_cli intervention --input <file> --out <file>`, which
emits `rh-intervention-result/1` with explicit scope, selection rationale,
baseline, comparison, outcomes, and limitations; it remains observational and
does not claim causal benefit or prevented incidents
(`tests/test_intervention_cli.sh`).

**M10 scope (in progress):** scaling is measured, not assumed.
`src/bench_runner.elisa` generates deterministic uniform, long-tail, central-hub,
cyclic, and ecosystem profiles at 100, 1,000, and 10,000 nodes. `tools/bench.sh`
and `tools/profile.sh` each take one warmup and ten timed process samples per
workload, recording median/p95/variance, per-process peak RSS, source and binary
identity, toolchain, hardware/disk context, cache conditions, and controlled
batches of 1–32 local workload processes. Throughput is aggregate per batch;
peak RSS remains the largest individual child observation. The manifests are
`rh-bench/3` and `rh-profile/3`. Both retain
structural digests and exact counts, and tests assert workload identity, sample
count, resource fields, and output determinism without asserting performance
thresholds. `rh-bench/3` also writes and verifies a temporary 17-file / 13-object
corpus through the local content-addressed store, measuring input bytes, stored
logical bytes, deduplication, and filesystem allocation when available. The
10,000-node workload avoids graph traversal; query profiles use
bounded cases, including central-hub and cycle graphs. The ecosystem profile
exercises package-version identities, accepted mirror grouping, independent
partial history/review coverage, temporal and runtime/Linux graph projections,
and the real correction invalidation/replay path. Core workloads remain synthetic and do not cover arbitrary historical
correction replay or worker-scheduler load shedding. `RH_PROFILE_REPO` now opts
into a full local Git-history scan that records source revision, history digest,
counts, latency, and memory samples without retaining raw identities or fetching
remotely. Concurrency results include a 1 ms target-poll series summing live-
child RSS reads per driver pass, explicit missed samples, and a conservative
sum-of-high-water-marks bound; short peaks can fall between polls.
Request-budget variation, remote object storage, and deployed database load also
remain unmeasured. Downstream shared-cache snapshots now use
`rh-projection-snapshot/2`: they store only the public downstream graph, remap
visible node IDs, drop private nodes and incident edges, and omit unknown fields,
unresolved rows, and advisory witnesses. A regression checks two visibility
policies against one content-addressed root and verifies each immutable payload
contains only its own visible graph. This covers snapshot payload isolation, not
deployed tenant authorization, so the M10 capacity exit gate remains open (scope:
`docs/operations/BENCHMARKS.md`).
The measured core also has rebuildable derived artifacts: `rh_cli snapshot`
emits `rh-columnar-snapshot/1` column exports, `rh_cli aggregate` emits
validated daily/weekly `rh-aggregate-result/1` rows with correction-scoped
invalidation, and `rh_cli index` emits digest-bound incoming/outgoing
`rh-index-manifest/1` CSR indexes. These artifacts preserve source digests and
do not replace canonical evidence. No approximate or accelerated mode is
enabled, and no graph-DB optimization has been added without a measured need.

**Property layer:** `src/test_properties.elisa` (harness
`tests/test_properties.sh`) asserts invariants over many inputs rather than
exact expected values — `1/n ≤ HHI ≤ 1` and `1 ≤ effective ≤ n` by exact
cross-multiplication, HHI and 50% absence-factor reorder independence,
concentration monotonicity in the threshold (k50 ≤ k80), empty ⇒
not_applicable (not zero), identity accept/revoke reversibility with the
revision returning to 0, depth-limit monotonic reachability, and public
projection ⊂ unfiltered. This is a distinct layer, not a substitute for the
oracle/unit suites; the local suite is now **12 harnesses**.

**M01 tracked gap:** the exit gate asks for local-path vs *remote fixture
server* equivalence. Covered now: local path vs local clone (identical
metrics, distinct provenance) plus `https` clone support in the scanner.
A localhost fixture server is not used — the threat model forbids loopback
targets for collection, and no exception is granted for tests. The gap
stays open until a controlled remote fixture exists that does not violate
S002.

**Research-paper follow-up status (2026-09-19):** RP-02 now has a real
`rh-lineage-input/1` -> `rh-lineage-result/1` path with field-level loss
states, separate delivery/origin assessment identity, and raw/derived/modeled
metric classes (`tests/test_lineage_cli.sh`). RP-03 has a filesystem-backed
`rh-ingest-input/1` -> `rh-ingest-result/1` conformance replay that writes
events before cursors and distinguishes duplicate, empty, failed, partial, and
stale-lease outcomes (`tests/test_ingest_conformance_cli.sh`). RP-04 has a
reviewed adapter binding contract (`rh-adapter-manifest-result/1`) that pins
source review, rights, interface revision, complete cache identity, and graph
snapshot context (`tests/test_adapter_manifest_cli.sh`). RP-05, RP-06, and
RP-07 have role-grain, bounded population, and evidence-drill-down product
paths with deterministic negative tests. The RP-01 ledger in
`ops/research-conformance.json` maps all 48 proposed paper fixtures to actual
paths: 48 are covered and 0 remain partial with named open assertions. The
paper's Appendix D helper results are not claimed as locally rerun evidence.

## Metric catalog status (209 implemented definitions; 226 Architecture keys lack an implemented definition)

| Metric key | Version | Stage |
|---|---|---|
| history.commit_count | 1.0.0 | `implemented` (F001, F002) |
| history.reachable_revisions | 1.0.0 | `implemented` (F001, F002) |
| history.reachable_merge_count | 1.0.0 | `implemented` (F002) |
| history.rejected_record_count | 1.0.0 | `implemented` (F003; structurally rejected Git log records remain visible as a parser-integrity count) |
| history.missing_object_count | 1.0.0 | `implemented` (F001, F004; explicit unavailable blob-size records in retained git tree evidence remain partial, never silently complete) |
| history.coverage_state | 1.0.0 | `implemented` (F001, F003) |
| activity.commit_event_count | 1.0.0 | `implemented` (F001, F002) |
| activity.active_complete_months | 1.0.0 | `implemented` (F001, F002) |
| contributors.raw_identity_count | 1.0.0 | `implemented` (F001, F002) |
| contributors.automation_known | 1.0.0 | `implemented` (F001, F002, heuristic — see below) |
| coverage.window_completeness | 1.0.0 | `implemented` (F001, F003) |
| coverage.window_completeness | 2.0.0 | `implemented` (F003, F038; full requested-window denominator on shallow/truncated scans) |
| freshness.evidence_max_age_hours | 1.0.0 | `implemented` (F001, F002, F008) |
| source.manifest_presence | 1.0.0 | `implemented` (F001; local worktrees only) |
| documentation.readme_present | 1.0.0 | `implemented` (F001; root-level recognized README path in retained snapshot file list) |
| documentation.contributing_guide_present | 1.0.0 | `implemented` (F001; root-level recognized CONTRIBUTING path in retained snapshot file list) |
| licensing.license_declaration_present | 1.0.0 | `implemented` (F001; root-level LICENSE or COPYING path in retained snapshot file list) |
| documentation.installation_guide_present | 1.0.0 | `implemented` (F001; recognized installation/build path in retained snapshot file list) |
| documentation.api_reference_present | 1.0.0 | `implemented` (F001; recognized API reference path in retained snapshot file list) |
| governance.governance_document_present | 1.0.0 | `implemented` (F001; recognized governance or conduct document path in retained snapshot file list) |
| governance.code_ownership_rules_present | 1.0.0 | `implemented` (F001; CODEOWNERS path in retained snapshot file list) |
| licensing.source_notice_presence | 1.0.0 | `implemented` (F001; recognized NOTICE path in retained snapshot file list) |
| governance.release_process_document_present | 1.0.0 | `implemented` (F001; recognized release-process path in retained snapshot file list) |
| governance.succession_process_document_present | 1.0.0 | `implemented` (F001; recognized succession/handover path in retained snapshot file list) |
| licensing.license_file_count | 1.0.0 | `implemented` (F001; counted recognized LICENSE/COPYING paths in retained snapshot file list) |
| documentation.example_program_count | 1.0.0 | `implemented` (F001; counted files below the root examples/ path in retained snapshot file list) |
| security.security_policy_present | 1.0.0 | `implemented` (F001; recognized SECURITY path in retained snapshot file list) |
| release.release_note_presence | 1.0.0 | `implemented` (F001; recognized changelog/news/release-note path in retained snapshot file list) |
| release.release_note_presence | 2.0.0 | `implemented` (F021, F023, F024; explicit per-release note retrieval outcomes over all accepted releases; missing states remain partial/unsupported) |
| code.source_file_count | 1.0.0 | `implemented` (F001; counted retained source-extension paths in the snapshot file list) |
| persistence.retained_90d | 1.0.0 | `implemented` (F015; full non-shallow history only — windowed/shallow is `unsupported`) |
| persistence.retained_365d | 1.0.0 | `implemented` (F015; full non-shallow history only — 365–394 day return windows, censored before the window completes) |
| persistence.returning_after_gap | 1.0.0 | `implemented` (F001, F015; actors spanning the configured 90-day gap under complete history) |
| dependencies.unsupported_range_count | 1.0.0 | `implemented` (F022; `rh_cli deps`, declared supported-syntax subset; unsupported ≠ missing) |
| concentration.change_hhi | 1.0.0 | `implemented` (F013; `rh_cli continuity`, exact rational HHI over commit events) |
| concentration.change_effective_actor_count | 1.0.0 | `implemented` (F012, F013; exact reciprocal of HHI; one-off actors inflate it) |
| concentration.change_absence_factor_50 | 1.0.0 | `implemented` (F012, F013; top-actor count reaching 50% of commit events) |
| concentration.change_top1_share | 1.0.0 | `implemented` (F013; `rh_cli continuity`, exact rational: largest actor's share of commit events) |
| concentration.change_gini | 1.0.0 | `implemented` (F013; `rh_cli continuity`, exact rational Gini of the actor commit-count distribution) |
| succession.handover_overlap_months | 1.0.0 | `implemented` (F017; `rh_cli succession`, count of complete months in which a declared predecessor/successor pair are both active; absent pair is `not_applicable`) |
| succession.declared_handovers | 1.0.0 | `implemented` (F017; distinct explicit predecessor/successor pair count) |
| succession.observed_activity_overlap_months | 1.0.0 | `implemented` (F017; complete months with qualifying activity by both named participants) |
| persistence.persistent_12m | 1.0.0 | `implemented` (F001, F002, F015; six-active-month, six-span continuity cohort with explicit partial coverage) |
| persistence.persistent_24m | 1.0.0 | `implemented` (F001, F002, F015; trailing 24-month profile with explicit 12-month activity/span thresholds) |
| persistence.retention_censored | 1.0.0 | `implemented` (F001, F002, F015, F016; actors whose requested return window is censored) |
| persistence.active_3_of_12_months | 1.0.0 | `implemented` (F001, F002, F015, F016; actor groups active in at least three trailing complete months) |
| persistence.active_6_of_12_months | 1.0.0 | `implemented` (F001, F002, F015, F016; actor groups active in at least six trailing complete months) |
| persistence.active_9_of_12_months | 1.0.0 | `implemented` (F001, F002, F015, F016; actor groups active in at least nine trailing complete months) |
| persistence.persistent_event_share | 1.0.0 | `implemented` (F001, F002, F015, F016; qualifying events attributable to the persistence cohort) |
| persistence.median_observed_tenure_days | 1.0.0 | `implemented` (F001, F002, F015, F016; median first-to-last observed actor span) |
| roles.owner_declaration_count | 1.0.0 | `implemented` (F012, F013, F014; captured owner declarations, separate from observed actions) |
| roles.maintainer_declaration_count | 1.0.0 | `implemented` (F012, F013, F014; captured maintainer declarations, separate from observed actions) |
| roles.triager_declaration_count | 1.0.0 | `implemented` (F012, F013, F014; captured triager declarations, separate from observed actions) |
| roles.member_declaration_count | 1.0.0 | `implemented` (F012, F013, F014; captured member declarations, separate from observed actions) |
| roles.unknown_declaration_count | 1.0.0 | `implemented` (F012, F013, F014; declarations with unrecognized role strings remain unknown) |
| roles.provider_declaration_count | 1.0.0 | `implemented` (F012, F013, F014; declarations grouped by captured provider source) |
| roles.file_declaration_count | 1.0.0 | `implemented` (F012, F013, F014; declarations grouped by project-file source) |
| roles.operator_declaration_count | 1.0.0 | `implemented` (F012, F013, F014; declarations grouped by operator source) |
| adoption.unknown_count | 1.0.0 | `implemented` (F021, F023, F024; adoption records without a supported state remain unknown) |
| adoption.first_seen_only_count | 1.0.0 | `implemented` (F021, F023, F024; collector first-seen evidence stays separate from historical introduction) |
| adoption.confirmed_introduction_count | 1.0.0 | `implemented` (F021, F023, F024; explicitly confirmed dependency introductions) |
| adoption.confirmed_removal_count | 1.0.0 | `implemented` (F021, F023, F024; explicitly confirmed dependency removals) |
| graph.direct_dependents_count | 1.0.0 | `implemented` (F030, F031, F032; direct incoming consumers in a labeled public graph projection) |
| graph.transitive_dependents_count | 1.0.0 | `implemented` (F030, F031, F032; bounded unique transitive consumers with visited-set semantics) |
| graph.scc_component_count | 1.0.0 | `implemented` (F030, F031, F032; cycle-aware component count in the graph projection) |
| graph.scenario_affected_count | 1.0.0 | `implemented` (F030, F031, F032; affected consumers for an explicitly requested unavailable-node scenario) |
| population.selected_dependent_count | 1.0.0 | `implemented` (F030, F031, F032; selected dependent projects in the bounded focal-library population) |
| population.distinct_family_count | 1.0.0 | `implemented` (F030, F031, F032; distinct accepted project families represented in the selected population) |
| population.unresolved_mapping_count | 1.0.0 | `implemented` (F030, F031, F032; unresolved mappings remain visible instead of being dropped) |
| coverage.observed_capability_count | 1.0.0 | `implemented` (F021, F023, F024; source-scoped capability records in observed state) |
| coverage.partial_capability_count | 1.0.0 | `implemented` (F021, F023, F024; source-scoped capability records with incomplete acquisition) |
| coverage.stale_capability_count | 1.0.0 | `implemented` (F021, F023, F024; source-scoped capability records whose freshness is stale) |
| coverage.unavailable_capability_count | 1.0.0 | `implemented` (F021, F023, F024; unavailable capability records remain distinct) |
| coverage.unauthorized_capability_count | 1.0.0 | `implemented` (F021, F023, F024; authorization failure remains distinct from unsupported) |
| coverage.not_applicable_capability_count | 1.0.0 | `implemented` (F021, F023, F024; capabilities outside the source scope remain not applicable) |
| coverage.unsupported_capability_count | 1.0.0 | `implemented` (F021, F023, F024; unsupported capabilities remain explicit) |
| inventory.component_count | 1.0.0 | `implemented` (F021, F023, F024; components or packages in a supported CycloneDX or SPDX document) |
| inventory.invalid_component_count | 1.0.0 | `implemented` (F021, F023, F024; malformed component records remain counted) |
| inventory.components_with_purl_count | 1.0.0 | `implemented` (F021, F023, F024; parsed Package URLs are retained) |
| inventory.components_with_hash_count | 1.0.0 | `implemented` (F021, F023, F024; hash-bearing records remain distinguishable) |
| inventory.known_digest_count | 1.0.0 | `implemented` (F021, F023, F024; only valid supported digests count as known) |
| inventory.unknown_field_count | 1.0.0 | `implemented` (F021, F023, F024; unmodeled top-level fields are counted, not dropped) |
| release.release_count | 1.0.0 | `implemented` (F021, F023, F024; accepted releases from a bounded release-only feed) |
| release.rejected_count | 1.0.0 | `implemented` (F021, F023, F024; malformed release records remain counted) |
| release.asset_count | 1.0.0 | `implemented` (F021, F023, F024; assets attached to accepted release records) |
| release.digest_known_count | 1.0.0 | `implemented` (F021, F023, F024; release assets carrying recognized digests) |
| release.published_time_known_count | 1.0.0 | `implemented` (F021, F023, F024; releases with publisher-supplied valid time) |
| release.stable_count | 1.0.0 | `implemented` (F021, F023, F024; releases explicitly classified with `prerelease=false`) |
| release.prerelease_count | 1.0.0 | `implemented` (F021, F023, F024; releases explicitly classified with `prerelease=true`) |
| security.known_unique_advisories | 1.0.0 | `implemented` (F022, F023, F024; deduplicated advisory groups from supplied OSV evidence) |
| security.affected_resolved_nodes | 1.0.0 | `implemented` (F022, F023, F024; resolved nodes represented by matched advisory groups) |
| security.withdrawn_advisory_count | 1.0.0 | `implemented` (F022, F023, F024; withdrawn records encountered in supplied OSV evidence) |
| dependency.requirements_direct | 1.0.0 | `implemented` (F022, F023, F024; root requirements in selected graph context) |
| dependency.resolved_direct_versions | 1.0.0 | `implemented` (F022, F023, F024; unique exact destination nodes of root edges) |
| dependency.unresolved_requirements | 1.0.0 | `implemented` (F022, F023, F024; root requirements without accepted exact edges) |
| dependency.resolved_transitive_versions | 1.0.0 | `implemented` (F022, F023, F024; unique resolved nodes reachable from the selected graph root) |
| security.known_advisory_records | 1.0.0 | `implemented` (F022, F023, F024; matched advisory records before alias-group deduplication) |
| security.affected_direct_nodes | 1.0.0 | `implemented` (F022, F023, F024; matched advisory nodes that are direct destinations from the selected graph root) |
| security.affected_transitive_nodes | 1.0.0 | `implemented` (F022, F023, F024; matched advisory nodes reachable beyond the direct root destinations) |
| security.affected_unreachable_nodes | 1.0.0 | `implemented` (F022, F023, F024; matched advisory nodes outside the selected root reachability projection) |
| dependency.runtime_direct_count | 1.0.0 | `implemented` (F022, F023, F024; direct requirements classified as runtime/normal by the ecosystem parser) |
| dependency.build_direct_count | 1.0.0 | `implemented` (F022, F023, F024; direct requirements classified as development/build/toolchain by the ecosystem parser) |
| dependency.optional_direct_count | 1.0.0 | `implemented` (F022, F023, F024; direct requirements explicitly optional or conditionally activated) |
| dependency.unknown_scope_count | 1.0.0 | `implemented` (F022, F023, F024; requirements whose captured purpose or scope could not be established) |
| dependency.unpinned_requirement_count | 1.0.0 | `implemented` (F022, F023, F024; requirements that do not bind one literal version or artifact) |
| dependency.artifact_digest_coverage | 1.0.0 | `implemented` (F022, F023, F024; resolved destination nodes with observed artifact digests over resolved destination nodes) |
| dependency.maximum_observed_depth | 1.0.0 | `implemented` (F022, F023, F024; maximum shortest-path depth reached from the selected graph root) |
| dependency.resolution_complete | 1.0.0 | `implemented` (F022, F023, F024; no unresolved requirement attached to a reachable graph node) |
| graph.node_count | 1.0.0 | `implemented` (F022, F023, F024; visible nodes in the selected dependency graph projection) |
| graph.edge_count | 1.0.0 | `implemented` (F022, F023, F024; visible resolved edges in the selected dependency graph projection) |
| security.advisory_match_unknown_nodes | 1.0.0 | `implemented` (F022, F023, F024; resolved nodes whose advisory matching context is unknown) |
| security.fixed_version_available | 1.0.0 | `implemented` (F022, F023, F024; matched advisory evidence includes a fixed release event) |
| graph.cyclic_node_share | 1.0.0 | `implemented` (F030, F031, F032; visible nodes participating in a directed cycle over visible projection nodes) |
| graph.traversal_truncated | 1.0.0 | `implemented` (F030, F031, F032; selected traversal reached its configured node or depth budget) |
| release.latest_stable_age_days | 1.0.0 | `implemented` (F021, F023, F024; age from newest published stable release to explicit first_seen cutoff) |
| release.interrelease_median_days | 1.0.0 | `implemented` (F021, F023, F024; median interval over published stable releases) |
| release.interrelease_variance | 1.0.0 | `implemented` (F021, F023, F024; population variance over stable release intervals) |
| provenance.artifact_digest_present_share | 1.0.0 | `implemented` (F021, F023, F024; inventory components carrying hash material over parsed inventory components) |
| graph.strongly_connected_components | 1.0.0 | `implemented` (F030, F031, F032; SCC count in the labeled dependency projection) |
| graph.reverse_reachability_count | 1.0.0 | `implemented` (F030, F031, F032; unique visible consumers reachable from the selected subject) |
| coverage.requested_capabilities | 1.0.0 | `implemented` (F010, F011, F012; capability requests represented in the source-specific coverage ledger) |
| coverage.available_capability_share | 1.0.0 | `implemented` (F010, F011, F012; observed, partial, and stale capabilities over requested applicable capabilities) |
| coverage.unauthorized_capabilities | 1.0.0 | `implemented` (F010, F011, F012; requested capabilities explicitly marked unauthorized) |
| policy.evaluations | 1.0.0 | `implemented` (F038, F039, F040; completed policy evaluations bound to policy and evidence digests) |
| policy.allow_count | 1.0.0 | `implemented` (F038, F039, F040; evaluations returning allow under the four-valued policy lattice) |
| policy.warn_count | 1.0.0 | `implemented` (F038, F039, F040; evaluations returning warn under the declared precedence) |
| policy.deny_count | 1.0.0 | `implemented` (F038, F039, F040; evaluations returning deny with an evidenced blocking rule) |
| policy.unknown_count | 1.0.0 | `implemented` (F038, F039, F040; evaluations unable to decide from required evidence) |
| policy.active_exceptions | 1.0.0 | `implemented` (F038, F039, F040; approved, unexpired exceptions applying to the exact evaluation) |
| policy.exception_expiry_days | 1.0.0 | `implemented` (F038, F039, F040; minimum remaining whole days for an approved exception applied to the exact evaluation) |
| concentration.top1_event_share | 1.0.0 | `implemented` (F012, F013, F015; largest actor share of accepted change events) |
| concentration.top3_event_share | 1.0.0 | `implemented` (F012, F013; exact top-three share of attributed commit events) |
| concentration.top5_event_share | 1.0.0 | `implemented` (F012, F013; exact top-five share of attributed commit events) |
| concentration.hhi | 1.0.0 | `implemented` (F012, F013, F015; exact HHI over accepted change events) |
| concentration.effective_actor_count | 1.0.0 | `implemented` (F012, F013, F015; reciprocal of exact change-event HHI) |
| concentration.absence_factor_50 | 1.0.0 | `implemented` (F012, F013, F015; smallest actor population reaching 50 percent of events) |
| concentration.actor_count_80 | 1.0.0 | `implemented` (F012, F013, F015; smallest actor population reaching 80 percent of events) |
| activity.accepted_changes | 1.0.0 | `implemented` (F001, F002, F003; accepted Git change records in the selected observation window) |
| downstream_condition.intrinsic_coverage_share | 1.0.0 | `implemented` (F030, F031, F032; independently supplied intrinsic metric cells covered across the bounded dependent projection) |
| coverage.partial_collection_count | 1.0.0 | `implemented` (F010, F011, F012; selected collection run with an explicit partial capability state) |
| coverage.source_freshness_hours | 1.0.0 | `implemented` (F010, F011, F012; elapsed whole hours from the latest observed capability known_as_of to collected_at) |
| coverage.parser_error_count | 1.0.0 | `implemented` (F022, F023, F024; parser-support mismatches retained by bounded differential comparison) |
| coverage.mapping_conflict_count | 1.0.0 | `implemented` (F022, F023, F024; unmatched package, edge, or unresolved identities in parser differential comparison) |
| coverage.replay_match_share | 1.0.0 | `implemented` (F001, F002, F003; deterministic replay observations matching stored digest and counts) |
| coverage.lineage_complete_share | 1.0.0 | `implemented` (F001, F002, F003; published observations with complete local evidence references and bundle binding) |
| activity.active_months | 1.0.0 | `implemented` (F001, F002, F003; complete calendar months containing accepted change records) |
| contributor.source_accounts | 1.0.0 | `implemented` (F001, F002, F003; distinct source-scoped author accounts in retained Git evidence) |
| contributor.accepted_actor_clusters | 1.0.0 | `implemented` (F010, F031, F032; accepted identity-link clusters at a pinned identity revision) |
| contributor.known_human_accounts | 1.0.0 | `implemented` (F010, F031, F032; explicit human actor-kind classifications, unresolved actors excluded) |
| dependency.runtime_requirements | 1.0.0 | `implemented` (F022, F023, F024; captured requirements explicitly classified as runtime/normal scope) |
| dependency.development_requirements | 1.0.0 | `implemented` (F022, F023, F024; captured requirements explicitly classified as development scope) |
| dependency.optional_requirements | 1.0.0 | `implemented` (F022, F023, F024; captured requirements explicitly classified as optional scope) |
| dependency.peer_requirements | 1.0.0 | `implemented` (F022, F023, F024; captured requirements explicitly classified as peer scope) |
| dependency.unknown_scope_requirements | 1.0.0 | `implemented` (F022, F023, F024; captured requirements whose source scope is explicitly unknown) |
| dependency.runtime_resolved_edges | 1.0.0 | `implemented` (F022, F023, F024; resolved edges explicitly classified as runtime/normal scope) |
| dependency.development_resolved_edges | 1.0.0 | `implemented` (F022, F023, F024; resolved edges explicitly classified as development scope) |
| dependency.optional_resolved_edges | 1.0.0 | `implemented` (F022, F023, F024; resolved edges explicitly classified as optional scope) |
| dependency.peer_resolved_edges | 1.0.0 | `implemented` (F022, F023, F024; resolved edges explicitly classified as peer scope) |
| dependency.unknown_scope_resolved_edges | 1.0.0 | `implemented` (F022, F023, F024; resolved edges whose captured source scope is explicitly unknown) |
| dependencies.ecosystem_count | 1.0.0 | `implemented` (F022, F023, F024; supported ecosystems represented by captured dependency manifests) |
| dependencies.declared_requirement_count | 1.0.0 | `implemented` (F022, F023, F024; declared requirement expressions across supported manifests) |
| dependencies.resolved_edge_count | 1.0.0 | `implemented` (F022, F023, F024; exact edges resolved under ecosystem-native rules) |
| dependencies.unresolved_requirement_count | 1.0.0 | `implemented` (F022, F023, F024; unresolved requirements retain explicit reasons) |
| history.revisions_observed | 1.0.0 | `implemented` (F001, F002; accepted Git records across the retained ref set) |
| history.revisions_reachable_all_refs | 1.0.0 | `implemented` (F001, F002; `git log --all` snapshot) |
| history.revisions_reachable_default | 1.0.0 | `implemented` (F001, F002, F003; retained `git rev-list --count HEAD` default-branch projection) |
| history.collection_complete_windows | 1.0.0 | `implemented` (F001, F003; complete/requested counts for the retained scan interval) |
| history.first_author_time | 1.0.0 | `implemented` (F001, F002, F008; earliest valid author timestamp, source-authored time) |
| history.history_span_days | 1.0.0 | `implemented` (F001, F002; earliest-to-latest observed author timestamp span) |
| history.shallow_boundary_count | 1.0.0 | `implemented` (F003; shallow state is retained as an explicit boundary count) |
| activity.commits | 1.0.0 | `implemented` (F001, F002; selected author-time window) |
| activity.nonmerge_commits | 1.0.0 | `implemented` (F001, F002; commits with at most one parent) |
| activity.merge_commits | 1.0.0 | `implemented` (F001, F002; commits with more than one parent) |
| activity.active_days | 1.0.0 | `implemented` (F001, F002; distinct UTC author dates) |
| activity.longest_observed_gap_days | 1.0.0 | `implemented` (F001, F002; complete in-window event gaps) |
| activity.median_interevent_hours | 1.0.0 | `implemented` (F001, F002; ordered in-window author-time gaps) |
| activity.weekly_count_slope | 1.0.0 | `implemented` (F001, F002; exact ordinary least-squares slope over complete Unix weeks) |
| activity.weekly_count_variance | 1.0.0 | `implemented` (F001, F002; exact population variance over complete Unix weeks) |
| activity.bot_event_share | 1.0.0 | `implemented` (F001, F002, F011; known bot heuristic events over selected events) |
| contributor.raw_author_identities | 1.0.0 | `implemented` (F001, F002, F009; raw author-email evidence) |
| contributor.known_bot_accounts | 1.0.0 | `implemented` (F001, F002, F011; opaque actor groups with the bounded bot heuristic) |
| contributor.unclassified_accounts | 1.0.0 | `implemented` (F001, F002, F011; actor groups not classified as known bot) |
| contributor.first_observed_contributors | 1.0.0 | `implemented` (F001, F002, F003; full-history path, partial/unknown for windowed history) |
| contributor.single_event_contributors | 1.0.0 | `implemented` (F001, F002, F012; exact actor-event cardinality) |
| contributor.contributors_2_to_5_events | 1.0.0 | `implemented` (F001, F002; exact actor-event cardinality) |
| contributor.contributors_6_to_20_events | 1.0.0 | `implemented` (F001, F002; exact actor-event cardinality) |
| contributor.contributors_over_20_events | 1.0.0 | `implemented` (F001, F002; exact actor-event cardinality) |
| contributor.single_event_share | 1.0.0 | `implemented` (F001, F002, F012; exact actor-group denominator) |

The `rh_cli registry` command prints exactly the table above — never more.

**Heuristic honesty:** `automation_known` uses a name heuristic (`[bot]`,
`github-actions*`) in M01; provider-declared bot inventories arrive in
M02/M04. The report never calls raw authors maintainers; retention and
cross-source identity are deferred to M04.

## Backlog (plan §25, items 1–20)

| # | Task | Stage |
|---|---|---|
| 1 | Baseline + ADR-000 | `implemented` (license: public domain, owner-confirmed; toolchain pinned in TOOLCHAIN.md) |
| 2 | Identifiers, intervals, observations | `implemented` (oracles green) |
| 3 | Metric-definition schema + linter | `implemented` (`rh_registry_lint` + JSON mirror check) |
| 4 | Synthetic history + graph fixtures | `implemented` (harness-built git fixtures; graph fixtures pending M03) |
| 5 | Bounded subprocess + URL policy | `implemented` (allowlist oracles + exit-3 gates) |
| 6 | Bare-Git metadata extraction | `implemented` (plumbing-only runners) |
| 7 | Evidence bundle + digest verify | `implemented` (FNV manifest + replay exit-0/5) |
| 8 | First ten foundational metrics | `implemented` (see table) |
| 9 | JSON/Markdown report + explain | `implemented` (report.json/md; `rh_cli explain` emits `repo-health-explain/1`) |
| 10–20 | (see IMPLEMENTATION_PLAN.md) | `planned` |
| maintainer.role_assignments_with_end_dates | 1.0.0 | `implemented` (F014; explicit positive revocation timestamps only) |
| maintainer.declared_current | 1.0.0 | `implemented` (F012, F013, F014; active owner/maintainer declarations at the selected as-of time) |
| maintainer.permission_observed_current | 1.0.0 | `implemented` (F012, F013, F014; authorized provider permission declarations at the selected as-of time) |
| maintainer.active_declared_12m | 1.0.0 | `implemented` (F012, F013, F014; distinct declared owner/maintainer actors active for the preceding 12 months at explicit as-of time) |
| maintainer.observed_release_actors | 1.0.0 | `implemented` (F012, F013, F014; distinct actors in supplied release-action events, separate from declarations) |
| maintainer.observed_merge_actors | 1.0.0 | `implemented` (F012, F013, F014; distinct actors in supplied merge-action events, separate from declarations) |
| maintainer.observed_review_actors | 1.0.0 | `implemented` (F012, F013, F014; distinct actors in supplied review-action events, separate from declarations) |
| maintainer.permission_inventory_coverage | 1.0.0 | `implemented` (F012, F013, F014; authorized active provider permission actors with nonzero captured permissions divided by distinct active provider actors) |
| maintainer.unattributed_release_count | 1.0.0 | `implemented` (F012, F013, F014; supplied release events with missing or null actor attribution) |
| build.ci_configuration_present | 1.0.0 | `implemented` (F001, F002; recognized CI configuration path in retained snapshot file list) |
| testing.test_files_observed | 1.0.0 | `implemented` (F001, F002; retained files below tests/, test/, or spec/) |
| maintainer.release_role_automation_share | 1.0.0 | `implemented` (F012, F013, F014; explicitly classified bot/service release events divided by attributed release events) |
| maintainer.review_share | 1.0.0 | `implemented` (F012, F013, F014; explicitly selected review actor's events divided by attributed review events) |
| code.source_bytes | 1.0.0 | `implemented` (F001, F002; recognized source-extension blob sizes from the retained long Git tree) |
| release.withdrawn_publications | 1.0.0 | `implemented` (F021, F023, F024; releases explicitly marked withdrawn in a captured release feed) |
| release.supported_lines | 1.0.0 | `implemented` (F021, F023, F024; distinct explicit supported_line labels in a captured release feed) |
| release.support_end_timestamp | 1.0.0 | `implemented` (F021, F023, F024; newest explicit support_end_at declaration, with per-release issuer retained) |
| release.release_source_mapping_coverage | 1.0.0 | `implemented` (F021, F023, F024; explicit source-mapped release states divided by releases with supplied mapping state) |
| release.tag_target_changes | 1.0.0 | `implemented` (F021, F023, F024; explicit target changes for repeated release tags, ordered by known observation time) |
| concentration.release_actor_count_80 | 1.0.0 | `implemented` (F012, F013, F014; minimum distinct release-action actors reaching 80% of supplied release actions) |
| concentration.review_actor_count_80 | 1.0.0 | `implemented` (F012, F013, F014; minimum distinct review-action actors reaching 80% of supplied review actions) |
