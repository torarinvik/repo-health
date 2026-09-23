# Changelog

All notable changes to the repo-health Elisa reference implementation are
documented here. Statuses (`planned` … `released`) follow
IMPLEMENTATION_PLAN.md §2.3; nothing is listed as done without tested code
on the real execution path.

## [Unreleased]

### Fixed
- M12 release packet (`tools/release-packet.sh`): the `limitations` block
  had drifted behind the implementation. It now says what the tree can
  actually back up — native VCS parsers span Mercurial, Subversion and
  Fossil (still fixture-driven, no live tooling); dependency parsers span
  Cargo, npm, PyPI and Go declared-requirement subsets; CycloneDX and SPDX
  2.3 inventories are pinned; the HTTP listener exposes a server-rendered
  `/_report.html`; and notification state is durable via `--state`. A
  release packet that understates or overstates capability is a defect in
  its own right, so this is a correctness fix, not cosmetics.

### Added
- M08 PEP 440 local-version ordering now compares bounded normalized local
  segments (case-folded text, equivalent separators, numeric ordering) instead
  of treating all local labels as equal. The parser caps labels at eight
  segments, eight text characters per segment, and numeric values through
  1e12; `rh-pep440-result/2` reports each valid version's local segment count.
  Contract and regression coverage include mixed numeric/text segments and
  inputs outside each bound.
- M03 Python lock evidence: `src/rh_pylock.elisa` and
  `rh_cli pylock --input <pylock.toml> --out <file>` emit
  `rh-pylock-audit/1` for bounded PEP 751 package-to-package auditing. The
  report keeps package markers and Python constraints, marks dependency links
  informational, and never invents a project-root relationship that the format
  does not record; `input_sha256` binds the result to the exact lock bytes.
  The top-level environment, extra, dependency-group, and default-group arrays are
  preserved in declaration order without evaluating selection semantics.
  Missing, ambiguous, and source-specific references remain distinct. Bounded
  wheel, sdist, and archive records retain expected hash values and fingerprint
  URL/path locators with SHA-256 without publishing the locators, including
  table and inline-table input forms. Optional declared artifact sizes are
  projected as `size_bytes` and checked against supplied local bytes. Explicit UTC
  artifact `upload-time` values are retained as source event times. Optional
  archive `subdirectory` values are retained as package-root context within the
  archive. Package index URLs are retained only as `index_sha256` fingerprints.
  `[packages.vcs]` records retain the VCS type, exact commit ID, optional
  requested revision, source subdirectory, and a fingerprint of the URL/path
  locator. `[packages.directory]` records retain a path fingerprint, editable
  flag (defaulting to `false`), and source subdirectory. Locators remain private.
  VCS, directory, and archive dependency selectors narrow package candidates by
  their supplied source fields; unknown selector fields remain context-only.
  Package attestation identities retain `kind`, publisher-specific string
  fields, and inline string-valued `claims` members as recorded, without claiming
  attestation verification. Other claim value types fail closed.
  Environment/group selection, complete artifact projection, and unsupported
  fields remain counted as gaps.
  `rh_cli pylock-observe` now verifies supplied local bytes against SHA-256,
  SHA-384, and SHA-512 values and emits a separate
  `rh-pylock-artifact-observation-result/1` sidecar bound to the audit digest
  and artifact ID. Size/hash mismatches remain `changed`; unknown algorithms
  remain unsupported. `tests/test_pylock_cli.sh`, checked-in goldens, schemas,
  and public-contract entries cover both paths. Full TOML validation,
  complete artifact metadata, project manifest integration, and use as a
  resolved dependency graph remain open.
- M11 forecast evidence now requires a named observable binary outcome and
  retains model and baseline Brier scores with the same submitted evaluation
  cohort identifier and sample count. `rh-forecast-input/2` and
  `rh-forecast-result/2` reject mismatched
  baseline cohorts, a baseline identical to the model, and labels outside
  `event`/`no_event`; both outputs remain experimental and outside policy
  decisions. `tests/test_forecast_cli.sh` covers the new comparison and
  fail-closed cases.
- M08 review-workflow lane — Gerrit: `src/rh_gerrit.elisa` plus
  `rh_cli vcs --format gerrit` (`rh-gerrit/1`) parse a Gerrit changes query
  response and fold N re-pushed patch-sets into **one** logical change keyed
  by the stable `_number`, so a 3x-revised series is one change with
  `revision_count` 3 — never three separate changes (R025, no workflow
  redefinition per provider). `created`/`updated` use the RFC-style Gerrit
  timestamp with fractional seconds dropped and an unparseable time failing
  closed; non-PR semantics are preserved without demanding a GitHub merge
  request. The parser only counts value nodes in the JSON object so a key
  named like an entry is never mistaken for one. Golden fixture
  `fixtures/vcs/gerrit-changes.json`; `tests/test_vcs_cli.sh` covers the
  fold, determinism, and the fail-closed negative.
- M08 forge lane — Bitbucket Cloud connector: `rh_bitbucket_repo_canonical`
  and `rh_cli forge normalize --connector bitbucket` normalize a Bitbucket
  Cloud repo object into `rh-canonical-repo/1`. This is a genuinely
  different forge API from GitHub/GitLab/Gitea: identity is the `uuid`
  string plus workspace/repo `full_name`, the html URL is nested at
  `links.html.href`, and `created_on`/`updated_on` carry fractional seconds
  with a `+00:00` offset (dropped before the strict ISO parse, never
  guessed). Fixtures + a byte-for-byte golden are checked in, the connector
  manifest and source-review register record it (traffic is
  unauthorized/unsupported — never estimated), and `rh_cli connector check`
  reports its capability table. `tests/test_forge_cli.sh`,
  `tests/test_m02.sh`, and `tests/test_connector_cli.sh` cover the golden,
  determinism, connector-distinctness, and the fail-closed negatives.
- M09/M04-08 metric: `succession.handover_overlap_months` (v1.0.0) is now
  `implemented`, completing the catalog's last `planned` definition. New
  `src/rh_continuity.elisa` `rh_succession_metrics_write` and
  `rh_cli succession --input <file> --out <file>` publish the count of
  complete months in which an explicit **declared** predecessor/successor
  pair are both active. An absent declared pair (or the same actor for both)
  is `not_applicable` — never zero overlap — so an activity-derived
  primary change is never substituted for a declared handover (no motive
  attribution, R030). `tests/test_succession_cli.sh` covers the exact
  overlap, the not_applicable cases, determinism, and fail-closed
  negatives; the runtime registry gains entry 19 (18 implemented). Catalog
  state: 21 definitions = 18 `implemented`, 3 `prototype`, 0 `planned`.
- M02 unattended worker pass: new `src/rh_worker.elisa` and `rh_cli worker
  tick --input <file> --out <file>` (`rh-worker-plan/2`) run one bounded,
  deterministic scheduling pass over a source table: each source gets a
  full-reconcile, incremental, or skipped decision with its reconcile
  horizon/overlap/debt, plus an aggregate service-health summary. All due full
  reconciles use queue slots before incremental work, and source order rotates
  by `now` within each priority class. A bounded queue (or an exhausted host
  quota) skips the overflow but keeps each skipped source's schedule debt
  visible so the next tick retries — sources are never silently dropped. The
  pass is deterministic for its inputs, so replaying it at the same `now`
  yields the identical plan; malformed input fails closed.
  `src/test_worker.elisa` (`WORKER OK`) and `tests/test_worker_cli.sh` cover
  global priority, bounded rotation, quota refusal, determinism, and negatives;
  public contract `worker-plan` registered.
- M02-06 reconciliation policy: new `src/rh_reconcile.elisa` and `rh_cli
  reconcile --input <file> --out <file>` (`rh-reconcile-result/1`) decide
  when a periodic full reconcile is due, how far back it must look, the
  incremental cursor overlap start, and the schedule debt. Only a completed
  full reconcile advances the clock (an incremental cursor never does), the
  horizon spans the whole interval since the last full reconcile (a cursor
  proves which updates were seen, not what was deleted), a never-reconciled
  source is due immediately with debt 1, and a zero interval means "never
  scheduled" so a misconfiguration cannot cause a tight loop.
  `src/test_reconcile.elisa` (`RECONCILE OK`) and `tests/test_reconcile_cli.sh`
  cover the due/horizon/debt/overlap/mode math, determinism, and fail-closed
  negatives; public contract `reconcile-result` registered.
- M02 scheduling core: `src/rh_job.elisa` gains a bounded scheduler (enqueue/
  claim/succeed/fail/cancel/reclaim) composing failure classification with a
  token-bucket host quota and host backoff, plus `rh_cli job run --input <file>
  --out <file>` (`rh-sched-result/1`). The queue is bounded (enqueue past
  capacity is refused, never dropped); claims consume a host token; a failed
  job retries with backoff, dead-letters, or goes terminal by classification;
  an expired lease is reclaimable with a fresh fencing token so a stale worker
  cannot publish. `src/test_job.elisa` (`JOB OK`) and `tests/test_job_cli.sh`
  cover the transitions, determinism, and fail-closed negatives; public
  contract `job-schedule-result` (`rh-sched-result/1`, additive) registered.
- M02 ingestion job machine: new `src/rh_job.elisa` (failure classification,
  retry disposition, integer exponential backoff, retry/dead-letter/terminal
  transitions) and `rh_cli job classify --input <file> --out <file>`
  (`rh-job-next/1`). Failure kinds are distinct (transient, rate_limit, auth,
  unsupported, malformed, budget, canceled — never one collapsed "error");
  auth/unsupported are terminal, malformed dead-letters, transient/rate-limit/
  budget retry with backoff, and an exhausted retry dead-letters rather than
  succeeding. `src/test_job.elisa` (`JOB OK`) and `tests/test_job_cli.sh`
  cover classification, disposition, backoff monotonicity/caps, every
  transition, determinism, and fail-closed negatives; public contract
  `job-next` (`rh-job-next/1`, additive) is registered (35 contracts total).
- M02 connector instances with approved base URLs: new `src/rh_connector.elisa`
  and `rh_cli connector check --instance <file> --out <file>` read an
  `rh-connector-instance/1` document and write
  `rh-connector-instance-result/1` with the connector's full capability
  table (unsupported stated, never omitted), declared capabilities, and a
  usability verdict. This makes R007 real: an arbitrary approved public
  self-hosted base URL is `usable` with no code change, while approval and
  transport stay separate gates — a loopback/private/link-local host,
  non-https scheme, userinfo-smuggled URL, or single-label host is
  `transport-rejected` even when approved (S002). Unknown connector ids,
  unknown capability keys, and undeclared capabilities (e.g. Gitea
  `traffic`) fail closed. `tests/test_connector_cli.sh` covers the
  self-hosted fixture, six hostile URLs, per-connector capability tables,
  determinism, and the negatives; public contract `connector-instance`
  (`rh-connector-instance/1`, additive) is registered (34 contracts total).
- M06 durable correction ledger: `rh_cli correct --state <file>` now loads
  and rewrites an `rh-corrections-state/1` document (`src/rh_correction_report.elisa`
  gains `rh_correction_state_parse`/`rh_correction_state_emit` and a stateful
  `rh_correction_report_state`), carrying the revision floor, the
  last-correction ordinal already folded in (watermark), and the subjects
  superseded so far. Replaying the same corrections file is idempotent (no
  second revision advance, no re-supersede), a persisted revision floor is
  honoured, and corrupt/wrong-schema state fails closed (exit 4).
  `tests/test_correction_cli.sh` gains idempotent-replay, deterministic
  write-back, revision-floor, and malformed-state checks; public contract
  `corrections-state` (`rh-corrections-state/1`, additive) is registered
  (33 contracts total).
- M06 durable policy exceptions: `rh_cli policy --state <file>` now loads
  and rewrites an `rh-policy-state/1` document (`src/rh_policy_parse.elisa`
  gains `rh_policy_state_parse`/`rh_policy_state_emit`), so an approved
  waiver survives process restarts and an expired one is re-evaluated, not
  silently renewed. A persisted row is dropped when the same `(rule_id,
  subject_id, digest)` is declared inline in the current document (current
  intent wins over stale state); corrupt/wrong-schema state fails closed
  (exit 4). Write-back is byte-stable. `tests/test_policy_cli.sh` gains
  cross-run persistence, deterministic write-back, expiry/revoke denials,
  inline-over-state precedence, and malformed-state exit-4 checks; public
  contract `policy-state` (`rh-policy-state/1`, additive) is registered.
- M08 inventory unknown-fields (lossless reporting): `src/rh_inventory.elisa`
  gains `rh_bom_unknown_keys`, and the CycloneDX result now carries
  `unknown_top_keys` (top-level fields not modeled are **counted**, not
  silently dropped) — matching what SPDX already reported. Only true
  object keys are counted (odd-position members), so string *values* are
  never mistaken for unknown fields. `rh_cli inventory --format cyclonedx`
  emits the count in `rh-inventory/1` `counts`; `src/test_package.elisa`
  and `tests/test_inventory_cli.sh` cover zero-unknown and a two-unknown
  document. Suite remains 47 harnesses.
- M09 wave-B metric: `concentration.change_gini` (v1.0.0, `implemented`).
  `src/rh_metrics.elisa` gains `rh_gini` (exact reduced rational; S =
  sum over unordered nonzero-actor pairs of |x_j - x_k|, G = S/(n*total);
  fewer than two nonzero actors is refused so the caller reports
  `not_applicable`, never 0; overflow is a bounded false). Published via
  `rh_cli continuity` in `continuity-metrics.json` alongside HHI /
  effective-count / absence-factor / top1-share so no single number implies
  a verdict (R030). Registered in `rh_registry.elisa` (now 18 entries, 17
  implemented, denominator rule 4); added
  `metrics/definitions/concentration_change_gini.json`; regenerated the
  profile. Oracle vectors: [9,3] → 1/4; [25,25,25,25] → 0/1; [4,2,1,0] →
  2/7; n<2 refused (`src/test_continuity.elisa`); CLI asserts 3/20 on the
  4-actor fixture (`tests/test_continuity_cli.sh`). Catalog now 21
  definitions = 17 implemented, 3 prototype, 1 planned. Suite remains 47
  harnesses.
- M02/M04 R029 execution path (coverage change vs activity change):
  `src/rh_continuity.elisa` gains `rh_coverage_basis` (full / windowed /
  shallow; shallow wins so a depth-limited clone is never treated as
  complete), `rh_coverage_basis_label`, and `rh_coverage_vs_activity`
  (observed-activity / observed-quiet / coverage-limited). The
  `rh-continuity/1` report now carries a `coverage` block with the basis
  label and `activity_change_claims_supported` (true only on a full basis)
  plus an explicit note that a coverage-limited basis means absence is not
  activity evidence. `rh_cli continuity` derives the basis from the
  manifest's `full-history`/shallow flags. `src/test_continuity.elisa`
  covers the classifier, the coverage-vs-activity truth, and the emitted
  basis/claims; `tests/test_continuity_cli.sh` asserts full vs windowed
  bases on real scans. R029 evidence extended; suite remains 47 harnesses.
- M11 anomaly-analysis adapter (R024): `src/rh_experimental.elisa` gains a
  concrete first-level cadence-deviation surface —
  `rh_exp_cadence_outcome` (quiet/active/not-observable per window),
  `rh_exp_cadence_baseline` (exact `sum/baseline` rational over the
  caller-declared leading windows, `not_applicable` when none are
  observable), and `rh_exp_cadence_findings` (per-window indices at or
  below a declared floor after the baseline; unobservable windows are
  excluded, never coerced to zero). It emits concrete per-window findings,
  never an aggregated suspicion score, never names a cause, and is
  explicitly not a maliciousness/health judgement. Registered as the
  `anomaly.cadence_deviation_windows` experimental definition (wave G,
  opt-in, costed, limited); `src/test_m11.elisa` and `tests/test_m11.sh`
  cover outcomes/baseline/findings/denominator and the definition gates.
  Catalog now 20 definitions = 16 implemented, 3 prototype, 1 planned.
  Suite remains 47 harnesses.
- M09 wave-B metric: `concentration.change_top1_share` (v1.0.0,
  `implemented`). `rh_continuity.elisa` gains `rh_top1_share` (exact
  rational: largest single actor's share of qualifying commit events;
  zero-total is `not_applicable`, never 0), published in
  `continuity-metrics.json` via `rh_cli continuity` alongside HHI /
  effective-count / absence-factor so no single number implies a verdict
  (R030). Registered in `rh_registry.elisa` (now 17 entries, 16
  implemented) with denominator rule 4; added
  `metrics/definitions/concentration_change_top1_share.json`; regenerated
  `metrics/profiles/per-project.json`. Updated the oracle counts
  (`src/test_oracles.elisa`), the registry-mirror gate (`tests/test_m00.sh`
  now 19 definitions / 16 implemented) and `tests/test_continuity_cli.sh`
  (2/5 for the 4-actor fixture; 9/12 for the [9,3] oracle). STATUS catalog
  table updated; the catalog is now 19 definitions = 16 implemented, 344
  not yet. Suite remains 47 harnesses.
- M08 fourth-ecosystem dependency parser (Go modules): `src/rh_package.elisa`
  gains `rh_go_parse` for `go.mod`. Declared requirements are never silently
  treated as resolved edges (R009): only a `require <module/path> vX.Y.Z`
  directive whose version is a plain release (`v` MAJOR.MINOR.PATCH) becomes
  a package node and a root edge. Pseudo-versions and `+incompatible` stay
  `missing` unresolved entries with their original text; `replace`/`exclude`/
  `retract` directives stay `context` unresolved (a rewrite target is not a
  registry version and must never be treated as the resolved edge). Both the
  single-line `require` form and the parenthesized `require (...)` block are
  handled, `// indirect` is a comment (preserved only in the recorded
  requirement text), and the root identity is the `module` directive path.
  Module paths are byte-exact. Added `RH_ECO_GO`, the `Go` OSV ecosystem id,
  byte-exact `rh_go_name_eq`, and `go` entries in `rh_deps_eco`/
  `rh_deps_spec`/`rh_graph_write_json`. `rh_cli deps` now reads `go.mod` and
  emits `deps-go-graph.json`; metrics gain a `go` ecosystem component. Added
  `fixtures/packages/go.mod.txt` and `fixtures/packages/go-graph.golden.json`;
  `src/test_package.elisa`, `tests/test_m03.sh` and `tests/test_deps_cli.sh`
  cover the lane. `schemas/dep-graph` gains the `go` enum value. The
  dependency lane now spans four ecosystems (Cargo, npm, PyPI, Go). Suite
  remains 47 harnesses.
- M08 native non-Git adapter (Fossil): `src/rh_vcs_fossil.elisa` parses the
  documented `fossil timeline -F "%H|%a|%d|%b|%p|%t|%c"` placeholder format
  with a bounded line parser (default cap 20000). The check-in artifact id
  is a native Fossil hash (SHA-1 40 or SHA-256 64 lowercase hex; anything
  else is rejected, not guessed); the author login is raw evidence; `%p`
  phase tokens and `%t` tags are counted, not interpreted; ISO8601 dates
  (with optional fractional seconds / `Z` / `±HH:MM`) are converted to UTC
  via `rh_days_from_civil`, and a bad date leaves `has_date:false`/`utc:-1`
  rather than fabricating a time. `rh_cli vcs --format fossil` emits
  `rh-vcs/1`; `connectors/manifests/fossil.json` records the capability
  matrix. Added `fixtures/vcs/fossil-timeline.txt`; `src/test_m08.elisa` and
  `tests/test_vcs_cli.sh` cover parse, hash/date validation, reject counts,
  and fail-closed empty input. M08 now has three native non-Git adapters
  (Mercurial, Subversion, Fossil). Suite remains 47 harnesses.
- M08 native non-Git adapter (Subversion): `src/rh_vcs_svn.elisa` parses
  `svn log --xml -v` with a bounded direct linear byte parser (no general
  XML DOM; predefined + numeric entities decoded; cap default 20000;
  malformed doc fails closed). A revision is preserved as a
  repository-global number and never converted to a Git hash or treated as
  a per-project change; the author string is raw evidence; path actions
  (A/M/D/R) are counted per revision, unknown actions counted as `other`;
  entries without a valid revision are rejected, not guessed.
  `rh_cli vcs --format svn` emits `rh-vcs/1` alongside `hg`/`patch`, and
  `connectors/manifests/subversion.json` records the capability matrix.
  Added `fixtures/vcs/svn-log.xml`; `src/test_m08.elisa` and
  `tests/test_vcs_cli.sh` cover parse, entity decoding, action counts,
  fail-closed non-log/unterminated input, and the negatives. R025 now has
  a second (non-Git) native adapter. Suite remains 47 harnesses.
- M08 third-ecosystem dependency parser (PyPI): `src/rh_package.elisa` gains
  `rh_pypi_parse` for a PEP 508 subset of `requirements.txt`. Only an exact
  `==`/`===` pin with no extras, environment marker or direct URL becomes a
  package node and a root edge; plain ranges become `missing` unresolved
  entries, while extras (`pkg[extra]`), markers (`pkg; python_version<...`),
  direct URLs (`git+https://...`) and pip options (`-r`/`-e`) stay `context`
  unresolved with their original text preserved. Added `RH_ECO_PYPI`, PEP 503
  name equality (`rh_pypi_name_eq`: case-insensitive, `-`/`_`/`.` equivalent)
  and the `PyPI` OSV ecosystem id. `rh_cli deps` now reads `requirements.txt`
  alongside `Cargo.lock` and `package-lock.json` and emits
  `deps-pypi-graph.json`; `rh_deps_metrics_emit` gains the `pypi` ecosystem
  component. Added `fixtures/packages/python-requirements.txt` and
  `fixtures/packages/python-graph.golden.json`; `test_package` and
  `tests/test_deps_cli.sh` cover the new lane (root + 3 pins, 3 edges, 5
  unresolved, extras not resolved, unsupported=1). `schemas/dep-graph`
  gains the `pypi` enum value and a `str_or_null` type for the root node's
  null version; `tools/schema-check.sh` supports `str_or_null`. The scan
  manifest probe also recognizes `requirements.txt`. Suite remains 47
  harnesses.
- M05-06 per-metric intrinsic join product path (R011): `rh_cli downstream
  --intrinsics <file>` accepts an `rh-intrinsics/1` document (metric keys +
  a presence bitmask per dependent node) and joins it to the dependent set
  via `rh_downstream_coverage`, emitting a covered denominator per metric
  in the `rh-downstream/1` report (`intrinsics.covered`). Coverage is never
  collapsed to one number and intrinsics stay independent of downstream
  inputs (anti-circularity). Malformed/missing intrinsics fail closed
  (exit 4). `tests/test_downstream_cli.sh` proves the per-metric
  denominators (3/1/1 over a 3-dependent set) and the negatives. With R012,
  `ops/requirements-index.json` is now 30 implemented, 0 partial.
- M05-04 mirror/family dedup product path (R012): `rh_cli downstream
  --mirror a:b` (repeatable) builds ACCEPTED `RhAssertion`s from
  `<dep-graph/1>` node ids and feeds them to `rh_family_dedup`, so direct,
  transitive and scenario lists collapse to one member per accepted family
  while forks stay distinct. The `rh-downstream/1` report gains a
  `grouping` block (`accepted_assertions`, `family_dedup`) and a note that
  grouping requires accepted assertions. `src/rh_downstream_report.elisa`
  gains `rh_ds_parse_pair` (strict `a:b` parser, fails closed) and
  `rh_downstream_report` now takes an assertion list; only the CLI calls it.
  `tests/test_downstream_cli.sh` covers mirror collapse (2/3 → one family),
  fork distinctness without an assertion, and malformed `--mirror`
  negatives.
- M08 forge breadth (Gitea/Forgejo): `src/rh_forge.elisa` gains
  `rh_gitea_repo_canonical`, shared by both connectors but parameterized by
  the connector label so `source` and the `native_id` prefix stay
  connector-specific. `rh_cli forge normalize --connector gitea|forgejo`
  now reproduces checked-in `rh-canonical-repo/1` goldens byte-for-byte,
  alongside GitHub and GitLab. Gitea/Forgejo expose `updated_at` but no
  `pushed_at`; that field is emitted as `null` (unknown), never guessed.
  Added `fixtures/connectors/gitea-repo.json` /
  `fixtures/connectors/forgejo-project.json` plus goldens (validated by the
  `canonical-repo` schema target glob and `tests/test_m02.sh`), and
  `tests/test_forge_cli.sh` now covers four connections including
  gitea/forgejo distinctness. No new contract: the `canonical-repo`
  contract already covers the shape. Suite remains 47 harnesses.
- M02-03 job-lease execution path: `src/rh_lease_report.elisa` +
  `rh_cli store lease --root <dir> --job <name> --input <file> --out <file>`
  apply a claim/heartbeat/release/status sequence to a real
  `<root>/leases/<job>.lease` (+ append-only attempt `.log`) and enforce
  fencing: a live lease is held (−1), an expired one is reclaimable with a
  new token, a terminal phase refuses further claims (−2), and a stale
  worker (wrong token) cannot heartbeat or release/publish. Malformed
  schema/phase/shape fails closed (exit 4). `tests/test_lease_cli.sh` covers
  claim/held/release/terminal, expiry reclaim, stale-worker fencing,
  determinism on a fresh store, and the negatives. Registered as the
  `store-lease-result` public contract; R022 gains execution-path evidence.
  Suite is now 47 harnesses.
- M06-08 durable notification state: `rh_cli notify --state <file>` loads a
  prior `rh-notify-state/1` document and writes the updated rows back, so
  dedup/cooldown, acknowledgement and resolution survive across separate
  runs (a missing state file is a fresh state; a corrupt one fails closed
  with exit 4). `src/rh_notify_report.elisa` gains
  `rh_notify_report_state`/`rh_notify_parse_state`/`rh_notify_emit_state`;
  the old `rh_notify_report` is a thin wrapper for the stateless path.
  `tests/test_notify_cli.sh` proves the cross-run sequence
  (new → cooldown → ack → acknowledged → resolve → resolved) and the
  corrupt-state negative. Registered as the `notify-state` public contract.
  This is caller-managed durable state, not yet the M02 store wiring.
- M09 catalog expansion (concentration family): three new metric definitions
  are now `implemented` and published on the real `rh_cli continuity` path in
  `continuity-metrics.json` — `concentration.change_hhi` (exact reduced
  rational HHI over commit events), `concentration.change_effective_actor_count`
  (exact reciprocal of HHI), and `concentration.change_absence_factor_50`
  (top-actor count reaching 50% of commit events). An empty/zero denominator
  is `not_applicable`, never 0, and the raw numerator/denominator components
  are emitted alongside. The registry, oracles (count 16, implemented 15),
  profile (15 reachable), and STATUS are updated. `tests/test_continuity_cli.sh`
  now asserts the exact values for the existing scan and the plan's `[9,3]`
  oracle on a real two-author repo (HHI 5/8, effective 8/5, 50% → 1).
  Catalog state: 18 definitions = 15 implemented, 2 prototype, 1 planned
  (345 of 360 not yet). R015 gains execution-path evidence. Suite stays 46
  harnesses (the continuity CLI harness was extended, not added).
- M06-03 accessible server-rendered UI execution path: `src/rh_render.elisa`
  renders an M01 `report.json` into a self-contained, keyboard/screen-reader
  friendly HTML page with scoped metric and capabilities tables (the text
  alternative to any chart) and the mandatory caveats (raw authors are not
  maintainers; unknown is not zero; there is no universal score; reviews/
  permissions/traffic/dependents are not collected). `rh_cli render --report
  <report.json> --out <file.html>` exposes it offline, and `rh_cli serve`
  answers `/_report.html` by rendering `report.json` at request time (no
  static fixture). Every dynamic string is HTML-escaped, so a hostile
  repository name cannot inject markup; the page computes nothing and adds
  no verdict. `tests/test_render_cli.sh` covers the structure, the escaping
  of a hostile source name, determinism, and negatives; the opt-in live HTTP
  block now also fetches `/_report.html`. Registered as the `report-html`
  public contract (`repo-health-report-html/1`); R022 gains execution-path
  evidence. Suite is now 46 harnesses.
- M11 experimental isolation execution path (R024): `src/rh_experimental_report.elisa`
  + `rh_cli experimental --input <file> --out <file>` turn
  `rh-experimental-input/1` into `rh-experimental-result/1`. Each spec is
  gated (opt-in + wave G + a cost class + at least one explicit limit) with a
  reason (`not-opt-in`/`wrong-wave`/`no-cost`/`no-limits`) when rejected; the
  sample `discontinuity.no_qualifying_release_in_horizon` metric reports an
  observable horizon outcome where a censored subject is excluded from the
  denominator, zero-observable is `not_applicable` (value `null`), and the
  mandatory label ("observable horizon outcome, not a reliability or
  abandonment label") travels with the result. With no admissible spec the
  metric is `unsupported`. Malformed schema/cost/shape fails closed (exit 4).
  `tests/test_experimental_cli.sh` covers admissibility reasons, the
  aggregate, the not_applicable/unsupported branches, determinism, and
  negatives. Registered as the `experimental-result` public contract; R024
  gains execution-path evidence. With this, every `rh_*` module is reachable
  from the CLI. Suite is now 45 harnesses.
- R013 declared-roles execution path: `src/rh_roles_report.elisa` +
  `rh_cli roles --input <file> --out <file>` turn `rh-roles-input/1`
  time-scoped role/permission declarations and queries into
  `rh-roles-result/1`. A revoked or not-yet-effective declaration is
  inactive at that time; an unrecognized role string stays `unknown`
  (never guessed at maintainer); permissions are checked exactly against
  the declared bit; declaration sources (provider/file/operator) are
  tallied; and the report states declared roles are separate from observed
  actions. Malformed schema/source/shape fails closed (exit 4).
  `tests/test_roles_cli.sh` covers the queries, permissions, tally,
  determinism, and negatives. Registered as the `roles-result` public
  contract; R013 gains execution-path evidence. Suite is now 44 harnesses.
- M07-07 publication suppression execution path: `src/rh_privacy_report.elisa`
  + `rh_cli privacy --input <file> --out <file>` turn `rh-privacy-input/1`
  aggregate cells into `rh-privacy-result/1`. A cell publishes only when
  every contributing subject is public AND the disclosure threshold is met;
  an unknown-visibility member withholds before a private one; a small
  public cell suppresses; authorized members join the total but never make a
  sub-threshold public cell publishable. Every decision carries the
  `rh_privacy` explanation verbatim, including "suppression is not
  anonymization", and the report states no formal-anonymity claim is made
  without a stated method. Malformed schema/shape/missing-id fails closed.
  `tests/test_privacy_cli.sh` covers the decisions, the unknown-before-private
  precedence, the caveat, determinism, and the negatives. Registered as the
  `privacy-result` public contract; S007 gains execution-path evidence.
  Also renamed `rh_privacy`'s visibility constants to `RH_PV_VIS_*` to avoid
  a collision with `rh_graph`'s `RH_VIS_PUBLIC`/`RH_VIS_PRIVATE` once both
  are in the CLI unit. Suite is now 43 harnesses.
- M07-11/M07-12 ops execution paths: `src/rh_ops_report.elisa` +
  `rh_cli ops monitor|quota`. `ops monitor --input <file> --out <file>`
  emits `rh-monitor-result/1` where service health and project health are
  **separate series** (a source outage moves service counters, not project
  activity/unknown) and a rate with no denominator is `null` (unknown, not
  0), plus a deterministic `rh_service_*`/`rh_project_*` exposition.
  `ops quota --input <file> --out <file>` emits `rh-quota-result/1` running
  a per-host token bucket with exponential capped backoff (10/20/40/…),
  operator stop, and cancel refund. Malformed input fails closed.
  `tests/test_ops_cli.sh` covers the monitor series, the no-denominator
  null, the quota state machine, the backoff cap, determinism, and the
  negatives. Registered as the `monitor-result` and `quota-result` public
  contracts; R029/R022 gain execution-path evidence. Suite is now 42
  harnesses.
- M08 PEP 440 version-semantics execution path: `src/rh_pep440_report.elisa`
  + `rh_cli pep440 --input <file> --out <file>` turn an `rh-pep440-input/1`
  list into `rh-pep440-result/1` with per-version details (epoch, release
  segments, a/b/rc pre with dev, post, local presence) and an ascending
  order over VALID versions only. Python ordering is honoured, not SemVer:
  `1.0a1.dev1 < 1.0a1 < 1.0b1 < 1.0rc1 < 1.0 < 1.0+local < 1.0.post1 <
  1.0.1 < 2.0 < 1!0.1`. Invalid versions are reported `valid:false` and are
  never compared or sorted (their order would be meaningless); internal
  sentinels (absent dev/post) are emitted as `null`, not raw sentinel
  values. Malformed schema/shape fails closed. `tests/test_pep440_cli.sh`
  covers the ordering, validity, determinism, and negatives. Registered as
  the `pep440-result` public contract. Suite is now 41 harnesses.
- M03-05 registry enrichment execution path: `src/rh_registry_meta_report.elisa`
  + `rh_cli registry-meta --input <file> --out <file>` turn an
  `rh-registry-meta/1` document into `rh-registry-meta-result/1`. The
  honest states are preserved: a yanked version is retained (not deleted),
  an absent yank field is `null` (unknown, never false), numeric and ISO
  published times are kept as-is (unknown stays `null`), a declared
  repository link is labelled an assertion (not identity), and
  declared/optional/dev dependency counts are exact (declared, not resolved
  edges). Malformed shape/JSON fails closed (exit 4).
  `tests/test_registry_meta_cli.sh` covers the counts, the yank tri-state,
  the ISO-vs-epoch date handling, determinism, and the negatives.
  Registered as the `registry-meta-result` public contract; R008 gains
  execution-path evidence. Suite is now 40 harnesses.
- M08 release-only source execution path: `src/rh_release_feed_report.elisa`
  + `rh_cli release-feed --input <file> --out <file>` turn an
  `rh-release-feed-input/1` feed into `rh-release-feed-result/1`. Published
  time (valid time) and collector first-seen time (known time) are kept
  separate; a missing published time stays `null` (unknown), never replaced
  by first-seen; asset counts and how many carry a valid digest are exact;
  an entry with no tag is rejected rather than guessed; and the source
  declares `history_supported`/`identity_supported` both false (no history
  or author identity is derived — a tag is a label, not a release event).
  `tests/test_release_feed_cli.sh` covers the fields, re-observation with a
  distinct first-seen, rejected-not-guessed, determinism, and the
  fail-closed negatives. Registered as the `release-feed-result` public
  contract; R017 gains execution-path evidence. Suite is now 39 harnesses.
- M04-03 reversible identity-link execution path (R016):
  `src/rh_identity_report.elisa` + `rh_cli identity --input <file> --out
  <file>` process an `rh-identity-input/1` ledger into
  `rh-identity-result/1` with the identity revision, clusters derived only
  from ACCEPTED links, a per-actor cluster map, and actor-kind
  stratification. Rejected/proposed links change nothing; revoking an
  accepted link recomputes clusters and changes the revision with no raw
  record rewritten (reversibility). Malformed state/kind/actor-range fails
  closed (exit 4). `tests/test_identity_cli.sh` covers the cluster/revision
  values, revoke recompute, no-op proposed/rejected ledgers, determinism,
  and the negatives. Registered as the `identity-result` public contract;
  R016 gains execution-path evidence. Suite is now 38 harnesses.
- M06-01 query execution path: `src/rh_query_report.elisa` +
  `rh_cli query --input <file> --out <file>` process an
  `rh-query-input/1` request into `rh-query-result/1`. It provides cursor
  pagination over an ascending id list (a replayed cursor is idempotent and
  `next_cursor` is null exactly when complete), a per-capability scan-status
  breakdown that localizes a failed fetch to its capability rather than the
  project, and a bounded-job lease sequence (claim/renew/finish/budget) with
  fencing tokens — a stale token cannot renew or finish. Malformed requests
  (unknown kind, bad state/phase, non-integer ids) fail closed (exit 4).
  `tests/test_query_cli.sh` covers the pages/cursors, scan-status tally, the
  lease state machine, determinism, and fail-closed negatives. Registered as
  the `query-result` public contract; R022 gains execution-path evidence.
  Suite is now 37 harnesses.
- M06-08 notification execution path: `src/rh_notify_report.elisa` +
  `rh_cli notify --input <file> --out <file>` process an
  `rh-notify-input/1` event stream (`notify`/`ack`/`resolve`) into
  `rh-notify-result/1`. The non-negotiable rule is enforced on the real
  path: an upstream maintainer destination is refused unless explicitly
  subscribed, and a refusal records nothing — so it cannot start a phantom
  cooldown that would silence a subscriber's first real alert. Dedup/cooldown
  are keyed on (rule, subject, artifact digest), a changed digest is a new
  key, source outages suppress coverage-derived alerts, and acknowledged/
  resolved keys stay quiet. `tests/test_notify_cli.sh` proves the full
  decision sequence and exact counts, the no-phantom-cooldown case, allowed
  subscribed-upstream, ack on an unknown key, determinism, and fail-closed
  malformed inputs. Registered as the `notify-result` public contract; R022
  gains execution-path evidence. Suite is now 36 harnesses.
- M08 native-VCS / non-PR execution path (R025): `src/rh_vcs_report.elisa`
  emits `rh-vcs/1` and `rh-patch/1`, and `rh_cli vcs --format hg|patch
  --input <file> --out <file>` is the real path. `hg` parses `hg log -Tjson`
  preserving the native 40-hex node id (a 64-hex SHA-256 shape is rejected),
  keeping `rev` repository-local (never identity) and the author string raw
  (not an account), counting tags without calling them releases, and
  counting malformed entries as rejects rather than guessing. `patch` splits
  an mbox-like series at `From ` lines, parses each `Subject:` for
  `[PATCH vN i/total]`, scans body trailers, and collapses N revisions of one
  patch base into ONE logical change (a 3x-revised series is not three
  changes); `Fixes:` is a claim, not confirmed reachability; duplicate
  approvers are deduped; a non-patch message is never forced into a series.
  Wrong shape/format fails closed (exit 4) and an unknown `--format` exits 3.
  `tests/test_vcs_cli.sh` covers both lanes, the reject-not-guess rule,
  series collapse, approver dedup, determinism, and the negatives. Registered
  as the `vcs-observation` and `patch-report` public contracts; R025 gains
  execution-path evidence. Suite is now 35 harnesses.
- M03-07/M08 inventory interchange execution path: `src/rh_inventory_report.elisa`
  emits `rh-inventory/1` and `rh_cli inventory --format cyclonedx|spdx
  --input <file> --out <file>` is the real path. It reports the declared
  spec version, exact component/package counts, per-component
  name/version/purl and `digest_known` (only a valid SHA-256 counts), and
  for SPDX the `unknown_top_keys` count. A declared spec version outside
  the supported set is reported `unsupported` with the reason and exits 3 —
  never interpreted; a document of the wrong format fails closed (exit 4);
  an unknown `--format` exits 3. `valid != complete` is stated in every
  report. `tests/test_inventory_cli.sh` covers CycloneDX 1.5 and SPDX-2.3,
  determinism, the unsupported-version branch, and the negatives. While
  wiring it, fixed a span bug: the spec-version span indexes the decoded
  text buffer, so it is now copied into the component pool before emission.
  Registered as the `inventory-observation` public contract; R027 gains
  execution-path evidence. Suite is now 34 harnesses.
- M02 forge normalization execution path: `rh_cli forge normalize
  --connector github|gitlab --input <file> --out <file> [--fetched-at N]`
  turns a captured forge payload into `rh-canonical-repo/1`. At a pinned
  collection time it reproduces the checked-in GitHub and GitLab goldens
  byte-for-byte, proving two genuinely different forge payload shapes on a
  real path (beta: "≥2 forge implementations"); the output is deterministic
  and connector-distinct. An unknown connector with no normalizer
  (forgejo/gitea/generic-git) is rejected (exit 3) rather than guessed, and
  a payload that does not match the connector shape fails closed (exit 4).
  `tests/test_forge_cli.sh` covers all of it. R006 gains execution-path
  evidence. Also renamed the `nodes` parameter of `rh_graph.rh_family_dedup`
  to `members`: including `rh_forge` (which has an `rh_get_str_span` with a
  `nodes: darray[RhJsonNode]` parameter) into the CLI unit triggered a
  stage1 type-inference quirk that mis-typed that parameter. Suite is now 33
  harnesses.
- M02 store + M07 ops execution paths: `rh_cli store put --root <dir>
  --file <path>` (idempotent for identical bytes; refuses to overwrite a
  different blob under the same digest) and `rh_cli store verify --root
  <dir> --name <hex>` (recomputes the digest; missing/corrupt evidence
  exits 5 and blocks publication). `rh_cli ops backup|verify|restore`
  wraps the M07-10 backup/restore drill: canonical `rh-backup/1` manifest,
  a verify that counts verified/missing/corrupt **separately**, and a
  restore that copies only digest-verified objects. Fixed a real bug found
  while wiring: `rh_backup_verify` documented a missing-object count but
  was counting missing objects as corrupt; it now checks file existence
  first. `tests/test_store_cli.sh` covers put/verify, a clean manifest,
  restore-only-verified (a corrupt object is skipped), the missing-vs-corrupt
  distinction, and fail-closed negatives. R022 gains execution-path
  evidence. Suite is now 32 harnesses.
- M06 correction execution path: `src/rh_correction_report.elisa` parses a
  versioned `rh-corrections/1` document (corrections + derived results +
  replay inputs) and applies it in order; `rh_cli correct --corrections
  <file> --out <dir>` writes `rh-corrections-result/1`. Accepted
  corrections advance the revision and supersede only the target subject's
  older derived results — counted once even across multiple accepted
  corrections — while rejected/open corrections change nothing; replay
  recomputes from raw inputs the path never rewrites; unknown
  kind/state/combine/schema fails closed (exit 4).
  `tests/test_correction_cli.sh` proves the accepted/rejected/open flow,
  the no-double-count rule, subject isolation, replay add/subtract/identity
  values, the rejected-only no-op, and the malformed-input negatives.
  Registered as the `corrections-result` public contract; R028 gains
  execution-path evidence. Suite is now 31 harnesses.
- M06 policy execution path: `src/rh_policy_parse.elisa` parses a
  versioned `rh-policy/1` document (rules + exceptions) and an
  `rh-policy-input/1` observation document, and aligns inputs to rules by
  id so a rule with no supplied input becomes `unavailable` -> UNKNOWN.
  `rh_cli policy --policy <file> --input <file> --out <dir>` writes
  `rh-policy-result/1` with the four-valued decision, fired/excepted/
  missing rule ids, a structured explanation, and the
  policy/context/artifact/time binding digests. Unknown schema, operator,
  status, or a non-positive threshold denominator fails closed (exit 4) —
  never a default allow. `tests/test_policy_cli.sh` proves observed
  violation -> deny, partial -> unknown, missing input -> unknown, deny
  beats unknown, approved+unexpired digest-bound exceptions authorize
  while expired ones or a changed artifact digest do not (TOCTOU), prose
  in the input cannot flip a decision, and malformed inputs fail closed.
  Registered as the `policy-result` public contract; R020/R021 gain
  execution-path evidence. Suite is now 30 harnesses.
- M05 downstream execution path: `src/rh_downstream_report.elisa` parses
  an `rh-dep-graph/1` document and emits `rh-downstream/1`; `rh_cli
  downstream --graph <dep-graph.json> --subject <id> --out <dir>
  [--max-nodes N] [--max-depth D] [--unavailable <id>] [--private <id>]...`
  is the real path. It applies a labeled public projection (private nodes
  are excluded and never enqueued — S007/F030), returns direct + bounded
  transitive dependents, an SCC count, an optional simulated-unavailability
  scenario, and an explicit `truncated` flag with the reminder that a
  truncated result is NOT a total and that dependents do not feed back into
  intrinsic metrics. `tests/test_downstream_cli.sh` proves diamond
  direct=2/transitive=3, cycle termination with subject exclusion, budget
  truncation, private exclusion, scenario presence, an end-to-end `deps`
  graph, and fail-closed negatives (missing subject → 3, malformed/missing
  graph → 4). Registered as the `downstream-report` public contract; R010
  gains the execution-path evidence. While wiring it, the requirements
  index was re-audited against its own rule ("implemented = contract + real
  path + test"): R011 (per-metric downstream coverage join) and R012
  (family dedup) are test-backed but have no product surface yet, so both
  are now `partial` with explicit gaps, and the stale STATUS count
  (27 implemented / 3 partial) was corrected to 28 / 2. Suite is now 29
  harnesses.
- M03 dependency-graph execution path: `rh_cli deps --repo <dir> --out
  <dir> [--osv <file>]` reads a local project's `Cargo.lock` and/or
  `package.json` + `package-lock.json`, resolves the version-aware graph,
  and writes one `rh-dep-graph/1` report per ecosystem plus
  `rh-deps-metrics/1`. Requirements that do not resolve stay explicit
  unresolved nodes with reasons (`missing`/`ambiguous`/`context`) — never
  guessed edges (R009); a malformed lockfile fails closed with **no
  partial graph**. The planned metric `dependencies.unsupported_range_count`
  is now `implemented` against a **declared** supported syntax subset
  (semver operators/identifiers only): protocol/alias/workspace/path forms
  and dist-tags are unsupported-by-declaration, explicitly distinct from a
  missing dependency (`rh_req_range_supported`). Offline advisories come
  only from a provided `--osv` file and are never fabricated; an advisory
  present but not reachable from the scan root yields an empty witness
  (presence != affected reachability, R019). Tests:
  `src/test_package.elisa` (classifier oracles including alias/workspace/
  path/git/dist-tag rejects and diamond zero-counts) and
  `tests/test_deps_cli.sh` (both ecosystems, exact node/edge/unresolved
  counts, exact unsupported count of 4, empty-witness case, no-manifest and
  malformed-lock negatives). The format is registered as the `deps-metrics`
  public contract. Catalog: 12 implemented / 2 prototype / 1 planned of 15
  (348 of 360 not yet). Suite is now 28 harnesses.
- M04 continuity execution path: `src/rh_continuity_scan.elisa` parses the
  pinned `evidence/git-log.bin` into raw project-local author-identity
  events (actor ids by first appearance; no cross-source or name/domain
  merge) and computes retention with the plan's censoring rule.
  `rh_cli continuity --bundle <manifest> --out <dir>` writes
  `continuity.json` (`rh-continuity/1`) and publishes
  `persistence.retained_90d` as a real metric observation in
  `continuity-metrics.json` (`rh-continuity-metrics/1`). Windowed or
  shallow scans cannot establish first observation, so retention is
  `unsupported` there — never a misleading rate. The metric is now
  `implemented` in the catalog (11 reachable / 4 not available; the
  definition keeps its admission template). Tests:
  `src/test_continuity_scan.elisa` (hand-computed actor dedup, instants,
  1/3 retention, censoring, malformed-record skip) and
  `tests/test_continuity_cli.sh` (real scan → continuity, exact ratio,
  windowed `unsupported` branch, fail-closed missing bundle, and a check
  that no raw author email leaks into published output). The
  `rh-continuity-metrics/1` format is a registered public contract; R014
  and R022 gain the new execution-path evidence. Suite is now 27 harnesses.
- M07-04 release signing: `src/rh_sha256.elisa` implements SHA-256
  (FIPS 180-4) and HMAC-SHA256 (RFC 2104). Correctness is pinned to
  published vectors in `src/test_m07_sha.elisa` / `tests/test_m07_sha.sh`
  (empty, `abc`, 448-bit multi-block, RFC 4231 cases 1/2/6, plus
  wrong-key/wrong-message/tampered-signature negatives). `rh_cli sign|
  verify` emits/checks a `rh-release-signature/1` object over the release
  packet; `tools/release-packet.sh` signs only when `RH_SIGNING_KEY_FILE`
  names a raw key held outside the tree (`.gitignore` excludes `*.rhkey`
  and `ops/keys/`). Verification proves subject integrity and possession
  of the shared key — symmetric, not a public-key signature, and never a
  code-safety claim (S011). The signature format is registered as a public
  contract; suite is now 26 harnesses.
- Fixed a stale M07 status note that still listed M07-06/07/08/09/13 as
  "not yet" after their artifacts had landed; only the independent
  threat-model review and the opt-in pilot remain.
- R013 declared roles vs observed actions: `src/rh_roles.elisa` models
  time-scoped role/permission declarations with a source stratum
  (provider/file/operator), honoring `declared_at`/`revoked_at` and
  returning `unknown` for an unrecognized role string rather than guessing
  maintainer. Declarations never become observed facts. `src/test_m04_roles.elisa`
  covers role parsing (incl. `wizard` staying unknown), active/revoked/
  not-yet-effective time windows, unknown actors, permission bits, and
  source stratification. R013 moves from partial to implemented in the
  requirements index (28 implemented, 2 partial).
- Requirements/safety evidence index: `ops/requirements-index.json` maps
  each R001-R030 and S001-S012 to a file+token, with honest status and a
  `gap` for partial/deferred entries. `tools/requirements-audit.sh` fails
  on a missing file or token; `tests/test_requirements.sh` proves that with
  a negative control. Writing the index immediately exposed four inaccurate
  tokens (R002, R007, R022, S010), which were corrected to real evidence.
  State: 27 requirements implemented, 3 partial (R013, R022, R024), 12
  safety rules. Suite is now 21 harnesses.
- M08 mailing-list trailers: `src/rh_patch.elisa` now parses patch-body
  trailers (`Reviewed-by`, `Acked-by`, `Tested-by`, `Fixes:`, `Link:`)
  into typed spans, trims values, dedupes distinct approvers, rejects
  non-trailer prose and empty values, and never executes or interpolates
  the body. `Fixes:` is explicitly a CLAIM, not confirmed reachability
  (R019), and declared roles stay separate from observed actions (M04-01).
  `src/test_m08.elisa` covers counts, kinds, trimming, approver dedup, and
  rejection; `tests/test_m08.sh` asserts the checks and caveats. This
  closes the trailers gap noted in the earlier M08 scope note.
- S008/S009 audit tags: the mechanisms were already tested but not named,
  so a reader could not map safety rule to evidence. `tests/test_m04.sh`
  now asserts the reversible-merge checks (`id-full-revoke-restores`,
  `id-revision-back-to-1`) for S008, and `tests/test_m05.sh` asserts the
  bitemporal checks (`known-2025-cannot-see-2026-discovery`,
  `known-2026-sees-discovery`, `valid-2024-after-introduction`) for S009.
  Every S001-S012 rule now appears by name in at least one gate. Suite
  stays 20 harnesses.
- S011 certification-claim contract in `src/test_m06.elisa`: a
  signature/attestation/popularity-style claim is not a measurement. The
  policy engine has no such input; the test proves a perfect-looking value
  carried under a non-observed status evaluates to `unknown`, never
  `allow`; a popularity-shaped input is not a deny; a "test passed" claim
  under `not_observed` stays `unknown`; and a completeness-requiring rule
  returns `unknown` for an incomplete inventory. `tests/test_m06.sh` asserts
  the checks are present.
- M06-03 accessible renderer: `tools/render-project.sh` renders a report
  directory to a static HTML page with semantic tables (`<caption>`,
  `scope` headers, declared language). There is no chart or color-only
  encoding, so the table is the primary representation; unknown metrics
  render their status/reason rather than 0, and the page carries no health
  or trust verdict. `tests/test_m06_ui.sh` covers a real repo and an empty
  repo (forcing an unknown metric), asserting structure, unknown-not-zero,
  and language. Honest scope: this is a render of pinned evidence, not a
  live service; the HTTP listener is still pending. Suite is now 20
  harnesses.
- S005 webhook idempotency in `src/test_store.elisa`: the plan's exact
  "3x webhook + reordered updates → correct projection, no inflated
  metrics" case. Two logical deliveries (`x`, `y`) arrive out of order,
  `x` three times and `y` twice; the store must retain exactly two rows and
  index each id once (`wh-exactly-one-each`), proving both duplicate-skip
  and reorder convergence on the real append path. `tests/test_m02.sh`
  asserts the checks are present.
- S007 private-frontier isolation in `src/test_m05.elisa`: a private
  intermediate node must not leak its subtree into a public projection.
  For the chain `5 -> 2(private) -> 4`, a public query of 4 yields zero
  direct and zero transitive dependents, node 5 never enters the frontier,
  and the same chain is fully visible (2 nodes) under the unfiltered
  projection. `tests/test_m05.sh` asserts both checks are present.
- S006 mutation kill in the property layer: `prop_unknown_no_value` asserts
  that only `observed`/`partial`/`stale` may carry a value — every other
  status, including `not_observed`, `unavailable`, `not_applicable`, and
  `unsupported`, must reject one. A mutation that let unknown carry 0 fails
  this. It also pins ratio validity: zero denominator rejects, numerator
  may not exceed the denominator, and zero numerator is allowed. Categories
  are asserted present in `tests/test_properties.sh`.
- S012 resource-limit termination: `tests/test_m07_resource_limits.sh`
  proves bounded termination. A `RH_SCAN_MAX_COMMITS` environment hook
  (parsed in the scanner, lower-only, never removing the 20000 default)
  lets the suite exercise the truncation path with a 12-commit fixture,
  asserting `coverage_state = truncated` and window completeness `partial`;
  the oversized-evidence cap (`RH_MAX_READ`) and the fetch byte/time and
  redirect caps are verified on the real paths. Note: an earlier draft
  built a 21k-commit repo, which took 4m16s; the hook makes the same claim
  in under a second. Suite is now 19 harnesses.
- S010/R030 publication review: `tools/publication-review.sh` scans the
  generated report directory against prohibited patterns (health/trust
  score, trustworthy, safety/certification verdicts, medical/moral
  inference, maintainer-worth verdicts, letter grades/ratings, "all metrics
  available"), while allowing caveat lines that name and deny the forbidden
  language. `tests/test_m07_publication.sh` scans a real repo, asserts the
  output is clean, and injects a verdict line into a copy to prove the
  reviewer rejects it. Local suite is now 18 harnesses.
- M07-09 provider-dependency review: `ops/provider-dependency-review.json`
  records each external feed/tool dependency (`git-cli`, `osv-data`,
  `deps-dev`, `criticality-score`, `ecosyste-ms`, `reproducible-builds`)
  with lifecycle, failure mode, assumption, and rights.
  `tests/test_providers.sh` asserts the review is complete, that retired or
  not-enabled feeds are explicitly not claimed in use (Criticality Score is
  retired and never consumed; no historical dataset is assumed current),
  and that every failure mode states unknown/stale/fail-closed. Local suite
  is now 17 harnesses.
- S003 credential-canary test and S001 exec-canary test in
  `tests/test_m01.sh`. S001 scans a repo carrying config/attribute/hook
  traps (`core.fsmonitor`, `core.pager`, `filter.*.clean`, `diff.*.textconv`,
  `core.hooksPath`, executable `post-checkout`) and fails if any canary file
  appears, proving collection ran no source-controlled command. S003 scans a
  repo whose git credential-store token and userinfo remote URL contain a
  canary and fails if that secret appears anywhere in report, evidence, or
  stdout/stderr — while distinguishing it from a token a project deliberately
  commits as author data (that is history, not a leaked transport credential).
- F004 (missing blobs) surfaced in the report: the scanner now reads
  `extensions.partialClone` (`rh_run_git_partial`) and, for a partial
  clone, reports `blob_metrics: "partial-missing-blobs"` in the JSON
  capabilities and a `blob-derived metrics | partial` row in the Markdown,
  while history metrics stay **observed**. A repo without the marker
  reports `not-derived`. `tests/test_m01.sh` asserts both directions, so
  F004 moves to `covered`: **all 40 golden fixtures are now covered**,
  with `tests/test_fixtures.sh` failing if any fixture regresses to
  partial/planned.
- Process documentation with a doc gate: `docs/GOVERNANCE.md` (metric
  change process naming the tests that enforce it: lint, version-not-rewrite,
  planned-absent-from-registry, reachable==implemented, correction workflow,
  human-review and paywall boundaries), `docs/operations/MIGRATIONS.md`
  (versioned artifacts, rollback = restore + replay, no silent
  reinterpretation, explicit non-guarantees) and `docs/operations/RELEASE.md`
  (release checklist, recovery, roadmap/hidden-score prohibitions).
  `tests/test_docs.sh` checks the documents exist, that every cited
  file/command path resolves, and that no safety/trust verdict language
  appears. Local suite is now 16 harnesses.
- Metric availability profile: `metrics/profiles/per-project.json`, with
  `tools/metric-profile.sh` deriving it from `metrics/definitions` and
  `tests/test_profile.sh` asserting the checked-in copy matches, that the
  reachable set is exactly the `implemented` definitions, and that no
  not-available metric is advertised as reachable. Every definition now
  carries a `status_note` (enforced by `tools/metric-lint.sh`), and the
  profile embeds the per-source availability matrix. Local suite is now 15
  harnesses.
- Public schemas + schema-check: `schemas/` holds six versioned schemas
  (`rh-jsonschema/1` dialect) covering connector manifests, canonical repo
  documents, dependency graphs, CycloneDX, SPDX and registry metadata, each
  declaring the fixture globs it governs. `tools/schema-check.sh` validates
  the real checked-in fixtures independently of generated code;
  `tests/test_schemas.sh` runs it, asserts every schema family is present,
  and includes a negative control proving a manifest missing required
  capability keys is rejected. The local suite is now 14 harnesses.
- M10 benchmark infrastructure: `src/bench_runner.elisa` generates a graph
  deterministically from a seed (seeded LCG), runs reverse traversal and
  concentration over it, and prints a structural FNV digest plus exact
  counts — timing is measured outside the process by `tools/bench.sh`,
  which writes `build/bench-manifest.json`. `tests/test_bench.sh` asserts
  dataset determinism (identical digests across runs) and manifest schema,
  and does not assert timing values because they are machine-specific.
  This is measurement only: no approximate mode, index, or graph-DB
  acceleration is enabled. The local suite is now 13 harnesses.
- Property test layer: `src/test_properties.elisa` +
  `tests/test_properties.sh` add invariants over many inputs, distinct from
  the oracle/unit suites: exact `1/n ≤ HHI ≤ 1` and
  `1 ≤ effective ≤ n` by cross-multiplication; reorder independence of HHI
  and the 50% absence factor; concentration monotonicity (k50 ≤ k80);
  empty ⇒ not_applicable rather than zero; identity accept/revoke
  reversibility with the revision returning to 0; depth-limit monotonic
  reachability (more depth never yields fewer nodes); and public
  projections being a subset of the unfiltered set. The local suite is now
  12 harnesses.
- M08 second inventory format: `src/rh_spdx.elisa` parses SPDX 2.3 JSON
  (declared supported version; another `spdxVersion` is reported
  `unsupported`, never guessed; a document without `spdxVersion` fails
  closed). It extracts package name/versionInfo, purls from `externalRefs`,
  and SHA-256 checksums (only `SHA256` + 64 lowercase hex counts), and it
  **counts unknown top-level keys** rather than dropping them silently —
  lossless awareness, with the same `valid != complete` caveat as
  CycloneDX. `fixtures/inventory/spdx-2.3.json` is the checked-in document;
  `test_package` covers the counts, unsupported-version, and
  missing-version paths, and `tests/test_m03.sh` validates both pinned
  inventory fixtures.
- M07-08 deletion/replayability drill: `rh_store_delete_blob` removes a
  raw evidence object idempotently (deleting an absent blob is success,
  never an error), and `rh_replay_label` classifies a referenced input set
  as `replayable`, `not_replayable`, or `unknown` (empty set) by presence.
  `test_m07` proves the label flips from replayable to not-replayable after
  a deletion, and that derived results are never silently recomputed from
  live data. Digest verification remains a separate check (M07-10).
- M03-05 registry enrichment: `src/rh_registry_meta.elisa` parses captured
  registry version metadata into per-version records (label, yanked flag,
  published time as epoch or raw string, declared source link, declared
  normal/optional/dev dependency counts). Invariants proven in
  `test_package`: a yanked version is retained rather than deleted; an
  absent yank field is unknown (-1), never silently false; a declared
  source link passes through `rh_repo_claim_state` as `unverified` and is
  never identity (F023); declared dependencies are counts, not resolved
  edges (R009). `fixtures/packages/registry-meta.json` is the captured
  document; wrong-shape documents fail closed.
- M03-07 inventory interchange: `src/rh_inventory.elisa` parses CycloneDX
  JSON with a declared supported spec set (1.4/1.5/1.6). An unrecognized
  spec version is reported `unsupported`, never guessed; a non-CycloneDX or
  spec-less document fails closed. Component identity (type/name/version/
  purl) and SHA-256 hashes are extracted; a hash that is not 64 lowercase
  hex is not counted as a known digest; components missing name/version are
  counted invalid and skipped. The module states `valid != complete`.
  `test_package` covers the counts, the unsupported-version path, the
  non-CycloneDX rejection, and the missing-spec rejection;
  `fixtures/inventory/cyclonedx-1.5.json` is the checked-in document.
- M09 catalog governance: `tools/metric-lint.sh` mechanically enforces the
  metric admission template. Every definition must have the base contract
  fields; every non-`implemented` definition must additionally declare
  `inputs`, `params`, `missing_behavior` and `confounders`, and a `ratio`
  output must name its numerator and denominator. Three wave-B/C metrics
  were added as `planned` with the full template
  (`persistence.retained_90d`, `succession.handover_overlap_months`,
  `dependencies.unsupported_range_count`). `tests/test_m00.sh` now verifies
  the runtime registry mirrors exactly the published definitions — a
  `planned` metric must be ABSENT so the system never implies availability —
  and catalog state is 14 definitions (10 implemented, 1 prototype, 3
  planned). None of the planned metrics is computed or published.
- M08 ecosystems lane: `src/rh_pep440.elisa` implements Python/PEP 440
  version parsing and ordering and explicitly does NOT apply SemVer rules.
  Epoch, release segments, `a`/`b`/`rc` pre-releases with `alpha`/`beta`/`c`/
  `pre`/`preview` aliases, post-releases, dev releases and local versions
  are handled; the ordering follows PEP 440's comparison key. Declared
  subset: local versions compare by presence only (public < local; two
  locals of one public version compare equal), and an invalid version has
  `ok=0` and compares as 2 (never ordered). `test_m08` asserts the canonical
  chain `1.0.dev1 < 1.0a1 < 1.0 < 1.0.post1 < 1.0.1`, epoch dominance,
  release zero-padding, the aliases, and the invalid cases.
- M08 release-only adapter: `src/rh_release_feed.elisa` parses a release
  feed (array or `{releases:[...]}`) into releases with their published
  time (valid time), the collector's first-seen time (known time, both
  retained), asset counts, and how many assets carry a digest. It derives
  no history or author identity — `rh_release_feed_history_supported` and
  `rh_release_feed_identity_supported` both return 0 and the manifest marks
  those capabilities `unsupported`; a missing published time stays unknown
  rather than becoming first-seen. Records are keyed by (tag, first-seen)
  via `rh_release_first_seen_for`, so a re-published tag is a new
  observation, not an overwrite. `connectors/manifests/release-feed.json`
  and the source register add the family; `test_m08` covers parse,
  missing-published-unknown, wrong shape, missing-tag rejection, and the
  release cap.
- F033 orphan cleanup: `rh_store_gc` deletes candidate blobs whose names
  are not referenced, leaves referenced objects untouched, and counts
  removals; `rh_names_has` does the membership test across the two caller
  buffers. `test_store` stores one orphan and one referenced blob, runs the
  GC, and verifies the orphan is gone and the referenced blob still
  verifies. Safe retry was already proven, so F033 is now `covered`. Only
  F004 remains partial (no published tree/blob metric to make partial).
- F023/F024 coverage in `src/rh_package.elisa`: `rh_artifact_identity`
  treats the same version label with different observed bytes as a distinct
  artifact (`RH_ART_CHANGED`), missing either side as unknown, and
  `rh_repo_claim_state` keeps a declared repository link `unverified`
  unless reviewed evidence verifies it, with conflicting evidence winning
  over everything (`conflicted`). `test_package` exercises all branches,
  including that unverified/conflicted/unknown are never identity. No
  fixture is `planned` any more: 38 covered / 2 partial (F004, F033).
- F006/F007 coverage: `tests/test_m01.sh` now proves two commits with an
  identical patch but different hashes are distinct revisions and the
  report claims no equivalence; `test_store` proves a force-push
  redelivery dedups to one copy and never deletes the immutable event for a
  now-unreachable revision (append-only retention). Fixture split is now
  36 covered / 2 partial / 2 planned.

### Changed
- Fixture catalog corrected against real test evidence: the M04 fixtures
  A–E are each backed by a named assertion, so F012 (many one-offs + stable
  core → no concern), F014 (review-only maintainer visible), F015 (newcomer
  right-censored) and F017 (handover with explicit overlap) move to
  `covered`. F021 (optional edges excluded from a runtime-context
  projection) was added to `test_m05` and also moves to `covered`. Honest
  split is now 34 covered / 2 partial / 4 planned.

### Added
- M08 native-VCS lane (prototype): `src/rh_vcs_hg.elisa` parses the
  documented `hg log -Tjson` machine format into normalized changes.
  Mercurial `node` ids are preserved verbatim and never treated as Git
  hashes; the integer `rev` is kept as repository-local and explicitly not
  identity; the author string stays raw evidence; dates are kept as UTC
  plus the recorded offset; tags are counted but never called releases;
  public/draft/secret phases are preserved. Malformed JSON and non-array
  payloads fail closed, unusable entries are counted as rejects rather than
  guessed, and a change cap bounds input. `connectors/manifests/mercurial.json`
  declares history-only capability (everything else `unsupported`) and the
  source-review register records its rights. `src/test_m08.elisa` +
  `tests/test_m08.sh` cover the parse/normalize path, wrong-typed fields,
  rejects, bounds, and the native-form checks; `test_m02`'s manifest set and
  the register validator are updated for the sixth connector.
- M08 non-PR workflow lane: `src/rh_patch.elisa` gives patch series the
  right semantics. A logical change is keyed by (base subject, patch
  index), so `[PATCH 1/1]`, `[PATCH v2 1/1]`, `[PATCH v3 1/1]` collapse to
  one change with `max_version` 3, while `1/2`+`2/2` is two changes;
  `Re:` prefixes are handled and non-patch messages each count as their own
  change rather than being forced into a series. Trailers and roles are
  explicitly out of scope here. `test_m08` covers revisions-collapse,
  series-counting, the mixed case, reply prefixes, and non-patch messages.
- Versioned metric registry (R023/M00-05, F038): `src/rh_registry.elisa`
  now keys definitions by `(key, version)`. Entry 10 is a deliberate second
  version of `coverage.window_completeness` at `2.0.0` with a *different*
  denominator rule and status `prototype`, so a denominator change is a new
  definition rather than a silent redefinition. Added `rh_reg_find_versioned`
  and `rh_reg_denom_rule_for` (an unknown version resolves to -1 with no
  fallback), `rh_reg_implemented_count`, and per-entry `rh_reg_status`;
  `rh_cli registry` prints the status. `tests/test_m00.sh` now verifies every
  key *and version* literal is mirrored and that exactly ten definitions are
  implemented; `test_oracles` exercises the v1/v2 distinction and the
  no-fallback rule. F038 moves from planned to covered.
- F001-F040 fixture catalog and mechanical lint:
  `fixtures/fixture-catalog.json` records every plan fixture with an honest
  `covered`/`partial`/`planned` status and a pointer to the test that
  proves it; `tools/fixture-lint.sh` fails when a `covered`/`partial` entry
  names a file or token that does not exist, so no green suite can imply
  coverage that is absent. `tests/test_fixtures.sh` runs the lint, enforces
  all forty ordered ids, and asserts the security-critical fixtures are
  covered while the unimplemented ones stay honestly `planned`. Current
  split: 28 covered, 4 partial, 8 planned. The release packet now embeds
  the same coverage summary.
- M07 security/ops cores: `src/rh_ops.elisa` (backup manifest writer;
  verify that counts present/corrupt and **refuses to restore** corrupt
  objects; monitoring with separate `rh_service_*` and `rh_project_*`
  series and an observed-rate that returns -1 — unknown, never 0 — when
  there is no denominator; per-host token-bucket quota with exponential
  capped backoff, operator stop, and cancel refund) and transport
  hardening in `src/rh_git.elisa` (leading-zero/octal, hex, and zero-padded
  host obfuscation; strict hostname charset; extended reserved v4 ranges;
  a post-DNS `rh_addr_guard` for rebinding that the connector must call
  before any bytes leave). `src/test_m07.elisa` + `tests/test_m07.sh`
  cover all of it: transport accept/reject matrix, address guard,
  structured parser failure under hostile JSON/semver/lockfile input,
  monitoring separation, quota/backoff/stop, and a corruption-detected
  backup/restore drill.
- Documentation honesty note (M07-04): store verification is FNV-1a
  integrity, explicitly **not** a signature and never presented as a
  safety claim; release signing stays pending.
- M07-07 publication suppression gate: `src/rh_privacy.elisa` decides
  publish/suppress-small/withhold-private/withhold-unknown with precedence
  unknown > private > threshold, so a private or unknown-visibility member
  can never be folded into a public aggregate, and its explanation states
  that suppression is not anonymization.
- M07-13 runbooks: `docs/operations/runbooks.md` documents the seven
  operational procedures (provider outage/schema change, bad identity
  merge, corrupt evidence, credential exposure, mass false alert, operator
  removal, backup restore), each tied to the module that enforces it and
  ending with what must be recorded.
- Release evidence packet generator: `tools/release-packet.sh` emits a
  deterministic `release-packet.json`/`.md` from real tree state —
  implemented metric definitions (refusing an implemented metric without a
  denominator/fixtures/source requirements), the reviewed source register,
  milestone stages, and the local harness list. It states that it does not
  assert test results and lists known limitations; `tests/test_release_packet.sh`
  checks determinism, schema, and absence of safety/trust verdicts.
- M07-06 source review register: `ops/source-review-register.json` records
  terms, redistribution, attribution, personal-data fields, retention,
  contact, and per-capability scope for five collected source families;
  `tests/test_m07.sh` validates the schema and rejects credential-like
  fields. GitHub's traffic capability is explicitly `unauthorized`.

- M06 query + notification surfaces: `src/rh_query.elisa` (validated
  request kinds; stable exclusive-cursor pagination with a page-size cap
  where replaying an old cursor is idempotent; per-capability scan-status
  tally plus failure localization so a failed review fetch becomes a
  stale/unavailable REVIEW row and never a project verdict; bounded graph
  jobs with an in-memory fenced lease using the recorded-ttl semantics
  proven by the store) and `src/rh_notify.elisa` (upstream maintainers
  refused unless explicitly subscribed, suppressed decisions record
  nothing so a phantom cooldown cannot silence a first real alert,
  artifact-digest change starts a new key, acknowledged/resolved keys stay
  quiet, source outages suppress coverage alerts). `test_m06b` covers
  all of it including the unauthorized/cooldown/ack/resolve/outage matrix
  and pagination/job-fencing sequences.

- M06 policy/correction layer: `src/rh_policy.elisa` (four-valued
  decision lattice deny > unknown > warn > allow, so unknown is never
  spent as permission and warn cannot override deny; exact rational
  comparisons for all six operators with overflow returning unknown;
  freshness, minimum-sample, and required-completeness gates; scoped
  approved-and-unexpired-and-digest-matched exceptions; binding digests
  over subject/context/artifact/rules/time for TOCTOU safety; structured
  explanation built only from typed fields) and `src/rh_correction.elisa`
  (open/accepted/rejected disputes; acceptance advances a revision;
  targeted derived-result supersession; replay from an unchanged raw
  ledger).
- `src/test_m06.elisa` + `tests/test_m06.sh`: truth table for observed
  pass/fail/unavailable/partial/stale/not-applicable/conflicted/
  suppressed/unsupported, freshness/sample/completeness gates,
  precedence assertions (deny>unknown>warn>allow, deny+unknown→deny,
  warn+deny→deny), missing-input→unknown, exception suppression/expiry/
  digest-mismatch, TOCTOU digest binding, agent prose-inertness, and
  correction invalidation/replay. Harness adds a no-floating-point
  exactness check and the lattice/fail-closed contract checks.
- M05 temporal graph + downstream layer: `src/rh_graph.elisa` (labeled
  projections with scope/platform/valid-time/known-time/revision/
  visibility fields and node/depth budgets, bitemporal edge visibility
  enforcing the S009 no-leakage rule, unique direct/transitive reverse
  traversal with structural root exclusion and dedup, iteration-based
  Kosaraju SCC with bounds guards — no recursion anywhere, mirror/family
  dedup gated on ACCEPTED assertions only, simulated-unavailability
  scenarios) and `src/rh_downstream.elisa` (per-metric covered
  denominators so coverage is never collapsed into one number, value
  histograms, staged adoption evidence with right-censored durations and
  observed-upgrade semantics distinct from migration, observed
  actor-overlap for shared-maintenance exposure).
- `src/test_m05.elisa` + `tests/test_m05.sh`: graph-count suite
  (chain/diamond/cycle/disconnected/multigraph/version-dupes/mirror-dupes
  with exact direct/transitive/SCC counts), truncation-flag assertion,
  private-dependent exclusion under public projections, the 2024/2025/2026
  valid-vs-known-time matrix, downstream coverage independence,
  anti-circularity (500 dependents added; intrinsics unchanged), adoption
  and censoring assertions, and a structural no-recursion check.
- M04 continuity/identity layer: `src/rh_identity.elisa` (explicit
  identity links with proposed/accepted/rejected/revoked lifecycle,
  revisioned union-find clusters recomputed on every change, actor-kind
  stratification where `unresolved` is never forced human) and
  `src/rh_continuity.elisa` (actor-by-complete-month presence matrix,
  persistence cohorts returning their components, continuity concern
  defined on the persistent core rather than one-off ratios, retention
  with censoring precedence and coverage-gap unobservability, exact
  concentration/effective-count via the shared rational core, primary
  actor and handover overlap measurement, role visibility, and an
  `rh-continuity/1` report that pairs every number with its rule,
  coverage, identity revision and denominators; empty populations
  serialize as `null`).
- `src/test_continuity.elisa` + `tests/test_m04.sh`: plan §9.4 oracles,
  fixtures A–E, revocation cluster/revision recomputation, automation
  stratification, report-field assertions, a structural check that the
  identity layer cannot reference raw events (revocation can never
  mutate the ledger), and an R030 score-language scan.
- M03 package layer (`src/rh_package.elisa`): ecosystem-native semver
  (strict digits, prerelease precedence with exact numeric-identifier
  ordering, build metadata ignored, one leading `v` tolerated), Cargo name
  normalization, `Cargo.lock` `[[package]]` parser (registry/path/git
  source kinds, checksums as digests separate from version labels, fail
  closed on malformed TOML, unknown keys counted — never dropped
  silently), npm parser (`lockfileVersion` 2/3 `packages` maps with
  Node-style walk-up resolution preferring nested installs, v1 legacy
  `requires` trees, dev/optional/peer scopes, integrity digests),
  requirement-vs-resolution separation with explicit unresolved reasons
  (`missing`/`ambiguous`/`context`) so a declared range never becomes an
  exact edge without resolution evidence, bounded forward/reverse BFS with
  truncation flags and root exclusion, bounded BFS witness paths, offline
  OSV matching (id+alias union merge with alias count, withdrawn counted
  and excluded, fixed-only ranges vulnerable-from-start per OSV
  semantics, unparseable ranges unknown), canonical `rh-dep-graph/1` JSON.
- `src/test_package.elisa` + `tests/test_m03.sh`: diamond/cycle/multi-
  version/optional/peer fixtures with byte-exact goldens (hand-verified),
  ambiguous-vs-missing unresolved assertions, truncation assertions,
  advisory alias-merge assertion, golden determinism re-dump.
- M02 durable store (`src/rh_store.elisa`, Elisa adaptation of M02-01/02:
  filesystem-backed per ADR-000, no Postgres in this slice):
  content-addressed evidence blobs (FNV hex names, immutable, tamper and
  missing block publication, operator-remove-then-refetch restore),
  JSONL canonical events with id-index dedup (retries/reorders converge),
  commit-after-verify cursors with one-page overlap (S004), coverage
  interval observations (M02-07).
- M02 job leasing (`rh_store`, M02-03 core): fencing tokens, recorded-ttl
  expiry (the lease judges its own ttl — a replacement's ttl cannot move
  the verdict), heartbeat/release gated on token match (stale workers
  cannot publish), terminal phases, append-only attempt log.
- `src/test_store.elisa` + crash-injection harness: deterministic selftest
  (fixed clocks) plus a real kill -9 sequence proving expiry reclaim with
  fencing increment and stale-release refusal with audit log entry.
- M02 forge layer: `src/rh_json.elisa` (bounded JSON parser — flat DOM,
  exact number spans, depth/node caps, U+FFFD substitution), `src/rh_forge.elisa`
  (5 capability manifests under `connectors/manifests/`, ISO8601 with
  leap-aware validation, SSRF fetch guard, GitHub/GitLab normalizers to
  `rh-canonical-repo/1` with byte-exact goldens), curl transport runner
  (`--proto`=https/file, no redirects, time/size caps, no auth headers).
- `src/test_forge.elisa` + `tests/test_m02.sh`: golden comparison,
  escape vectors, manifest↔code cross-check, file:// transport fidelity,
  guard blocks without packets, usage gate, opt-in live GitHub fetch.
- M01 CLI (`src/rh_cli.elisa` → `build/rh_cli`): `scan` (local path or
  public `https`, bare/blob-less/depth-bounded clone for remotes,
  plumbing-only acquisition, 10-metric pinned reports), `replay` (offline
  recompute from the retained bundle against the pinned cutoff — no clock,
  no network; exit 0 verified / 5 mismatch), `registry`, `version`.
- M01 report writer (`src/rh_report.elisa`): `report.json` (per-metric
  status/value/evidence, explicit capability block), `report.md`
  (restrained wording, no maintainer/traffic/dependent claims),
  `bundle.manifest` (FNV digest, counts, cutoff, file list), manifest
  field readers for replay.
- M01 gate (`tests/test_m01.sh`): usage/validation exits (2/3/4), F001
  empty, F002 exact multi-author, hostile fixtures (unicode, future,
  skew, merge, invalid-UTF-8 — no crash, future flagged), shallow clone
  (no lifetime claim, partial coverage), clone-path equivalence, replay
  verified, tamper → exit 5, corrupt manifest → exit 4, R030 language
  scan, determinism (identical digests across runs).
- Empty-repository handling: `rev-parse --verify HEAD` distinguishes
  observed-empty history (exit 0, honest zeros + unavailable freshness)
  from genuine collection failure (exit 4).
- M01 Git acquisition module (`src/rh_git.elisa`): URL classification
  (local / public-https / unsupported), strict shell-argument allowlist,
  plumbing-only `log` / `rev-parse` / `--version` runners with structured
  exit reporting.
- M01 scan engine (`src/rh_scan.elisa`): NUL-delimited log parser with
  counted rejections (never coerced), bot-heuristic helper, FNV evidence
  digest over the accepted stream, window coverage, local manifest probe,
  hex-digest parser for replay.
- Oracle coverage for URL classification and the allowlist (20 checks:
  `https` accepted; `http`/`ssh`/`scp`/`file`/empty rejected; `; space ' $
  `` ` `` `|` `&` `@` `$()` and empty rejected).

### Changed
- Standard-library-first native boundary: `src/rh_base.elisa` includes the
  Elisa standard library (`elisacore_std`: runtime hub + file I/O) and uses
  it instead of hand-written libc `extern`s: std declarations for `strlen`,
  `strcmp`, `write`, `getenv`; std `file_exists` in the manifest probe; std
  `read_entire_file` / `write_entire_file` behind the bounded `rh_io_read` /
  `rh_io_write` wrappers (engine-style expression `catch`, `RH_MAX_READ`
  cap retained). Remaining direct `extern`s are only what the standard
  library does not provide: `system`, `mkdir`, `time`.
- Toolchain follows elisa-engine (studied as the style exemplar): installed
  stage1 snapshot on PATH, `-emit exe` direct to executables, `main() ->
  i32`; `tools/build.sh` + `tools/check.sh` rewritten to that pattern (see
  `TOOLCHAIN.md`). Engine's `entity_id` test passes through the same path.
- Expression-`catch` with bare variant arms adopted; statement-`catch` with
  `return`s and payload-destructuring `(_)` arms do not lower on the pinned
  product (see "Stale-toolchain surface" below). New code binds catch
  results (`got: T = catch ...`) and returns the binding.
- `return <call>` (direct call in return position) declined by the backend;
  new code binds first, then returns. Avoid `fail` as a function name (the
  std prelude owns it); avoid `match` as a variable (reserved).
- `struct` fields assigned after construction must be declared `mutable`.
- Value-block capture semantics confirmed safe for never-mutated locals;
  prefer binding a struct/darray element to a local before passing it by
  reference (`x: T = arr[i]; f(x)`) — passing `arr[i]` directly as a
  `&`-argument, or a struct where a `darray[T]&` is expected, produces a
  misleading "backend could not produce a linkable unit; declined
  (expression)" instead of a clean type error. Same for an overlarge
  single `main`: backend declines report as `(expression)`; split test
  bodies into section functions with `fails: mutable i64&`.
- `rh_manifest_has` uses std `file_exists`; `rh_file_exists` removed.
- Standard-library sweep (no ad-hoc duplicates): surveyed `elisacore_json`
  (its numbers are `f64` — wrong for exact IDs — and its accessors return
  `error` unions needing payload `catch`, still stage0-only, so the exact
  `rh_json` parser stays with reasons recorded here), `elisacore_math`
  (no gcd; nothing to adopt), string `sview` helpers (adopted where they
  fit: the write path and manifest spans). Deliberately remaining ad-hoc:
  darray number printers (no per-call arena growth), civil-date math,
  FNV-1a, concentration rationals (exactness requirements above what std
  offers).

### Fixed
- Notification phantom cooldown: `rh_notify_record` created a row even for
  a suppressed (unauthorized/outage) decision, which then started a
  cooldown that silenced the first genuine alert. Suppressed decisions now
  record nothing; only a delivered notification starts a cooldown.
- Build slowness: `tools/build.sh` is incremental (skips binaries newer
  than every source module and than the script), so the single local suite
  no longer recompiles all nine binaries once per harness (120s+ -> ~25s).
- M03 development fixes (all caught by fixtures before check-in):
  (1) v1 npm requirements read from `requires`, not nested
  `dependencies` (nested entries are packages, not range strings);
  (2) OSV name/version comparisons normalized into the inventory pool
  first — comparing spans across two decoded-text buffers indexed the
  wrong array (silent mismatches for Cargo, bounds traps for npm);
  (3) OSV event items are JSON objects (kind 5), not arrays — the wrong
  kind check rejected every range; (4) OSV ranges with only
  `fixed`/`last_affected` are vulnerable-from-start (implicit
  introduced=0) instead of never matching.
- Module-namespacing REVERTED (correctness over style): converting
  `src/*.elisa` to engine-style `module`/`using` produced silent zeroed
  output — identical code is byte-correct flat and zero-filled in modules
  (correct length, zero content; e.g. `report.json` went from valid JSON
  to 1890 NUL bytes). Minimal repros: a module function pushing through a
  cross-module `&`-param helper zeroes the bytes; direct method pushes in
  the same function are fine; the same shapes are correct in flat files
  (full M00/M01/M02 gates green before and after the revert). Per-file
  `include`s are kept (driver dedupes; engine layering), `rh_` prefixes
  are the namespace, and formerly-private helpers are marked
  `# private to this file`. Modules retried after a toolchain re-seed.
- Trailing-newline record: `git log` appends `\n` after the final NUL;
  the parser treats a whitespace-only tail as terminator, not a rejected
  record (verified: `rejected: 0` on clean fixtures).
- Replay compares digest AND counts: a tamper that only adds rejected
  records leaves the digest unchanged, so counts are pinned too (verified:
  appended byte → exit 5).
- Concentration threshold comparison (`rh_cross_ge`): the gcd reduction
  divided one product alone, which is mathematically wrong (caught by the
  `[9,3]` 80% and `[25×4]` oracles). Both sides are now divided by common
  factors. Verified: `ORACLES OK`.
- `.gitignore` no longer ignores `docs/adr` and `TOOLCHAIN.md` (required
  deliverables); `build/` is ignored instead.

### Known limitations
- `system(3)` still invokes a shell; user input passes the strict
  allowlist first (documented deviation, see `docs/THREAT_MODEL.md`).
- Stale-toolchain surface (pinned snapshot rev `debbf68b`): statement-form
  `catch` with `return`s, payload-destructuring `(_)` arms, direct
  `return <call>`, and the `fail`/`match` identifiers do not lower — see
  Changed above for the adopted shapes. A re-seed may lift these; until
  then the constraints are load-bearing style rules, recorded here rather
  than worked around silently.
- No subprocess timeout yet (macOS has no `timeout(1)`); scans are bounded
  by `--max-count` and the `RH_MAX_READ` cap. Tracked for M07 hardening.

## [0.1.0] — 2026-09-18

### Added
- Honest baseline (M00-01): public-domain `LICENSE` (owner-confirmed),
  `README.md`, `TOOLCHAIN.md` (pinned: stage1 product, LLVM 23.1.1, Apple
  Git 2.54.0), `tools/build.sh` + `tools/check.sh` (portable compiler
  lookup via `ELISA_COMPILER_ROOT`, sibling-dir default),
  `docs/adr/ADR-000.md` (Elisa override), `docs/THREAT_MODEL.md`,
  `STATUS.md` (all 360 catalog metrics `planned`, none claimed).
- Domain contracts in Elisa (M00-02…M00-06): `rh_domain` (opaque IDs,
  native refs, revision/edge/finding kinds), `rh_temporal` (intervals,
  civil algorithms, bitemporal visibility), `rh_observation` (11 statuses,
  ratio rules, §18.2 consistency), `rh_registry` (10-metric M01 subset +
  lint), `rh_evidence` (FNV-1a, spec vectors), `rh_metrics` (exact HHI,
  overflow-safe concentration).
- Oracle suite (`src/test_oracles.elisa`, ~50 checks, exit 0) and
  `tests/test_m00.sh` gate: build + oracles + JSON registry mirror
  consistency + STATUS honesty + required docs.
- `metrics/definitions/*.json`: the 10 M01 metrics, all
  `implementation_status: planned`, machine-checked against the Elisa
  registry.
