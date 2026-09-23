# repo-health — Implementation Plan

**Document version:** 0.2.0  
**Status:** Research-informed delivery plan; implementation evidence tracked separately in [STATUS.md](STATUS.md)  
**Prepared:** 2026-09-18  
**Updated:** 2026-09-21
**Companions:** [Architecture.md](Architecture.md), [research paper](REPO_HEALTH_RESEARCH_PAPER.md)  
**Architecture baseline:** repo-health Architecture 0.1.0

> **Delivery objective:** Build a useful, defensible repository-health observatory in small verified increments, while preserving the long-term design: multiple source hosts, temporal dependency relationships, downstream condition, concrete maintainer-continuity measurements, and a very broad extensible metric catalog.

This plan translates the architecture into code boundaries, schemas, work packages, tests, acceptance criteria, operational safeguards, and release gates. It is deliberately ambitious about eventual coverage and conservative about what a completed increment may claim.

The architecture contains 360 candidate metric definitions across 30 families. The implementation must not attempt to ship all 360 before producing a useful first release. Equally, it must not reduce the project to a GitHub-star dashboard and call the broader mission complete.

This revision incorporates the local research paper, especially §§13–22 and Appendices A–D. Its static source review and 16 reported synthetic checks motivate adoption gates; they do not validate upstream deployments or this implementation. Commands, schemas, workload targets, and proposed paths below remain specifications unless supported by implementation evidence. The repository now contains Elisa code, fixtures, and tests. Reconcile work against [STATUS.md](STATUS.md), the real execution paths, and [ADR-000](docs/adr/ADR-000.md) before implementing it again; this documentation update does not certify milestone completion.

## Contents

- [1. Delivery strategy](#1-delivery-strategy)
- [2. Requirements and traceability](#2-requirements-and-traceability)
- [3. Milestone map and dependency graph](#3-milestone-map-and-dependency-graph)
- [4. Repository structure and module ownership](#4-repository-structure-and-module-ownership)
- [5. M00 — Establish contracts and test oracles](#5-m00--establish-contracts-and-test-oracles)
- [6. M01 — Safe Git scan and first real report](#6-m01--safe-git-scan-and-first-real-report)
- [7. M02 — Durable ingestion and multiple source hosts](#7-m02--durable-ingestion-and-multiple-source-hosts)
- [8. M03 — Package identity, dependency evidence, and advisory matching](#8-m03--package-identity-dependency-evidence-and-advisory-matching)
- [9. M04 — Maintainer continuity and reversible identities](#9-m04--maintainer-continuity-and-reversible-identities)
- [10. M05 — Temporal graph and downstream ecosystem condition](#10-m05--temporal-graph-and-downstream-ecosystem-condition)
- [11. M06 — Product surfaces, policy gates, and corrections](#11-m06--product-surfaces-policy-gates-and-corrections)
- [12. M07 — Security, privacy, operations, and public beta](#12-m07--security-privacy-operations-and-public-beta)
- [13. M08 — Broader source and ecosystem coverage](#13-m08--broader-source-and-ecosystem-coverage)
- [14. M09 — Expand the metric catalog responsibly](#14-m09--expand-the-metric-catalog-responsibly)
- [15. M10 — Scale only after measuring](#15-m10--scale-only-after-measuring)
- [16. M11 — Experimental models and advanced verification evidence](#16-m11--experimental-models-and-advanced-verification-evidence)
- [17. M12 — Stable production release and stewardship](#17-m12--stable-production-release-and-stewardship)
- [18. Concrete storage and ingestion blueprint](#18-concrete-storage-and-ingestion-blueprint)
- [19. Algorithm implementation notes](#19-algorithm-implementation-notes)
- [20. Comprehensive test strategy](#20-comprehensive-test-strategy)
- [21. Performance validation and capacity planning](#21-performance-validation-and-capacity-planning)
- [22. Operational runbooks](#22-operational-runbooks)
- [23. Risk register and mitigation ownership](#23-risk-register-and-mitigation-ownership)
- [24. Team structure and AI-assisted implementation](#24-team-structure-and-ai-assisted-implementation)
- [25. Initial executable backlog](#25-initial-executable-backlog)
  - [25.1 Research follow-up queue](#251-research-follow-up-queue)
- [26. Release evidence packet](#26-release-evidence-packet)
- [27. Success measurements for repo-health itself](#27-success-measurements-for-repo-health-itself)
- [28. Primary implementation references](#28-primary-implementation-references)
- [29. Final implementation rule](#29-final-implementation-rule)

## 1. Delivery strategy

### 1.1 Build vertically before expanding horizontally

The first usable slice should accept one repository, safely acquire real evidence, normalize it, compute a small set of exact metrics, produce a report, and explain every value. That path must work end to end before building a large dashboard, a global crawler, or a predictive model.

Once the slice works, add a second source family without changing the core model. This is the first architectural test of forge independence. Then add package identities, version-aware dependencies, reverse edges, continuity cohorts, and downstream-condition summaries.

Breadth follows correctness. Hundreds of metric keys with placeholders, guessed values, or undocumented formulas are not progress. A missing-capability result is acceptable when honest; a synthetic success response in a live-data path is not.

### 1.2 Preserve the distinctive features early

The first public beta must demonstrate more than repository metadata. It should include:

- Generic Git collection independent of a forge API.
- At least two genuinely different forge/provider implementations and a tested self-hosted instance configuration.
- Role-specific participation and persistent-contributor measurements.
- Version-aware dependency evidence in at least two package ecosystems.
- Known downstream dependents with their independently computed intrinsic measurements.
- Provenance, missing-data states, and reproducible report inputs.
- An explainable policy result that cannot silently convert unknown data into permission.

The beta need not know every dependent in the world. It must precisely identify the observed graph it does know.

### 1.3 Use milestones, not speculative calendar promises

Milestones are dependency and acceptance boundaries, not guaranteed dates. Some work can proceed in parallel, but a milestone is complete only when its tests and evidence artifacts pass.

Project staffing and workload estimates should be created after the initial data and performance spikes. Avoid scheduling the entire ecosystem crawl from assumptions about average repository size or API access that have not been measured.

### 1.4 Default technical direction

The reference implementation uses Elisa, as recorded in [ADR-000](docs/adr/ADR-000.md), with sources in `src/`, build/test tooling in `tools/` and `tests/`, and pins in [TOOLCHAIN.md](TOOLCHAIN.md). The earlier Rust/Go proposal is superseded. Do not introduce a language migration or duplicate crate tree as part of research adoption.

Use the expression-based style demonstrated by the sibling `elisa-engine`: block expressions own construction temporaries, scoped loop expressions own their counters and accumulators, and only results needed later escape those scopes. Prefer Elisa standard-library operations wherever their contracts fit. Preserve exact arithmetic, bounded parsing, and ownership lifetimes. Follow [the Elisa style guide](docs/elisa-style.md) for examples and current compiler constraints.

Filesystem evidence storage is the current baseline. PostgreSQL remains the planned server persistence target, subject to the transaction and failure gates below; proposed SQL is not evidence of a deployed database. External tools may supply versioned data through isolated adapters without replacing the Elisa canonical core. Pin exact tool/interface versions and review their operating and redistribution terms before enabling them.

### 1.5 Minimize the first production stack

The planned PostgreSQL-backed server deployment requires the application, PostgreSQL, an evidence directory, and an approved isolation mechanism for collectors. The current filesystem-backed implementation must satisfy the same evidence and replay contracts within its declared scope. It does not require Kubernetes, Kafka, Neo4j, a search cluster, a distributed data lake, or a separate machine-learning service.

Use interfaces that permit future replacements without building them prematurely. Add a new infrastructure component only after a measured problem and an architecture decision explain why simpler alternatives are insufficient.

### 1.6 Research adoption decisions and boundaries

Reuse acquisition and parsing capabilities selectively; own canonical identities, temporal semantics, executable metric contracts, reversible assertions, downstream populations, and policy decisions. These are planned dispositions, not installed integrations. Each adoption needs a pinned interface/revision, capability and rights review, retained fixtures, a normalization loss report, an operational owner, and a fallback when the provider disappears. Recheck mutable service claims at adoption time.

| Research input | Disposition and owning milestone | Required adoption evidence |
|---|---|---|
| CHAOSS (§5) | Reuse definitions through a versioned crosswalk in M00/M09. | Local unit, population, filters, denominator and interpretation; preserve the named 50% Contributor Absence Factor definition. |
| Aveloxis (§6) | Adapt staging, collection-start watermarks and queue patterns in M02. | Crash recovery, overlap, lease fencing, and failed-versus-empty replacement; row locks alone do not establish exactly-once behavior. |
| CollectOSS (§7) | Optional event import/breadth adapter in M04/M08. | Native event grain, join-cardinality fixtures, bounded time/event coverage; participation never implies authority. |
| GrimoireLab (§8) | Evaluate one Perceval backend in M02/M08; adapt SortingHat assertion/reversal concepts in M04. | Replayable envelopes, per-capability fixtures, identity revoke/recompute; no mandatory full GrimoireLab deployment or unrestricted profile import. |
| ecosyste.ms (§9) | First external repository/package lookup candidate, then parser/dependent enrichment in M03/M05. | Mapping provenance, bounded-population labels, parser field preservation, versioned caching, and separate code/data rights review. |
| deps.dev (§10) | Optional requirements/resolution enrichment in M03/M05. | Graph-local node identity, environment assumptions, node/edge errors and capped mapping responses retained; reverse index remains local. |
| Scorecard (§11) | Import structured findings in M06/M09, not an aggregate admission score. | Probe/version/polarity, inconclusive states, original assessment age, locations, remediation and shared-origin deduplication. |
| Criticality Score (§12) | Optional attributed historical/raw importance signals in M09. | Input dates, configuration and available-input coverage; no assumed live cloud dataset and no importance-to-health conversion. |

### 1.7 First research integration slice

After the contract gaps are closed, demonstrate one focal library and a small, explicitly observed dependent population across the two supported package ecosystems. Use native Git evidence, one external package/repository lookup adapter, and one parser adapter. Resolve mappings as assertions; compute a small set of intrinsic continuity measurements for each covered dependent independently of adoption signals.

The M03–M06 slice delivers a replayable report with package/version/project/family counts, dependency context and path witnesses, per-metric coverage, distributions, and an evidence drill-down. Include a mirror, multiple packages from one project, an unmapped package, a missing intrinsic measurement, and an unavailable provider. Every inclusion and exclusion must be explainable. Missing dependents remain visible in coverage; no global completeness claim is permitted. This slice precedes broad provider rollout and optional metric expansion, while retaining the M07 public-beta gates.

## 2. Requirements and traceability

### 2.1 Functional requirements

| ID | Requirement | First validating milestone |
|---|---|---|
| R001 | Accept generic public Git sources without GitHub-specific domain assumptions. | M01 |
| R002 | Produce a capability/coverage report for every scan. | M01 |
| R003 | Retain evidence references for every published metric. | M01 |
| R004 | Represent exact counts, ratios, enums, dates, and unknown states. | M00 |
| R005 | Replay deterministic metrics from a pinned evidence bundle. | M01 |
| R006 | Ingest multiple forge APIs through capability adapters. | M02 |
| R007 | Support arbitrary approved self-hosted instance base URLs. | M02 |
| R008 | Keep projects, repositories, packages, versions, and artifacts distinct. | M00 / M03 |
| R009 | Preserve requirements separately from resolved dependency edges. | M03 |
| R010 | Calculate direct and bounded transitive upstream/downstream relations. | M03 / M05 |
| R011 | Compute downstream condition from independent intrinsic metrics. | M05 |
| R012 | Deduplicate mirrors and project families with explicit assertions. | M05 |
| R013 | Track declared roles separately from observed actions. | M04 |
| R014 | Compute persistent cohorts and correctly censored retention. | M04 |
| R015 | Measure review, release, and change concentration independently. | M04 |
| R016 | Support reversible identity corrections. | M04 |
| R017 | Record both valid time and system knowledge time. | M00 / M05 |
| R018 | Match known advisories to supported exact package/version contexts. | M03 |
| R019 | Distinguish affected dependency reachability from runtime exploitability. | M03 / M06 |
| R020 | Evaluate allow, warn, deny, and unknown policy outcomes. | M06 |
| R021 | Bind policy evaluations to subject, context, evidence, and policy digests. | M06 |
| R022 | Expose API, CLI, evidence explanations, and accessible reports. | M01 / M06 |
| R023 | Add metrics through a versioned registry rather than schema columns. | M00 |
| R024 | Admit advanced measurements only with tests, costs, and interpretation limits. | M09 |
| R025 | Include native non-Git history and non-PR workflow support. | M08 |
| R026 | Treat traffic and clone data as optional authorized capabilities. | M02 / M09 |
| R027 | Import standards-based software inventories with declared version support. | M03 / M08 |
| R028 | Support project correction and dispute workflows. | M06 / M07 |
| R029 | Detect source-coverage changes separately from project-activity changes. | M02 |
| R030 | Publish no universal unqualified project-health or contributor-trust score. | Every milestone |

### 2.2 Safety and integrity requirements

| ID | Requirement | Mandatory evidence |
|---|---|---|
| S001 | No arbitrary source build execution in default collection. | Hostile-repository integration tests. |
| S002 | No public-crawler access to internal network destinations. | SSRF and redirect/DNS-rebinding test suite. |
| S003 | No credential leakage through redirects, logs, or evidence. | Secret-canary tests and log inspection. |
| S004 | No cursor advance that loses a committed page's records. | Crash injection around every commit boundary. |
| S005 | No duplicate analytical counts from retries or duplicate webhooks. | Replay and duplicate-delivery tests. |
| S006 | No raw unknown converted to a numeric zero. | Schema, property, and policy tests. |
| S007 | No public/private graph or cache leakage. | Multi-tenant adversarial tests. |
| S008 | No destructive identity merge without a reversal path. | Merge/revoke/replay tests. |
| S009 | No historical prediction using later evidence. | Bitemporal fixtures and leakage tests. |
| S010 | No person-level moral, medical, or sensitive-attribute inference. | Data schema and publication review. |
| S011 | No unsupported safety certification from signatures, tests, or popularity. | Report wording and policy-contract tests. |
| S012 | No unbounded graph traversal, archive expansion, or repository fetch. | Resource-limit tests with verified termination. |

### 2.3 Definition of done for any feature

A feature is complete only when its input/output contract is documented, implementation is connected to the real execution path, positive and negative tests pass, required security boundaries are exercised, unsupported cases return correct states, and user-facing explanations match the actual behavior.

A UI page displaying fixture data is a demo, not a completed live integration. A parser that accepts one happy-path lockfile is a prototype, not ecosystem support. A metric that lacks a denominator definition is not ready for publication.

Every work item records implementation status as `planned`, `prototype`, `implemented`, `validated`, `released`, or `retired`. The catalog must not imply that all proposed metrics are available.

## 3. Milestone map and dependency graph

| Milestone | Deliverable | Depends on | Release significance |
|---|---|---|---|
| M00 | Domain contracts, metric registry, fixture harness, threat model. | None | Architecture foundation. |
| M01 | Safe local/generic-Git scan, real metrics, replayable report. | M00 | First useful developer tool. |
| M02 | Durable ingestion, scheduling, multiple forge adapters, coverage. | M01 | Multi-source alpha. |
| M03 | Package identities, two ecosystem parsers, resolved graph, OSV. | M00–M02 | Dependency-aware alpha. |
| M04 | Roles, persistence, retention, concentration, reversible identities. | M02 | Continuity-aware alpha. |
| M05 | Temporal projections, downstream condition, family deduplication. | M03–M04 | Core differentiated product. |
| M06 | API, accessible UI, policy gates, explanations, corrections. | M03–M05 | Feature-complete beta candidate. |
| M07 | Security, privacy, operations, licensing, external pilot validation. | M00–M06 | Public beta release gate. |
| M08 | Expanded forge/VCS/registry/inventory/workflow coverage. | M07 | Broader ecosystem usefulness. |
| M09 | Metric catalog expansion and standards/provenance integrations. | Relevant earlier modules | Rich analytics releases. |
| M10 | Proven scaling, analytical snapshots, optional distributed workers. | M07, measured need | Larger deployment capability. |
| M11 | Validated experimental models, proof/benchmark evidence adapters. | M05, M09 | Optional advanced capabilities. |
| M12 | Stable 1.0 contracts, governance, sustainable operations. | M07–M10; M11 optional | General production release. |

```text
M00 -> M01 -> M02 -> M03 ---+
                |          |
                +-> M04 ---+-> M05 -> M06 -> M07 -> M08
                |                                |     |
                +---------- metric additions ----+--> M09
                                                 +--> M10
                                      M05 + M09 ----> M11
                                      validated core ----> M12
```

Security work begins in M00; M07 is the release gate, not the first time security is considered. M11 is not required for 1.0: the observatory can provide substantial value without predictive models.

## 4. Repository structure and module ownership

### 4.1 Logical boundaries and historical proposed layout

The tree below is the original logical module proposal, not a migration task. Implement equivalent boundaries in the existing Elisa `src/` layout under ADR-000; Cargo files and Rust crates are historical examples. New research contracts belong with the existing schemas, fixtures, connector manifests, and tests.

```text
repo-health/
  Architecture.md
  IMPLEMENTATION_PLAN.md
  README.md
  LICENSE
  SECURITY.md
  CONTRIBUTING.md
  Cargo.toml
  Cargo.lock
  rust-toolchain.toml
  crates/
    rh-domain/
    rh-schema/
    rh-evidence/
    rh-ingest/
    rh-identity/
    rh-vcs/
    rh-connectors/
    rh-packages/
    rh-graph/
    rh-metrics/
    rh-findings/
    rh-policy/
    rh-store/
    rh-api/
    rh-cli/
    rh-worker/
  web/
    templates/
    assets/
    tests/
  schemas/
    events/
    observations/
    policies/
    bundles/
    connector-manifests/
  metrics/
    definitions/
    profiles/
    fixtures/
  connectors/
    manifests/
    compatibility/
    fixtures/
  migrations/
  tests/
    unit/
    integration/
    property/
    adversarial/
    replay/
    performance/
    privacy/
  fixtures/
    synthetic/
    sanitized-provider/
    golden/
  tools/
    fixture-generator/
    schema-check/
    metric-lint/
    benchmark-runner/
  ops/
    compose/
    systemd/
    dashboards/
    runbooks/
    backup/
  docs/
    adr/
    api/
    metrics/
    connectors/
    privacy/
    operations/
    releases/
```

This layout is a boundary proposal. Do not create dozens of empty crates solely to imitate the tree. Start with domain, evidence, metrics, CLI, and a small VCS module; split modules into crates when dependency direction or isolated testing justifies it.

### 4.2 Dependency direction

`rh-domain` depends on no forge-specific crate. `rh-metrics` depends on domain contracts and deterministic utilities, not HTTP clients. `rh-policy` depends on typed metric results and policy definitions, not raw source payloads. `rh-api` and `rh-cli` orchestrate application use cases rather than reimplementing formulas.

Collectors may use source-specific libraries, but their outputs cross a validated canonical boundary. Plugins do not directly insert arbitrary metric rows into the public database.

### 4.3 Public schemas as compatibility boundaries

Version JSON Schemas and API contracts. Generate language types where appropriate, but keep schema tests independent of generated code. The same bug must not define both the producer and the only validator.

Every schema example in documentation is validated in CI. Unknown fields follow a documented compatibility policy. Unsupported major versions fail clearly; they are not accepted and partially ignored while claiming a complete import.

### 4.4 Development tooling

Provide formatting, linting, unit-test, integration-test, fixture-validation, schema-validation, and documentation-check commands. A single developer command should run the safe local suite without production credentials.

Networked connector tests are opt-in and separate from deterministic CI. Golden fixtures come from synthetic or permitted sanitized sources. Record fixture generation scripts so a failing case can be reproduced rather than merely copied.

## 5. M00 — Establish contracts and test oracles

### 5.1 Goal

Create the smallest foundation that prevents later modules from inventing incompatible meanings for identities, timestamps, missing values, dependencies, or contributor roles.

### 5.2 Work packages

**M00-01: Baseline reconciliation.** Verify existing project files, recorded license decision, toolchain pins, local checks, and supported platforms. Reconcile registry and status claims with execution-path evidence rather than recreating the bootstrap. New research requirements start as planned even where related code exists.

**M00-02: Domain types.** Implement opaque IDs for projects, repositories, accounts, revisions, packages, package versions, artifacts, evidence, graph snapshots, and metric definitions. Preserve source-native IDs separately. Do not reuse a raw string for every identity in application code.

**M00-03: Temporal primitives.** Implement UTC instants, half-open intervals, complete-calendar-month iteration, valid/system time pairs, unknown-start intervals, and time-basis enums. Reject invalid interval ordering and negative durations except where a metric intentionally preserves a meaningful signed interval.

**M00-04: Typed observations.** Implement value variants, measurement status, denominator rules, evidence links, quality dimensions, and serialization. Values may be absent for non-value states. Partial observations can contain a value only with explicit incompleteness metadata.

**M00-05: Metric registry.** Define the schema for metric specifications, register the initial keys, and add lint rules: unique key/version; known entity kind; unit/type consistency; denominator handling; source requirements; cost class; privacy class; and fixture references.

**M00-06: Evidence bundles.** Specify manifest, object digests, schema versions, rights metadata, expected metric outputs, and identity/mapping revisions. Build a minimal reader/writer with deterministic canonical ordering.

**M00-07: Threat model.** Enumerate trust boundaries from URL submission to public report publication. Document protected assets, allowed network paths, collector privileges, secret handling, and prohibited inference categories.

**M00-08: Synthetic fixture generator.** Generate controlled histories, graph structures, and account/role events. Keep expected outputs independent from production algorithms.

**M00-09: Observation and lineage contracts.** Version the evidence envelope with source instance/native object ID, locator, event/update/observation times, collection run and scope, coverage, payload schema/digest, collector version, rights/retention class, and derivation references. Keep delivery identity distinct from origin assessment identity. Deduplicate a shared assessment using tool/version, subject revision, original run/time and result digest where available; incomplete identity yields possible duplication, not claimed independent corroboration. (Paper §§13.5–13.8.)

**M00-10: Transformation and measurement contracts.** Record parser/normalizer version, configuration digest, input digest and output schema. Emit field-level `preserved`, `transformed`, `inferred`, `discarded`, or `unsupported` states for analysis-relevant fields; missing optionality is unknown, not false. Add the CHAOSS crosswalk and explicit raw/derived/modeled classification to metric admission. Schema changes require compatibility and migration fixtures, not silent reinterpretation. (Paper §§13.9, 17.)

**Current repository checkpoint:** all 212 metric definitions now declare `measurement_class`; the admission linter requires `raw`, `derived`, or `modeled` and confines modeled definitions to the experimental group. The canonical commit Contributor Absence Factor definition and its compatibility alias carry a CHAOSS crosswalk with the reviewed source file-object ID, its default-branch/unpinned status, the exact local Git-event population, the inclusive 50-percent boundary, empty-population behavior, deliberate scope differences, and interpretation limit. `tests/test_metric_admission.sh` checks the class set and rejects a missing class or changed threshold boundary. `rh_cli staged-normalize` publishes provider/capability-specific field mappings, all five transformation/loss states, explicit unknown semantics, normalizer/output-schema versions, and a configuration SHA-256 over the exact mapping bytes; `tests/test_staged_forge_cli.sh` verifies the digest and capability profiles. In addition, `rh_cli forge normalize` writes a `rh-forge-transformation-report/1` sidecar for each of the five repository normalizers, binding the exact raw payload and canonical output with SHA-256, a versioned provider normalizer configuration digest, output schema/version, and preserved, transformed, inferred, unknown, and discarded field states. `rh_cli ecosystem lookup` also writes a digest-bound transformation sidecar for captured and live ecosyste.ms responses, documenting package-coordinate filtering, provider field allowlisting, and field mappings; `tests/test_ecosystem_lookup_cli.sh` verifies both digests and deterministic replay. `rh_cli depsdev` also writes a digest-bound transformation sidecar for captured and fetched version payloads, including optional-field unknown states and provider fields outside the contract; `tests/test_depsdev_cli.sh` verifies the input/output digests. `rh_cli registry-meta` also emits a digest-bound field mapping for normalized versions, timestamps, source links, dependency counts, explicit unknowns, and discarded provider fields; `tests/test_registry_meta_cli.sh` checks its configuration/input/output digests. `rh_cli inventory` emits a format-specific CycloneDX or SPDX transformation sidecar bound to the exact input, output, and format configuration; `tests/test_inventory_cli.sh` verifies both format mappings and their digests. `rh_cli pylock` also emits a digest-bound mapping for package relationships, environment/group markers, artifacts, unknown root relationships, and discarded unsupported metadata; `tests/test_pylock_cli.sh` verifies its input/output/configuration digests. `rh_cli resolution` emits a digest-bound field mapping for graph-scoped package instances, dependency edges, unresolved requirements, and unknown optional metadata; `tests/test_resolution_cli.sh` verifies the configuration/input/output digests. The single-query `rh_cli osv-query --input` path emits a digest-bound field mapping for query coordinates, normalized vulnerability records, continuation tokens, and omitted response fields; `tests/test_osv_query_cli.sh` checks exact input and normalized-response digests. The graph-batch path also emits a digest-bound mapping for eligible positional queries, vulnerability IDs, skipped nodes, and IDs-only responses; `tests/test_osv_query_cli.sh` verifies the graph, result, and configuration digests for both modes. Transformation sidecars now also cover local artifact-byte observations; remaining non-forge adapters still need path-by-path review.

### 5.3 Essential invariants

```text
unknown != zero
not_applicable != false
account != person
contributor != maintainer
tag != release
package version label != artifact digest
requirement != resolved dependency
first observed != first occurred
graph reachability != exploitability
signature verified != code safe
one-off participation != unhealthy maintenance
```

Each invariant should have a test that would fail if a developer accidentally collapses the distinction.

### 5.4 Acceptance tests

Serialize and deserialize every value/state combination. Reject observed ratios with denominator zero. Verify calendar windows across leap years and month boundaries. Confirm a later-discovered historical fact appears in a retrospective-valid-time query but not in an earlier known-time query.

Create a bundle, reorder input files, replay it, and verify identical analytical outputs. Corrupt one blob and verify the digest mismatch prevents publication. Supply a missing optional input and verify an explicit unavailable/unknown state rather than a success-shaped placeholder.

### 5.5 Exit gate

M00 is complete when the schemas, fixtures, and invariants pass independently of a live source. The team can explain exactly what a metric result means and how it references evidence. No dashboard is required.

## 6. M01 — Safe Git scan and first real report

### 6.1 Goal

Deliver a CLI that scans a local or approved public Git repository, computes a useful baseline from actual history, and writes a replayable report directory.

### 6.2 Initial metric set

Start with approximately 30–40 foundational measurements selected from the architecture catalog. The exact implemented list is explicit, not advertised as the full catalog.

Required categories include revision count and reachability, author and observation times, history coverage, commit/event counts, active months, raw identity count, known automation classification, source-file/manifest presence where safely accessible, and evidence freshness.

Add basic role-neutral concentration only when actor grouping is defined. Do not call raw commit authors “maintainers.” Retention and cross-source identity are deferred to M04.

### 6.3 Work packages

**M01-01: CLI input validation.** Distinguish local paths, public HTTPS remotes, and unsupported schemes. Local-path access is explicitly local; never create a server endpoint that can scan arbitrary server paths supplied by an untrusted remote user.

**M01-02: Safe process runner.** Build one central subprocess wrapper with argument arrays, no shell, explicit environment, output limits, timeouts, memory/process limits where supported, cancellation, and structured exit reporting.

**M01-03: Git acquisition.** Use a bare workspace, no checkout, controlled configuration, explicit ref capture, and strict protocol restrictions. Record shallow and partial state. Support a bounded initial scan and an explicit full-history mode under a separate budget.

**M01-04: Native object parsing.** Read metadata using machine-oriented formats or object APIs. Preserve raw bytes safely when text is invalid. Avoid parsing human-formatted command output whose quoting changes with filenames or locale.

**M01-05: Evidence capture.** Record tool version, sanitized command purpose, source URL, fetched refs, object availability, timestamps, resource use, and errors. Exclude credentials from logs and manifests. The active local slice also retains a NUL-delimited `git ls-tree` path inventory, so snapshot-local documentation and license-presence observations can be replayed without reading ambient files. The retained Git log stores raw author name/email alongside Git's `.mailmap`-normalized author name/email; system/global and configured external mailmap sources are disabled, leaving only the repository's project-local `.mailmap` as identity correction evidence.

**M01-06: Deterministic metrics.** Implement the initial catalog subset as pure functions over a pinned snapshot. Compute raw counts and explicit filtered variants rather than guessing “meaningful commits.”

**M01-07: Reports.** Write `report.json`, `report.md`, and a bundle manifest into a user-selected directory. Include missing-capability explanations for reviews, issue response, permissions, traffic, and global dependents. The report publishes root-level README, CONTRIBUTING, installation, API-reference, governance, code-ownership, release-process, succession-process, security-policy, release-note, and LICENSE/NOTICE presence observations, plus counts of recognized license files, source-extension files, files below `examples/`, files below test directories, recognized CI configuration paths, and recognized-source blob bytes, all backed by retained long-tree evidence; presence is not a quality, execution, security, continuity, or legal-compliance assertion.

**M01-08: Replay.** Recompute the metrics offline from the retained bundle without consulting ambient network state or the current clock. Replay now requires the retained snapshot path inventory alongside the Git log and default-branch count, preventing a missing file-evidence input from being silently replaced by live data.

### 6.4 Hostile fixture cases

Include unusual Unicode names, invalid UTF-8 messages, very large messages, future timestamps, author/committer disagreement, merge-heavy history, rewritten refs, shallow boundaries, missing blobs, symlinks, submodules, attributes defining filters, repository-local configuration traps, and unexpectedly large objects.

Tests must verify that no source-provided command runs. The collector's inability to process a repository within limits is a bounded error, not a reason to bypass isolation.

### 6.5 Expected first report

```text
Project identity: repository-only; no accepted multi-repository mapping
History: complete for requested 365-day window
Observed commits: 240
Raw author identities: 17
Accepted cross-source actor clusters: not configured
Active complete months: 11 of 12
Review events: unavailable from generic Git
Maintainer permission inventory: unavailable
Known downstream projects: not collected
Clone traffic: unavailable
Report replay: verified against retained input bundle
```

The numbers are fixture examples. The report's restraint is part of the acceptance criterion.

### 6.6 Exit gate

Scan the same fixture through a local path and an approved remote fixture server. Verify equivalent history metrics with different transport provenance. Replay results offline. Confirm correct resource termination and explicit unknowns. A reviewer can trace any displayed count to its source population.

## 7. M02 — Durable ingestion and multiple source hosts

### 7.1 Goal

Convert the useful local tool into a durable multi-source service without introducing GitHub assumptions into the domain. Add forge metadata while preserving the generic Git baseline.

### 7.2 Source sequence

Implement GitHub, GitLab, and Forgejo as the initial forge family targets, with at least one controlled self-hosted test instance. Completion of this milestone requires more than three hardcoded domain names: arbitrary approved instance URLs and capability differences must be exercised.

Gitea can follow through shared low-level utilities, but it receives its own connector ID, compatibility fixtures, and capability validation. Similar API shapes do not justify pretending the products are identical. Official source contracts are listed in Architecture references S09–S12.

### 7.3 Work packages

**M02-01: PostgreSQL persistence.** Create source, collection, evidence, event, identity-placeholder, metric, and job tables. Add migration tests and transactional repository methods. Enforce source-scoped uniqueness. The target contract now lives in `db/migrations/001_initial.sql`: it covers the architecture table groups, visibility-scoped evidence, source-native uniqueness, bitemporal checks, adjacency/evidence/metric indexes, fenced lease claim/heartbeat/finish functions, and cursor-advancing functions that refuse partial pages and require a source-matched running job whose input manifest names the same collection run, with the current unexpired fencing token; heartbeat, finish, and page writes reject expired leases. The page and job rows stay locked through commit. `rh_claim_next_job` can claim the highest-priority eligible job or target one collection job without touching another queue entry. The `rh_begin_collection_run` function atomically creates or verifies a source configuration and its initial collection run; `rh_enqueue_collection_job` atomically queues an immutable run binding using the source visibility and exact retries do not create duplicate jobs. The `rh_commit_collection_page_events` function validates bounded event, typed-subject, and source-scoped actor arrays, registers or verifies their immutable metadata, absorbs source-native event duplicates, and commits entities, accounts, event rows, page metadata, and cursor advancement atomically; a malformed row or metadata conflict rolls back the transaction. The `rh_commit_staged_collection_page` function atomically preserves bounded raw object text and commits its complete/empty page metadata and cursor under the same lease fence. The idempotent `rh_register_evidence_object` function accepts bounded SHA-256 metadata and rejects identity or immutable-metadata conflicts. The `begin_collection_run`, `enqueue_collection_job`, and targeted-claim CLI operations bind source/run/job metadata through `rh_cli postgres`; `register_evidence` acquires the evidence-root guard before reading and verifying a content-addressed blob, computes SHA-256, and binds only the resulting metadata to PostgreSQL under the same guard, while the blob itself remains in the configured evidence store. `tests/test_migrations.sh` validates the migration vocabulary and safety invariants, while `tests/test_migrations_live.sh` applies the migration to an ephemeral PostgreSQL 16 container and exercises source/run and enqueue replay/conflicts, enqueue/targeted-claim/finish lifecycle, evidence replay/conflict, subject/actor creation and conflict, run-mismatched, stale-token, and expired-token page rejection, expired-job-finish rejection, terminal finish, complete-only cursor advancement, duplicate-event replay, duplicate-page rejection, malformed-page rollback, bounded raw-page persistence/replay/rollback, and stale-token raw-stage rejection when `RH_PG_MIGRATION=1`; it also kills PostgreSQL during an uncommitted event/page/cursor transaction, verifies crash recovery leaves no partial rows, and commits the exact replay once after restart. `src/rh_postgres.elisa` provides parameter-bound, timeout-bounded methods for source/run initialization, job enqueue and general or targeted collection claim, evidence registration, normalized and staged page commits, and PostgreSQL heartbeat/finish, distinguishing new registrations/commits/jobs, duplicates, claimed/empty queues, and current/stale tokens. `rh_cli postgres` exposes those operations through `src/rh_postgres_report.elisa` and versioned `rh-postgres-command/1` inputs; it reads connection settings only from `RH_DATABASE_URL` and emits `rh-postgres-result/1`. `tests/test_pg_adapter.sh` exercises the dynamic `libpq` ABI with a fake library, `tests/test_postgres_cli.sh` covers the command path and failure gates, and `tests/test_pg_adapter_live.sh` verifies source/run setup and the adapter against PostgreSQL when `RH_PG_ADAPTER=1` and `libpq` is installed. Shared-blob distribution and live provider acquisition/authentication remain open. `rh_cli ingest --postgres` accepts explicit normalized or staged pages, and `rh-postgres-legacy-ingest-input/1` bridges legacy filesystem replay attempts into staged pages with optional `--root` evidence registration.

**M02-01 lifecycle increment:** `rh_finish_collection_job` now closes a collection run and its owning PostgreSQL job in one transaction. It requires the source-matched run binding and a current unexpired token, validates the terminal run/job/completeness combination, and records bounded coverage details and attempt outcome. Generic `rh_finish_job` and both page-commit functions enforce their job kind, so collection jobs cannot bypass run finalization and other job kinds cannot write collection pages. The migration rehearsal checks expired rejection with no partial state change, successful atomic finalization, and terminal replay fencing; the CLI adapter exposes `finish_collection_job`.

**M02-01 normalized-page execution increment:** `rh_cli ingest --postgres [--root <store-dir>] --input <file> --out <file>` accepts `rh-postgres-ingest-input/1` with bounded, already-normalized pages. It parses and checks all page envelopes and embedded event/subject/actor records, verifies page ordering, stable scope, UUIDs, second-resolution ISO-8601 timestamps with `Z` or `±HH:MM`, declared event counts, and the lease window before opening libpq; then it initializes the run, enqueues and targets its job, commits each page through the fenced event-page transaction, and finalizes the run and job. When `--root` is supplied, optional `evidence_objects` descriptors bind verified blobs under `<root>/evidence` to PostgreSQL evidence UUIDs. The evidence-root guard stays held while all named blobs are verified, with a 64 MiB aggregate cap, before SHA-256 calculation and metadata registration. Missing or corrupt blobs, invalid UUIDs or names, and structurally malformed descriptors fail before database access; PostgreSQL validates timestamp syntax and immutable-metadata conflicts during registration. `rh-postgres-ingest-result/1`, the fake-libpq CLI test, and the opt-in live adapter rehearsal cover both registered and pre-registered evidence. The same path accepts partial, failed, and canceled collection runs with explicit coverage details and only commits supplied successful complete/empty pages; incomplete runs may contain no durable pages. The migration's valid job/run/completeness pairs are checked before connection, and the result reports the terminal run status. Provider acquisition and normalization remain separate. The legacy `rh-ingest-input/1 --root` flow remains a filesystem conformance replay; its raw pages enter PostgreSQL only through the explicit bridge described below.

**M02-01 staged-page CLI increment:** The same PostgreSQL ingest input accepts a page with `record_mode: "staged"` and a bounded `staged_records_json` array, while requiring its canonical event, subject, and actor arrays to be empty. The adapter validates labels, raw JSON objects, per-record and aggregate byte caps, record counts, page order, timestamps, and run metadata before connecting; it then calls `rh_commit_staged_collection_page` and marks the page as staged in `rh-postgres-ingest-result/1`. `record_mode` is omitted from normalized pages for output compatibility. The fake-libpq adapter and CLI fixtures verify parameter binding, raw-stage dispatch, exact result shape, and malformed/count-mismatch rejection before database access. The separately replayable GitHub event normalizer that consumes those committed records is described below.

**M02-01 staged-source-record increment:** `staged_source_record` preserves raw JSON text by collection run, page, and ordinal, with an opaque collector label kept separate from source-native event identity. `rh_commit_staged_collection_page` validates each record as a JSON object, caps one payload at 1 MiB, the page's raw payloads at 4 MiB, and the serialized staging envelope at 8 MiB, then stages all rows in the same lease-fenced transaction as complete/empty page metadata and cursor advancement. Duplicate pages are absorbed, while partial pages, stale leases, malformed payloads, and over-limit pages leave no staged rows or cursor movement. The static migration check and opt-in PostgreSQL rehearsal cover exact raw-text preservation, replay, malformed/oversized-input rollback, complete-only advancement, and stale-token rejection. This implements the paper's staging-before-normalization boundary for the persistence layer. The legacy filesystem replay now bridges into this writer through `rh-postgres-legacy-ingest-input/1`, requiring a matching `rh-ingest-result/1` input SHA-256 and cursor-advance report plus explicit PostgreSQL run metadata and committed-page cursor/timestamp bindings; only committed complete/empty attempts are staged. `tests/test_pg_adapter_live.sh` now also composes the real filesystem crash/retry replay, derives the bridge from its cursor report, commits the staged page through libpq to PostgreSQL, and checks exact raw payload, cursor page, and terminal run/job state; this remains an opt-in environment-dependent gate. `rh_cli staged-normalize --input <file> --out <file>` accepts versioned GitHub issue, proposal, review, and release envelopes; GitLab issue, merge-request, and release envelopes; and an allowlisted Gitea/Forgejo/Bitbucket event envelope. Gitea and Forgejo support issues, proposals, and releases; Bitbucket supports issues and proposals. Every form requires an explicit opaque-label-to-capability binding and committed complete/empty pages with contiguous record ordinals; GitHub review inputs additionally require an explicit pull-request scope. The adapter passes raw objects through the existing `rh-forge-events/1` normalizer. Its `rh-postgres-staged-normalize-result/1` output binds exact input bytes by SHA-256, publishes the exact mapping profile plus its configuration digest, and carries each final normalized event's source page and ordinal; duplicate replacement retains the later row's provenance so evidence lookup remains tied to the winning observation; the page's source page evidence ID is copied when present.

**M02-01 staged canonical-write-back increment:** `staged_normalization` records an immutable input/configuration/output digest manifest. The additive `commit_staged_normalization` operation on `rh-postgres-command/1` accepts a staged normalizer result, hashes the exact normalized event-array bytes, and calls `rh_commit_staged_normalization` through bound libpq parameters. The transaction requires a succeeded complete/empty run, rejects failed pages and duplicate object identities, and verifies each event's page number, ordinal, evidence UUID, and retained staged row before writing an observation event and its typed subject. Canonical object IDs retain both the page's scope hash and provider-native ID so identical issue numbers in separate repository scopes stay distinct. Exact replays return `duplicate`; PostgreSQL checks the submitted event payloads against the committed canonical rows as well as the digest manifest, while altered output under an existing run/input/configuration key fails without changing canonical rows. The command preflights UUIDs, digests, normalizer version, event kinds, timestamps, and provenance before connecting; the database repeats the durable lineage and completeness checks. `tests/test_postgres_cli.sh` and the fake-libpq adapter cover command validation, parameter order, output digest, commit, and replay, while `tests/test_migrations_live.sh` applies the real migration and verifies evidence mismatch, partial-run, changed-output, forged-digest, scope-isolation, and exact-replay behavior. Provider-specific normalization beyond the current forge adapter and shared-blob distribution remain open.

**M02-01 staged-normalize direct PostgreSQL increment:** `rh_cli staged-normalize --postgres` now feeds the generated normalization result directly into the existing `commit_staged_normalization` PostgreSQL operation and writes its `rh-postgres-result/1` commit/replay response to `--out`. Without the flag, the command retains its normalizer-result output contract. The CLI preflights and normalizes before requiring `RH_DATABASE_URL`; fake-libpq coverage checks commit, replay, canonical result bytes, and malformed-input rejection before database access in `tests/test_postgres_cli.sh`.

**M02-02: Content-addressed server store.** The local filesystem store stages each blob in an exclusive same-directory temporary file and publishes it with an atomic no-clobber hard link; `tests/test_store_cli.sh` races twelve identical puts and verifies one complete object with no staging residue. A per-root advisory guard serializes local blob publication and cleanup across processes, and `register_evidence` holds it through blob verification and the PostgreSQL insert. Digest verification blocks publication from missing or corrupted blobs. The `evidence_references` PostgreSQL command performs a fixed read-only scan capped at 100,001 evidence rows and reports valid content-addressed keys, malformed-key count, and truncation; `tests/test_postgres_cli.sh` covers its result, query failure, and oversized-result rejection. The opt-in PostgreSQL rehearsals execute the fixed query, verify valid/malformed-key classification, and confirm the 100,001-key response is flagged as truncated within the adapter's 4 MiB bound (the full CLI rehearsal also requires local `libpq`). The database-backed `evidence_gc` command discovers canonical blob names directly from the guarded evidence directory, ignores lock/staging/metadata files, caps one pass at 50,000 objects, and uses validated, sorted reference snapshots for bounded binary lookup. It fails closed on scan errors, over-cap roots, malformed or unsorted keys, truncated/oversized snapshots, and unavailable queries, then holds the root guard through unlink and directory sync. Its CLI test confirms referenced content survives, an orphan is removed and reported, unrelated root files remain, and incomplete snapshots leave the orphan untouched. The local cleanup primitive validates complete name lists before deletion, rejects path traversal, counts successful unlinks, syncs the evidence directory, and tests malformed input, no partial deletion, and filesystem failure. Local root-to-root blob distribution validates each manifest name and reuses atomic no-clobber publication; repeated restore is idempotent and a conflicting destination object is preserved. Separate hosts can exchange a bounded `rh-evidence-transfer/1` package through `ops export` and `ops import`: export requires a sorted backup manifest and verifies every blob, import validates framing and every FNV content address before publishing any object, and replay is safe after partial filesystem failure. `tests/test_store_cli.sh` round-trips binary bytes across isolated roots and proves a damaged later record publishes none of the earlier valid objects. This package detects corruption but does not authenticate the sender or encrypt contents; use a trusted transfer channel and retain the open M07-04 signing gap.

**M02-03: Job leasing.** Implement scheduling, claims, fencing tokens, heartbeats, retries, cancellation, per-source quotas, and dead-letter handling. Keep external operations outside long database transactions. Generic job leases retain terminal completion; the filesystem ingest resource lock now releases into a reusable `available` phase and increments its fencing token for each later collection.

**M02-03 reclaim increment:** PostgreSQL lease reclamation now closes each unfinished prior attempt as `lease_expired` before creating the next fencing-token attempt. The PostgreSQL 16 rehearsal drives an actual reclaim and checks the old attempt outcome, new token, and lease deadline.

**M02-04: Capability manifests.** Every connector declares supported operations, source/version constraints, auth scopes, pagination, time precision, rate-limit handling, and historical limitations. Capability probes return explicit unsupported/unauthorized states. The versioned manifest schema now requires source/version constraints, history limits, a rate-limit policy, source documentation, and a contract-check date; it constrains capability states and verifies authentication-scope and documentation entries are strings. `tests/test_connector_cli.sh` compares every capability in the five implemented forge manifests with `rh_cli connector check`, including GitLab's explicit `unauthorized` traffic state. Official API version docs corrected GitHub's current supported version and the Gitea/Forgejo REST path declarations; manifests retain source links and a verification date. The GitLab manifest records the `read_api` scope, `members/all` route documentation, and the live collector pagination/resume bound. Native VCS and release-feed manifests also declare their source constraints and whether rate limiting applies. Optional GitHub REST authentication for `api.github.com` is available through `RH_GITHUB_TOKEN` on the repository normalizer and bounded live issues, pull-request, release, pull-request-scoped review, and collaborator-permission collection; the latter requires an explicit token and retains authenticated repository scope and page-completeness state. An incomplete permission snapshot resumes from its validated `page=N` cursor with `--resume-from`, merging provider IDs and retaining each declaration's observation time. A GitHub-only traffic capability probe retains fixed-route request evidence and reports observed/unauthorized/rate-limit and inconclusive access states without counts. `rh_cli connector traffic-observe --github-repo owner/repo --captured-at EPOCH --input <response.json>` normalizes caller-supplied response bytes into `rh-github-traffic-observation/1`: it retains the reported rolling-window totals and ordered UTC daily buckets, caps the body and bucket count, rejects invalid/duplicate/out-of-order/future dates and invalid counts, and hashes the exact response bytes. Each result is one non-additive 14-day snapshot; normalization alone does not authenticate the supplied response. GitHub documents the [traffic route](https://docs.github.com/en/rest/metrics/traffic) for repositories with write access; a 403 can also signal a rate limit ([rate-limit guidance](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api)), and a 404 can conceal a private repository ([REST API troubleshooting](https://docs.github.com/en/rest/using-the-rest-api/troubleshooting-the-rest-api)), so neither is called unsupported. The explicit `connector probe --all` matrix performs one-item probes for issues, pull requests, and releases plus the existing traffic route, retains separate URL/body/status/error evidence for each, and reports route access without traffic counts or complete-snapshot claims ([issues](https://docs.github.com/en/rest/issues/issues), [pull requests](https://docs.github.com/en/rest/pulls/pulls), [releases](https://docs.github.com/en/rest/releases/releases)). `connector probe --review-pull N` probes the documented one-item review-list route for that explicit pull request, records the route status and separate raw evidence in `rh-github-review-capability-probe-result/1`, and does not claim review-history completeness. `connector probe --collaborators` requires `RH_GITHUB_TOKEN`, requests one collaborator row, retains the potentially identifying raw response only in local evidence, and emits `rh-github-collaborator-probe-result/1` with access status but no account fields or completeness claim; 403/404 remain inconclusive. `rh_cli connector probe --gitlab-project <group/path> --all` adds fixed one-item issues, merge-request, and release route probes under `rh-gitlab-capability-matrix/1`; project slashes are URL-encoded, optional `RH_GITLAB_TOKEN` is sent only to `gitlab.com` through curl stdin config, and each route preserves local raw evidence while mapping provider outcomes to shared coverage states. GitHub and GitLab capability matrices are now covered; probes for the other forge providers remain open. Bounded repository-wide review traversal is implemented under M02-05. (P34; [pull-request reviews](https://docs.github.com/en/rest/pulls/reviews).)

**M02-05: Provider adapters.** Normalize repositories, issues, proposals, review events, releases, and current-state snapshots. Preserve provider-native status fields for audit while mapping supported canonical semantics. The captured-event path accepts GitHub, GitLab, Gitea, Forgejo, and Bitbucket issues/proposals through `rh-forge-events-input/1`, emits `rh-forge-events-result/1`, preserves provider-prefixed native IDs and status strings, separates attempted, normalized, duplicate-replacement, unique, and rejected counts, and distinguishes missing `unsupported` capabilities from explicitly `not_attempted` work. `rh_cli forge events --github-repo owner/repo` fetches GitHub issue, pull-request, and release pages from fixed API routes, with a 1–10 page cap per capability, 100-record page size, 3 MiB aggregate response bound, numeric page cursors, and adjacent raw JSON/URL/status/error evidence. `--review-pull N` separately fetches bounded review pages for one pull request and identifies that scope in the result; `--review-page N` resumes at a returned numeric review cursor under the same explicit repository and pull-request arguments, with the same page and byte caps. Each invocation reports only its fetched segment. Unrelated capabilities remain `not_attempted`. Pull-request rows returned by the issues route are filtered before issue counts, and draft releases are excluded from published-release counts. The collector uses the manifest-pinned `X-GitHub-Api-Version`; optional `RH_GITHUB_TOKEN` reaches only `api.github.com` through curl's stdin config and stays out of arguments and evidence. Repository-wide review traversal is available through `--review-repository`: each invocation reads one pull-list page of 1–10 PRs, fetches up to 1–10 review pages per PR under a shared 3 MiB response cap, and records pull-list plus per-PR review cursors. `--resume-from` accepts only the same repository and result shape, finishes pending review pages before advancing the pull list, and associates each normalized review event with its PR number. Each result contains only the current segment. GitHub sorts the pull list by update time, so page completeness records traversal progress but cannot establish an atomic repository snapshot while the list changes; role inference remains separate.

**M02-06: Incremental fetch and reconciliation.** Use provider cursors or updated-since filters where available, with overlap windows for late updates. Add periodic complete reconciliation within budget. `rh_cli snapshot-reconcile` now reads `rh-snapshot-reconcile-input/1` and emits a bounded current-state projection: only `complete` or successful `empty` acquisition marks unseen IDs absent and refreshes last-success time, and only inside its exact source/capability/scope tuple; partial, failed, and unsupported acquisition retains unseen IDs as unconfirmed and cannot refresh last-success time. Observed IDs remain explicit, duplicate IDs fail closed, and the deterministic report preserves source-native identity. Webhooks are a freshness accelerator, not the only source of state; live provider collection and durable database projection remain open.

**M02-07: Coverage propagation.** A failed review fetch marks review-derived metrics partial or stale, not the whole project inactive. `rh_cli ingest` now appends one aggregate coverage status to `<root>/sources/<source>/coverage/<capability>.interval` for the pinned collection interval, after page processing under the active lease. The result exposes the persisted capability state and `refresh_last_success`: only an explicitly collection-complete run with fully committed complete/successful-empty pages yields `observed` and refreshes the last-success time; mixed, undeclared, or unreplayed work is `partial`, and failure-only authorization, unsupported, and transient/rate-limit runs stay `unauthorized`, `unsupported`, or `unavailable`. A recovered crash-before-cursor retry clears its pending page before reporting coverage. PostgreSQL normalized ingest now persists caller-supplied partial, failed, and canceled coverage with the collection run after committing only complete/successful-empty pages; omitted failed pages do not advance the cursor, and an incomplete run can have no durable pages. GitHub probe results preserve each provider status and HTTP code while mapping `coverage_state` conservatively: valid 200 arrays are `observed`, malformed 200 bodies are `partial`, 401 is `unauthorized`, and ambiguous 403/404 plus 429/transport failures are `unavailable`; GitLab capability-matrix results also map per-route access states conservatively (`observed`, `partial`, `unauthorized`, or `unavailable`); coverage mappings for other provider routes remain open.

**M02-08: Provider contract tests.** Exercise pagination, duplicates, deleted objects, changed schemas, authorization errors, empty successful responses, rate limits, and mutable current state. The captured forge-event adapter now replaces duplicate page observations by `(capability, provider-native-id)` while retaining the later status/timestamps, and carries validated opaque per-capability cursor/completion state through the result without interpreting or advancing it. `test_forge_events_cli.sh` distinguishes explicitly empty from missing/unsupported capabilities, ignores additive provider fields without changing canonical output, and covers malformed records, provider identity, duplicate replacement, and pagination state; `test_ingest_conformance_cli.sh` covers authorization and rate-limit failures; `test_snapshot_reconcile_cli.sh` covers deletion inference only after complete or successful-empty snapshots and preserves unseen IDs after incomplete acquisition. Controlled-instance rehearsals and live provider schema-change fixtures remain open.

**M02 Bitbucket Cloud capability increment:** `rh_cli connector probe --bitbucket-repo <workspace/repo> --all` issues fixed `pagelen=1` requests to the documented repository issue and pull-request resources, validates Bitbucket’s paginated `{values: [...]}` envelope, and keeps response rows in local evidence. The result explicitly marks releases unsupported: the Cloud API documents repository downloads, not a release-list resource. `rh-bitbucket-capability-matrix/1`, the connector manifest, and `tests/test_connector_cli.sh` preserve this provider distinction and reject traversal before transport. This is a bounded access probe, not an atomic snapshot or a substitute for paginated ingestion. The official route/source references are the Atlassian Cloud REST overview and issue-tracker documentation.

**M02-09: Research-driven ingestion conformance.** Pin the collection-start watermark and advance it only after durable publication under the active lease generation. Test updates arriving during collection, backdated events, overlap and reconciliation. `rh_cli ingest` reads the schema-checked `rh-ingest-input/1` fixture, exercises event-before-cursor replay, overlapping-interval event deduplication, capability-interval persistence, and lease fencing; `rh_cli snapshot-reconcile` separately projects current-state snapshots. A complete or successful-empty snapshot clears only its supplied source/capability/scope; failed, unsupported, or partial acquisition cannot clear unseen records or refresh last-success age. The captured provider adapter reports per-capability attempts, successful normalization, duplicate replacements, unique records, and rejection counts separately from successful acquisition pages. Compare one candidate Perceval backend against direct collection under matched scope before adoption. (Paper §§6, 8, 14, 18.)

### 7.4 Traffic handling

Implement the capability shape now even if no owner-authorized data source is available. Return `unauthorized` or `unavailable` correctly. Do not scrape an inaccessible traffic page or estimate clone counts from stars.

GitHub's documented traffic API has a 14-day reporting window and access restrictions. Overlapping responses must be stored as interval observations, not added into inflated totals. [P01]

### 7.5 Idempotency acceptance sequence

Fetch page A and crash before database commit. Retry and obtain exactly one canonical copy. Fetch page B and crash after commit but before acknowledgment. Retry and obtain exactly one canonical copy. Expire a worker lease, start a replacement, and verify the old worker cannot publish after losing its fencing token.

Deliver the same webhook three times and reorder two updates. Confirm the final source-state projection is correct and no duplicate contribution events inflate metrics.

### 7.6 Exit gate

The service ingests at least two different live or controlled provider implementations plus a generic Git source. The same domain report works for all of them. Missing data is localized to capabilities, and source outages do not create project-abandonment findings.

## 8. M03 — Package identity, dependency evidence, and advisory matching

### 8.1 Goal

Build the package/version/artifact foundation and a correct, explicitly bounded dependency graph. Start with two ecosystems whose semantics are implemented and tested, rather than shallow support for ten formats.

### 8.2 Initial ecosystem proposal

Use Cargo and npm as the reference first pair, subject to a bootstrap decision. They provide materially different version, feature, and dependency-context cases. The objective is to validate the abstraction, not favor those ecosystems permanently.

Use each ecosystem's official manifests, lockfile formats, and version semantics when implementing. Pin supported format revisions. A generic SemVer library is not assumed sufficient for every registry or package format.

### 8.3 Work packages

**M03-01: Package coordinates.** Parse and preserve Package URLs where supported, registry identity, namespace, normalized names, raw names, and ecosystem-specific versions. Add collision fixtures for identical names in different registries. Cargo lock nodes, including sparse registry sources, and npm `resolved` entries now retain source locators internally and emit SHA-256 source fingerprints instead of exposing raw locators. PEP 751 package index URLs likewise emit only an `index_sha256` fingerprint, preserving index association without publishing the URL. Cargo lock dependencies resolve by exact name/version/source identity; the Cargo registry collision and npm nested-package fixtures prove equal name/version coordinates from distinct sources stay distinct.

**M03-02: Artifact identities.** Store expected and observed digests independently from version labels. Model multiple artifacts per package version and changed bytes under the same label. The graph now stores artifact records separately from resolution nodes; multiple records may reference one package node, and each record carries expected/observed digests plus `match`/`changed`/`unknown` state. Cargo/npm/Go parsers populate expected digests from lockfile evidence; Go `h1` records must be canonical Base64 SHA-256 before they attach to a node. NuGet v1 lock `contentHash` values are retained as `nuget-sha512:` expected content hashes; they are not compared to raw `.nupkg` bytes by this verifier. `go.sum` `/go.mod` entries are retained as separate `go_mod` artifacts and verified against a supplied `go.mod` using Go's one-file `h1` dirhash. Module ZIP artifacts are verified using Go `HashZip`/`Hash1` semantics over sorted entry names and uncompressed file contents; the bounded ZIP reader validates CRC32 and caps archive bytes, total expanded bytes, entry count, and filename storage. ZIP64, split, encrypted, duplicate-name, malformed, and over-limit archives fail closed. The ZIP structure and `h1` summary remain in Elisa; the OS-provided zlib dependency handles raw DEFLATE and CRC32 only; see [P19], [P20]. `rh_cli artifact-observe` hashes user-supplied local Cargo archive bytes with SHA-256, npm tarball bytes with SHA-256/SHA-384/SHA-512 SRI Base64, Go `.mod` files, or Go module ZIPs, then emits ecosystem-specific observation contracts bound to the graph digest and artifact ID; no archive is extracted or executed. It rejects graph files over 8 MiB before reading them and caps input files at 64 MiB. Go `.mod` and ZIP verification emit separate `rh-go-mod-observation-result/1` and `rh-go-zip-observation-result/1` contracts, bound to the same immutable graph and artifact identity. npm integrity metadata may contain multiple SRI tokens: this verifier selects SHA-512 when present, otherwise SHA-384 when present, otherwise SHA-256, and matches if any token for the selected algorithm validates while retaining the original expected string. It splits each token at the first `?`, validates the digest, ignores reserved option expressions after validating their printable-ASCII syntax, and preserves the full original integrity value in the observation; see [P18]. The PEP 751 audit also retains expected algorithm/value pairs, any declared `size`, and explicitly UTC `upload-time` values for bounded wheel, sdist, and archive entries; upload time remains source event time, distinct from observation time. Archive `subdirectory` values retain package-root context. It keeps multiple artifacts distinct and represents URL/path locators only by SHA-256 fingerprints; complete artifact metadata remains open. `rh_cli pylock-observe` consumes that audit plus caller-supplied local bytes and emits `rh-pylock-artifact-observation-result/1`, bound to the exact audit bytes and artifact ID. It compares declared size independently from SHA-256, SHA-384, and SHA-512, reports a size or digest mismatch as `changed`, and keeps unknown algorithms in `partially_verified` or `unsupported` states; it does not open or extract archives. This observation is a separate sidecar, so the audit and source graph remain immutable. Other ecosystems and integrity strings without SHA-256/SHA-384/SHA-512 remain unsupported by this verifier. The dependency digest-coverage metric counts expected values and does not claim byte verification. `rh_cli artifact-observe` emits a digest-bound transformation sidecar for the graph, local artifact bytes, exact observation output, and versioned configuration; it records preservation, digest transformation, comparison, archive/path discard, and unsupported provider metadata without publishing local paths or archive contents (`tests/test_artifact_observation_cli.sh`). `rh_cli pylock-observe` also emits a digest-bound transformation sidecar for the exact PEP 751 audit, caller-supplied bytes, versioned configuration, and normalized observation; it documents identity/hash preservation, byte hashing and comparison, filesystem-path/archive-content discard, and unsupported hash algorithms, with a test that checks all digests and path privacy (`tests/test_pylock_cli.sh`).

**M03-03: Manifest parsers.** Extract declared direct requirements, scope, optional conditions, and source spans without executing package scripts. Store unsupported expressions intact. npm `peerDependenciesMeta` now retains `optional: true` through both resolved peer edges and unresolved peer requirements; the graph’s optional flag is additive and remains separate from peer scope.

**M03-04: Lockfile parsers.** Produce resolved graphs for supported contexts. Preserve multiple versions of one package, workspace members, registry aliases, local/path dependencies, Git dependencies, and unresolved external conditions. Cargo lock dependency IDs are filtered by their exact locked version and source when present; absent matches remain unresolved instead of falling through to a same-name candidate. The bounded parser accepts unversioned Cargo files with a separate `[root]` entry and `[[package]]` records, Cargo lockfile versions 3/4, npm's legacy version-1 dependency tree plus package-map versions 2/3 from either `package-lock.json` or `npm-shrinkwrap.json`, Yarn Classic lockfile v1's exact descriptor selectors and dependency scopes, pnpm lockfile version `9.0`, and NuGet `packages.lock.json` format version 1 with up to 64 target frameworks and 10,000 total package entries. Node lock selection is `npm-shrinkwrap.json`, `package-lock.json`, `pnpm-lock.yaml`, then Yarn Classic `yarn.lock`; npm's shrinkwrap precedence follows npm's specification. The pnpm adapter accepts one `.` importer, exact importer `version` resolutions, package metadata and snapshot entries, runtime/dev/optional scopes, and peer-suffixed snapshot paths. Each full snapshot path maps to its own graph node while its peer suffix stays private and the published version remains the package version. Workspace/path/Git locators remain context-unresolved; multiple importers, unsupported aliases, unknown top-level/package fields, malformed records, and other pnpm revisions fail closed. Pnpm source URLs are fingerprinted and integrity values remain artifact evidence. Yarn locators are fingerprinted, integrity strings retained, and Git/path selector kinds preserved, while Berry revisions, npm aliases, malformed records, and unknown fields fail closed. Inline Cargo checksums and historical `[metadata]` checksum entries are validated as 64-digit SHA-256 values; legacy entries attach only to a unique registry package matching exact name, version, and source, while unrelated metadata remains unsupported. NuGet uses one graph root and emits framework-specific package nodes; each target's direct and transitive edges stay within its own closure, with `target_framework` retained on every package node. Direct packages create root edges, and each locked package dependency resolves by case-insensitive package ID plus exact resolved version. NuGet content hashes are retained as expected artifact values without claiming raw archive verification. Other format versions, duplicate IDs or target-framework names, malformed dependencies, resource-limit excess, and unsupported fields fail closed. Unknown Cargo/npm/NuGet/pnpm revisions and revision/layout mismatches fail closed. (Official format references [P16], [P17], [P21], [P22], [P26], [P27], [P32], [P33].)

The `rh_cli pylock --input <pylock.toml> --out <file>` path emits a bounded PEP 751 audit projection under `rh-pylock-audit/1`, bound to the exact input bytes by SHA-256. It preserves package names, versions, package markers, `requires-python`, and package-to-package references expressed by name plus optional version. The top-level `environments`, `extras`, `dependency-groups`, and `default-groups` string arrays are preserved in declaration order without evaluating markers or selecting an installation context. For supported table and inline-table forms of wheel, sdist, and archive entries it also retains artifact names, hash algorithm/value pairs, optional byte sizes, explicit UTC artifact `upload-time` values retained as source event times, archive `subdirectory` values retained as package-root context, and SHA-256 fingerprints of URL/path locators without publishing raw locators. `[packages.vcs]` and `[packages.directory]` source records retain exact VCS commit IDs, optional requested revisions, directory editable flags (including the default `false`), source subdirectories, and URL/path fingerprints without publishing raw locators. VCS, directory, and archive dependency selectors narrow package candidates using the source fields they supply, and their locators are emitted only as fingerprints. A package-level index URL is retained only through its `index_sha256` fingerprint. Package `attestation-identities` retain their required `kind`, publisher-specific string fields, and inline string-valued `claims` members as recorded; the audit treats these as identity claims and does not verify attestations. Other claim value types remain unsupported and fail closed. References resolve only when the supplied name/version/source fields identify one package entry; missing, ambiguous, and unsupported source-specific references remain distinct. PEP 751 states that dependency links are informational and does not encode project-root requirements, so the report is rootless and is not accepted as `rh-dep-graph/1` or OSV input. `rh_cli pylock-observe` verifies caller-supplied bytes against SHA-256, SHA-384, and SHA-512 values from one audit artifact and emits a separate `rh-pylock-artifact-observation-result/1` sidecar bound to the exact audit bytes and artifact ID; unknown algorithms remain unsupported and the command never opens or extracts archives. Marker evaluation, environment/group selection, unknown dependency selector fields, remaining artifact metadata, and complete TOML validation remain open; coverage reports projected artifact hashes separately from complete artifact projection. Source-reported upload time is not capture time, following the paper’s §14 distinction between source event time and observation time. Project manifest integration and full lockfile coverage remain open. ([PEP 751](https://peps.python.org/pep-0751/); research paper §16.)

**M03-05: Registry enrichment.** Collect version metadata, publication times, source links, deprecations/yanks, and declared dependencies where available. Package source links are mapping assertions, not trusted project identity. The canonical registry report now counts deprecated, explicitly non-deprecated, and unknown versions separately and retains bounded source notices. npm's empty deprecation message means the version was undeprecated; a non-empty message marks that version deprecated [P24]. NuGet registration catalog entries retain the deprecation message when present [P25]. Other adapters preserve unknown rather than infer a negative state when they provide no deprecation signal. Each report is tied to the exact input bytes by SHA-256 and records local versus captured-URL origin; URL locators are represented by a one-way digest, and inputs are capped at 4 MiB. `source_link` and `source_link_kind` distinguish repositories, homepages, project URLs, and source-code links; the legacy `repository` value remains an alias. `schemas/registry-meta-result.schema.json` and a golden output fixture validate the public result token.

**M03-06: Graph storage.** Build outgoing and incoming adjacency for exact resolved edges. Add bounded breadth-first traversal with deduplication, cycle handling, and truncation metadata.

**M03-07: Inventory interchange.** Import CycloneDX 1.4/1.5/1.6 and SPDX 2.3 with schema validation. Store importer completeness and source provenance. A syntactically valid inventory may still be incomplete. The CycloneDX importer retains per-composition aggregate assertions and separates dependency-scoped `complete`, `incomplete`, `unknown`, and `not_specified` counts; it does not upgrade those scoped assertions into a claim that the whole BOM is complete. Both formats carry the exact input SHA-256 and an origin kind; URL captures also carry a one-way URL digest, while raw locators and local paths remain unpublished. Inputs and composition reference arrays are bounded. `schemas/inventory-result.schema.json` plus deterministic observed goldens for every declared supported format version and an unsupported-version golden validate the `rh-inventory/1` output contract. (Composition meaning: [P23].)

**M03-08: OSV integration.** Query supported package/version or commit contexts; preserve advisory source IDs, alias assertions, affected ranges, withdrawal status, and feed freshness. Record unknown when version matching is unsupported. The bounded `rh_cli osv-query` path accepts `rh-osv-query-input/1` for one package plus the supplied version string, or `/2` for a full 40/64-hex Git commit hash, then POSTs to the fixed OSV `/v1/query` endpoint. Its default one-page mode retains the `/1` result contract; opt-in `--continue-pagination` emits `rh-osv-query-result/2`, follows at most four pages, retains every page's request/raw response/status/stderr and SHA-256 digest, and combines full advisory records for the existing offline matcher. If page four still returns a continuation value, the result is explicitly partial and that value is retained. Commit-query results remain separate context evidence because Git-range matching is not implemented in the dependency graph. OSV documents package-version matching as fuzzy, so the submitted coordinate does not guarantee an exact server-side match; capture time does not establish feed freshness.

The explicit `rh_cli osv-query --graph <rh-dep-graph/1> --out <dir>` path now submits at most 64 eligible versioned nodes in graph order to the fixed `/v1/querybatch` endpoint. It skips path/Git and versionless nodes and counts eligible nodes omitted after the cap. The `/1` batch result retains the exact ordered request and raw response plus a query-to-graph-node index map and reports per-query advisory ID/modification summaries. Opt-in `--continue-pagination` emits `/2`, follows only queries with per-result cursors for at most four rounds, and retains each page's request/raw response/status/stderr/digest with original query indexes. A cursor left after round four leaves a saved remaining request and partial state. Opt-in `--hydrate-advisories` emits `/3` and fetches full records for distinct IDs observed in retained batch pages through the fixed `/v1/vulns/{id}` route. IDs are restricted to the OSV path-safe alphabet and checked against each returned record; each attempted request, raw response, status, stderr, and response digest is retained. Hydration is capped at 64 distinct records, 32 MiB of combined record bodies, 120 seconds total, and 10 seconds per record request (plus the transport's per-response byte cap); any invalid, omitted, failed, timed-out, or unfinished work marks coverage partial. The resulting `osv-query-hydrated-response.json` has the full-record `{"vulns":[...]}` shape accepted by the offline matcher, while its result envelope states whether hydration is complete. It covers only IDs returned for submitted nodes and captured rounds, so skipped/over-cap nodes and incomplete lockfile coverage remain explicit. OSV documents server-side version matching as fuzzy, and capture time does not establish feed freshness. (Paper §10; [P13], [P14], [P15].)

**M03-09: Optional data enrichment.** Integrate deps.dev only through a source adapter that records coverage and origin. The local graph remains useful if the enrichment service is unavailable. [P02] [P03]

**M03-10: Discovery and parser adoption spike.** The bounded `rh_cli ecosystem lookup` adapter accepts either the existing captured envelope or one explicitly requested `--ecosystem`/`--name` lookup. Live mode constructs only the reviewed `https://packages.ecosyste.ms/api/v1/packages/lookup` route, percent-encodes query values, sends one guarded JSON GET with no retry or batch behavior, and retains response body, HTTP status, and stderr beside the output. A non-200 result (including shared-pool 429), oversized body, or malformed array fails closed. Only rows whose returned ecosystem and package name exactly match the request are emitted; other search candidates add to the rejected count. The output keeps provider IDs, version/publication metadata, source and manifest locators, explicit field coverage, rejected-record counts, and candidate mapping provenance; origin records source URL/status, ecosyste.ms attribution, CC BY-SA 4.0 licence link, and that the allowlisted field filter modified the provider response. Unselected response fields (including maintainer identities/contact details when present) are not emitted. Live collection is one query per invocation only; maintainer permissions, traffic, batch lookup, resolved dependencies, and canonical identity remain outside scope. The source review was revalidated against current official API, authentication, and licence documentation; downstream publication must preserve applicable share-alike terms. The parser differential path compares matched node scope/optionality, artifact-digest evidence, exact resolved endpoint pairs and edge scopes, plus unresolved requirement identity/reasons; it emits explicit mapping, context, parser-support, and normalization loss classes while caching by input digest plus parser/version/configuration/output schema with visibility isolation. Unsupported input remains distinct from successful emptiness. (Paper §9; [P12], [P28]-[P31].)

**M03-11: Resolution-instance contract.** Separate package-version identity from `(graph snapshot, provider node ID)` resolution-instance identity; equal version labels may occupy different graph positions. The resolution report now retains graph relation scopes as explicit edges, preserves every unresolved requirement with its source node/name/original requirement/reason, and records source attestations alongside each instance while preserving provider environment/difference context. Preserve requirements separately from resolution, environment assumptions, node/edge errors and partial status. Do not infer directness from manifest/lockfile kind, invent installed versions from ranges, or use lexical key ordering as semantic version ordering. Preserve mapping relation types and source attestations; capped mapping responses are incomplete. (Paper §10.)

### 8.4 Resolver execution boundary

Do not run arbitrary package-manager installation to fill missing graph edges. Where a real resolver is required, use a separately approved metadata-only or isolated resolution mode, record its version, and constrain network and filesystem access.

A resolver-generated environment is hypothetical unless tied to a consumer's actual inventory. Label it `computed_resolution`, not `observed_installation`.

### 8.5 Critical test cases

Create a diamond dependency graph, a cycle, multiple versions of a shared package, optional and platform-specific edges, a missing transitive requirement, an unsupported range, a yanked release, a moved repository URL, and a package falsely claiming a well-known source repository.

Verify that requirements do not become exact edges without evidence. Verify that the same advisory under two accepted aliases counts once, while unrelated advisories are not merged because their descriptions resemble one another.

Test a fixed release published before public disclosure: the resulting signed interval is meaningful and must not be discarded merely because it is negative.

### 8.6 Exit gate

A submitted inventory produces a version-aware graph with explicit unresolved nodes, exact bounded dependent counts, known advisory matches, and path witnesses. The report does not claim global installed usage or runtime exploitability.

## 9. M04 — Maintainer continuity and reversible identities

### 9.1 Goal

Implement the user's central insight: persistent committed stewardship is different from a long list of occasional contributions. Measure it using exact event populations and role evidence, without creating a moral contributor reputation score.

### 9.2 Work packages

**M04-01: Role evidence.** Import versioned maintainer declarations, authorized permission inventories where available, and observed release/merge/review events. Keep declared roles and observed actions separate. Every permission-document import records an explicit authorization state (`authorized`, `unauthorized`, `not_requested`, or `unknown`) so captured provider evidence cannot be mistaken for an authenticated inventory. The bounded `rh_cli roles-import` path normalizes captured GitHub collaborator permissions and GitLab project access levels into `rh-roles-input/1`; GitLab Owner (50) maps to owner, Maintainer (40) to maintainer, Developer (30) and Reporter (20) to member; other levels remain unknown. GitHub maps only documented permission names, and unmapped provider roles remain unknown, non-authorized captures emit no declarations, duplicate page observations replace by actor ID under the member cap, and validated opaque member-page cursor/completion state is retained when supplied. `roles-import --github-repo owner/repo` adds an authenticated GitHub collaborator snapshot with a 1–10 page cap per invocation, 100-record page size, 3 MiB aggregate response bound per invocation, raw JSON/URL/status/error evidence, explicit repository scope, and completeness carried into `permission_inventory_complete`. `--resume-from` accepts only an authorized incomplete snapshot for the same repository, fetches from its validated numeric page cursor, merges by provider actor ID, and retains prior declaration observation times unless a newer page replaces that actor. GitHub defines this endpoint as the collaborators visible to the authenticated caller, including organization and team grants; that visibility boundary remains in the result scope and source notes. A completed cursor chain proves that all requested page segments reached a short page, but the API does not provide an atomic cross-page snapshot. `roles-import --gitlab-project group/path` adds authenticated GitLab `members/all` collection with the same per-invocation page, row, byte, evidence, and resume bounds; nested project paths are encoded as one route component, scope is retained as `project_path`, and only the host-scoped `RH_GITLAB_TOKEN` is sent through curl stdin configuration; GitLab documents `read_api` as the read-only API token scope ([token scopes](https://docs.gitlab.com/security/tokens/access_token_scopes/)). GitLab returns effective project members visible to the authenticated user, including inherited memberships, through the paginated [`members/all` route](https://docs.gitlab.com/api/project_members/), and only the documented Owner, Maintainer, Developer, and Reporter levels map into the normalized role tiers. A completed page chain indicates traversal reached a short page; it is not an atomic snapshot. The roles report publishes the distinct declared owner/maintainer actors intersecting a supplied persistent-activity profile at an explicit as-of time, distinct actors from supplied release, merge, and review actions, authorized permission inventory coverage only when explicit completeness evidence is supplied, release events with missing/null actor attribution as an explicit count, and automation share only from explicit per-action human/bot/service classification; absent as-of, profile, authorization, completeness, or action evidence remains unsupported. Controlled-instance rehearsal remains open admission work.

**M04-02: Local identity normalization.** Support source-native immutable account IDs and project-local mailmap assertions. Preserve raw author identities. Do not auto-merge globally by display name or email-domain similarity. The identity ledger accepts source/instance/native-ID tuples with separately retained display names and time-stamped aliases, rejects duplicate tuples, and keeps equal native IDs from different source namespaces distinct. `rh_cli continuity` groups Git author activity by the canonical author email produced from the repository `.mailmap`; the pinned log retains both raw and mapped values, M01 raw-identity counts remain raw, and system/global or externally configured mailmaps are excluded. The report labels this project-local actor basis without emitting email values.

**M04-03: Accepted identity links.** Add explicit proposed/accepted/rejected/revoked assertions, a review workflow, revisioned clusters, and complete recomputation after revocation.

**M04-04: Automation classification.** Store provider-declared bot/service accounts, explicit project declarations, and unresolved cases. Publish stratified metrics rather than treating every account as a person. The identity and project-publication paths now accept `human`, `bot_known`, `service_known`, and `unresolved` actor kinds and expose each group separately. Optional parallel `actor_kind_sources` entries (`provider`, `project`, `operator`, or `unknown`) retain per-actor source in the restricted identity result and publish only source counts in the project aggregate; omitted source metadata defaults to `unknown`, a missing public kind list defaults to unresolved, and unknown labels fail closed. Optional parallel `actor_kind_observed_at` entries accept nonnegative Unix seconds or `null`; restricted identity output retains each timestamp and aggregate known/unknown coverage, while project publication validates timestamps but exposes coverage counts only. Optional `actor_kind_history` assertions carry actor index, kind, source, and half-open `valid_from`/`valid_until` intervals; the project publication requires explicit `as_of`, resolves the active kind per actor with any history, treats no matching interval as unresolved, and otherwise retains the compact classification for actors without history; concurrent conflicting kinds are unresolved and concurrent source disagreement is unknown. The input order and interval bounds are validated, and the result exposes only the as-of instant plus aggregate assertion/conflict counts, never actor indices or interval rows. Optional parallel `actor_kind_evidence_refs` entries accept nonempty strings or `null`; restricted identity output retains each reference, while project publication validates the values and exposes reference-presence counts only. Missing observation times and evidence references default to unknown, and these optional arrays fail closed without an explicit kind list. When `rh_cli identity --evidence-store <root/evidence>` is supplied, each non-null actor-kind reference must be a 16-character content-addressed object name whose blob verifies under the evidence-store guard. Accepted, rejected, and revoked links additionally require nonempty `reviewed_by`, nonnegative `reviewed_at`, and a verified `evidence_ref`; when actor records identify different source or source-instance namespaces, the decision also requires nonempty `review_reason`. The `rh-identity-evidence-verification/1` sidecar binds verified-reference, reviewed-link, and reviewed-cross-source-link counts to the exact identity input and result digests. Without that option, references remain opaque and both sidecars state `unverified` with empty counts, replacing any prior verification artifact. The evidence-store path emits a restricted `rh-identity-review-notices/1` sidecar for reviewed cross-source links, including accepted, rejected, and revoked decisions; it binds the notices to the exact identity input and output digests and retains only ledger indexes, reviewer/time, rationale, and evidence reference. Delivery to configured subscribers remains open. Role reports publish release, merge, and review event totals stratified by explicit human/bot/service/unknown action type; omitted action type remains unknown. An optional `identity_snapshot` accepts `identity_revision` and the identity report’s `cluster_id_by_actor` map; actions can name their raw identity-ledger index with `identity_actor_index`, and the role report resolves it to the corrected cluster while carrying the revision for lineage. The lower-level per-action `identity_actor_id` override remains available only with an explicit revision. Distinct release/review actor counts and concentration use the resolved key, while source-native `actor_id` remains the basis for event attribution and review-focus metrics. The verifier now enforces and counts evidence-backed cross-source review provenance; delivery of identity-link notices to configured subscribers remains open.

**M04-05: Persistence cohorts.** Implement exact complete-calendar-month activity, span, and recent-activity criteria. Return component measurements alongside cohort membership.

**M04-06: Retention.** Implement eligible newcomer cohorts, return windows, right censoring, history-completeness rules, and observed versus actual first contribution semantics.

**M04-07: Concentration.** Compute top shares, HHI, effective actor count, 50% absence factor, and 80% concentration by event type. Support component and release-line scope. The role-event path now computes exact minimum distinct release and review actors reaching 80% of each supplied action population, with empty populations not applicable and no role inference. Role-event reporting also publishes review share only when an explicit review actor is selected, preserving an exact attributed-review denominator.

**M04-08: Transitions.** Record explicit handovers and separately named activity-derived primary-actor changes. Add follow-up windows and overlap measurements without attributing motives. `rh_cli succession` accepts the additive `rh-succession-input/2` handover-month and requested follow-up window, reports successor active months after the handover, and marks a window extending beyond complete history as partial with observed and requested month counts. `rh-succession-input/3` adds a complete actor-by-month event-count matrix and publishes a separately named activity-derived primary-actor change series and count without emitting actor indexes. A month has a primary actor only when one actor has a unique positive maximum; ties and empty months are null and break adjacent comparisons, while the published change series uses `true`/`false`/`null` for changed/stable/unknown months. The declared-pair overlap and activity-derived timeline remain separate, and neither implies motive or causal transfer.

**M04-09: Contributor protections.** Implement restricted raw identities, project-focused publication, correction requests, and no personal trust leaderboard. `src/rh_identity_publication.elisa` and `rh_cli identity-publish` now accept a bounded public publication input and emit only project-scoped actor-kind/cluster-size/correction aggregates. The public contract structurally omits source-native IDs, aliases, display names, and cluster membership; raw identity is labelled restricted, correction requests retain a project-owner review channel, and `personal_leaderboard` is always false. `tests/test_identity_publication_cli.sh` covers determinism, unknown-kind handling, secret absence, duplicate correction rejection, scope rejection, and malformed links.

Captured role declarations now have the same restricted publication boundary:
`src/rh_role_publication.elisa` and `rh_cli roles-publish` emit
`rh-role-publication-result/1` with authorization state, role/source tallies,
and aggregate query coverage only. Actor IDs, permission documents, and
individual rankings are omitted; declarations remain separate from observed
actions. `tests/test_role_publication_cli.sh` covers unknown roles, revoked
queries, permission coverage, deterministic replay, and malformed input.

**M04-10: Participation semantics and correction fan-out.** Preserve author, committer, reviewer and releaser roles without multiplying event counts. Validate relational joins against independent cardinality oracles; stable tie handling and threshold-crossing actors are mandatory. Any optional cross-project breadth is bounded participation evidence, never prestige or maintainership. Preserve unknown affiliation endpoints without factual sentinel dates. Identity corrections invalidate affected projections while raw events remain unchanged; distinguish current-corrected replay from as-known historical replay. (Paper §§7–8, 15.)

### 9.3 Required comparison fixtures

Fixture A has hundreds of one-off contributors and six persistent reviewers/release actors. It must not trigger a continuity concern merely because the one-off ratio is high.

Fixture B has few total contributors and one actor performing nearly all releases and reviews. It must reveal role concentration even if the one-off ratio is low.

Fixture C has a documented planned handover with long overlap and continued releases. It must not label the outgoing maintainer's reduced activity as failure.

Fixture D has a maintainer who authors few commits but reviews consistently. The maintainer must remain visible through role-specific events.

Fixture E contains a new contributor with less than a month of history. Twelve-month retention is censored, not failed.

### 9.4 Exact numerical oracles

For event counts `[9, 3]`, verify shares `[3/4, 1/4]`, HHI `5/8`, effective count `8/5`, 50% concentration `1`, and 80% concentration `2`.

For `[25, 25, 25, 25]`, verify HHI `1/4`, effective count `4`, 50% concentration `2`, and 80% concentration `4`.

For an empty population, return not applicable for concentration ratios and counts whose semantics require events. Do not claim zero operational redundancy merely because no release occurred in the window.

### 9.5 Exit gate

Every continuity report identifies cohort rules, event types, identity revision, coverage, and denominators. Identity revocation changes only derived cluster-sensitive results, not the raw event ledger. A maintainer can inspect and challenge the evidence behind an attribution.

## 10. M05 — Temporal graph and downstream ecosystem condition

### 10.1 Goal

Make downstream health a first-class product feature. A package report should explain not only which projects depend on it, but what is observably happening in those projects, without treating their popularity as a guarantee of safety.

### 10.2 Work packages

**M05-01: Projection manifests.** Introduce explicit graph projection IDs with version selection, edge scopes, platform/features, valid time, known time, identity revision, mapping revision, and tenant visibility. Prevent APIs from returning unlabeled graph counts.

**M05-02: Temporal relationships.** Record dependency introduction/removal evidence and distinguish it from collector first/last-seen observations. Preserve intervals where continuity is unknown because snapshots are missing.

**M05-03: Project/package mappings.** Build reviewed mapping assertions, one-to-many and many-to-many relationships, repository migrations, project components, and release-line associations. Source metadata does not automatically establish canonical identity.

**M05-04: Mirror and family handling.** Add exact shared-revision relationships, accepted mirror declarations, and optional project-family grouping. Keep independent forks distinct unless a specific deduplication projection groups them for a stated purpose.

**M05-05: Reverse traversal.** Implement unique direct/transitive dependent enumeration with visited sets, root exclusion, typed edge filters, and limits. Add SCC computation for cycle-aware analyses.

**M05-06: Downstream intrinsic joins.** Join known dependents to intrinsic metrics calculated without downstream/adoption inputs. Produce covered-count denominators and distributions of persistence, release activity, review coverage, and known support status.

**M05-07: Adoption changes.** Implement first-seen, confirmed introduction, confirmed removal, observed upgrade, supported-line adoption, and censored duration metrics. Keep replacement hypotheses separate from confirmed migrations.

The `rh_cli adoption` path now keeps optional `last_seen`, first/latest version ordinals, and supported-major evidence separate from first-seen and confirmed introduction/removal. Version ordinals use the documented `major * 1,000,000 + minor * 1,000 + patch` encoding for this bounded adapter. It emits nullable observed-upgrade and supported-line results when the required version evidence is absent, and reports elapsed seconds with `confirmed_removal`, `right_censored`, or `unknown` status; for release-to-upgrade lag, each comparison may carry an upstream release time, target version ordinal, first qualifying downstream version/snapshot, and a complete comparable follow-up boundary; event lag is measured from release to the first qualifying snapshot, right censoring requires the explicit complete-follow-up boundary, and incomplete/missing evidence stays unknown; last-seen/cutoff is the censor boundary, never an asserted removal. Unix epoch zero remains a valid instant; only null or omitted optional evidence is unknown. Inputs beyond cutoff, reversed observation times, and invalid version ordinals fail closed. Seven versioned registry counts expose eligible comparison denominators, observed upgrades, supported-line assessments/adoptions, and confirmed/censored/unknown durations; separate five-bucket histograms expose confirmed and right-censored elapsed durations plus observed and censored release-to-first-qualifying-snapshot lag; `downstream_condition.supported_version_adoption_share` publishes an exact ratio over relations with explicit support evidence. Empty populations return `not_applicable`. Records may supply ordered half-open `snapshot_coverage` intervals or ordered `snapshot_runs` entries with `from`, `through`, and a completeness flag; run histories reconstruct covered intervals from successful runs, while failed/partial runs and missing spans remain uncovered. Overlap, malformed completeness, or invalid ordering fails closed; gaps and uncovered seconds are reported, and any gap prevents right-censor classification. For a common capability, adoption inputs may select one `coverage_source` or an ordered `coverage_sources` list (maximum 16); their persisted or PostgreSQL run histories concatenate in the declared chronological order, so adjacent sources can establish continuity, incomplete spans stay uncovered, and overlaps or reversed cross-source order fail closed. Combined histories are byte-bounded and capped at 4,096 intervals. `rh_cli adoption --store-root <dir>` reads existing filesystem coverage logs. `rh_cli adoption --postgres` now retrieves bounded run windows by source UUID and capability through parameterized libpq calls using `RH_DATABASE_URL`; succeeded runs marked complete/empty count as complete, other run states remain incomplete, histories above 4,096 rows and subsecond boundaries fail closed, and missing bounds do not establish coverage. Fake-libpq and CLI tests verify the query binding and that an incomplete window prevents right-censor classification (`tests/test_adoption_cli.sh`, `tests/test_pg_adapter.sh`).

**M05-08: Shared maintenance exposure.** Join dependency nodes to accepted role evidence and report known overlap. Unknown identities or affiliations remain unknown; do not invent organizational independence. `rh-role-grain-result/1` retains the immutable `event_ledger` as known and a separate `current_event_ledger` with accepted replacements applied and retracted events omitted. `rh_cli maintenance-exposure --evidence-store <store-root>` consumes an `rh-maintenance-exposure-input/1` package graph, focus node, mapping revision, and per-node role ledgers; every supplied mapping must be explicitly accepted, reviewed with a nonempty reviewer and nonnegative time, and carry a 16-hex content address for the exact `rh-role-grain-result/1` blob that supplies its actor ledger; only complete evidence can produce a known overlap, while an accepted incomplete mapping remains unknown. It traverses the downstream closure, deduplicates current actor identities, and emits only known shared-actor counts plus evidence references; it never publishes actor identities, and an unmapped node keeps that pair unknown rather than reporting zero. Each mapping evidence reference is read from the supplied store, checked against its content address, and parsed as the role report itself; actors are never accepted from a separate embedded object. The input and result contracts have schemas and golden fixtures; `tests/test_maintenance_exposure_cli.sh` checks direct/transitive overlap, known zero, unknown mappings, privacy, exact input binding, and fail-closed review/provenance/missing/corrupt-evidence cases. The adapter caps its input at 8 MiB, graphs at 1,024 nodes and 200,000 edges, and each node at 256 distinct actors. Authorization of the named reviewer remains an external governance prerequisite.

**M05-09: Scenario queries.** Add bounded path witnesses for affected versions and simulated node unavailability. Clearly label hypothetical assumptions and observed-graph scope.

**M05-10: Population completeness and focal-library report.** Build the §1.7 slice using a locally owned reverse index. Record discovery source, selected/current/historical version policy, context, pagination/caps, mapping revision and deduplication unit. A top-dependent list is a selected population, not a census. Report unresolved mappings and unknown intrinsic measurements separately; show per-metric covered denominators, distributions and named policy pass/fail/unknown counts. Refresh mutable mappings separately from immutable artifact evidence. Provider downtime cannot remove observed dependents or manufacture healthy zeroes. (Paper §§9–10, 16.)

**Current temporal projection checkpoint:** the product downstream path now preserves optional edge platform, introduction, removal and first-seen observations. Explicit `--scope`, `--platform`, `--valid-as-of`, and `--known-as-of` filters emit `rh-downstream/2`; default calls retain `rh-downstream/1`. `--identity-revision` labels the selected identity snapshot in the report and persisted projection manifest; replay at the same revision preserves the content-addressed ID, while a changed revision produces a different ID. Tests show valid time and collector-knowledge time vary independently, and persisted projection IDs change when temporal or identity revision changes. Accepted mirror and migration mappings now respect the projection known-time cutoff and remap graph edge endpoints before traversal; queries traverse through newly connected canonical representatives, while invalid mapping endpoints fail closed. If any identity-group member is private, the whole representative is excluded from public graph counts and traversal. The downstream CLI verifies cutoff behavior, mapped bridge traversal, private-group exclusion, and invalid endpoints (`tests/test_downstream_cli.sh`). Source capability coverage now requires a valid nonnegative collection instant and rejects per-capability known times later than collection, while preserving Unix epoch zero as a valid instant; `tests/test_coverage_cli.sh` covers missing/future times and epoch zero. Transitive reverse traversal enforces `max_nodes` at each candidate insertion, never exceeds the requested node budget, and marks truncation only when an unseen visible node is actually hidden by a node or depth boundary; exact-fit leaf tests and hidden-branch tests cover both cases. Multi-source interval continuity remains separate work.

### 10.3 Required temporal examples

A dependency introduced in 2024 is first collected in 2026. The “first seen” metric belongs to 2026, while an explicit historical introduction event can belong to 2024. A forecast evaluated as of 2025 cannot use the 2026 discovery unless the query explicitly asks for retrospective knowledge.

A project moves from one forge to another while preserving its source history. Intrinsic project activity should remain continuous under an accepted migration mapping, but source-specific metrics retain their coverage gaps.

A package removes a dependency on one platform while retaining it on another. The graph must reflect context-specific removal rather than deleting a universal edge.

### 10.4 Anti-circularity test

Create project A and project B with fixed intrinsic measurements. Add a large set of dependent nodes to A. Confirm that A's intrinsic continuity metrics do not change. Confirm that B's downstream condition changes only when its own dependent population changes or the independent intrinsic inputs of those dependents change.

Any composite adoption model is explicitly experimental. The basic downstream report should remain useful without it.

### 10.5 Graph-count test suite

Use a chain, diamond, cycle, disconnected graph, multigraph with repeated evidence, package-version duplicates, and mirror-family duplicates. Validate exact expected direct/transitive counts for each projection.

Run each query with a deliberately small node/edge/depth limit. Verify `truncated = true` and no exact-total claim. Confirm private nodes do not appear in public counts or frontier metadata.

### 10.6 Exit gate

A project page can answer: “Which known projects depend on this package, what proportion have recent intrinsic evidence, and how is their maintenance continuity distributed?” All counts are reproducible from the selected graph snapshot and do not recursively depend on endorsement.

## 11. M06 — Product surfaces, policy gates, and corrections

### 11.1 Goal

Expose the observatory through a stable API, CLI, and usable website, including machine-readable decisions for coding agents. Make explanations and corrections part of the product rather than administrative afterthoughts.

### 11.2 Work packages

**M06-01: Query API.** Implement project identity, metrics, continuity, upstream/downstream graph, findings, evidence, and scan-status endpoints. Add cursor pagination and bounded asynchronous graph jobs.

The current bounded wire slice exposes `POST /api/query` for the versioned
`rh-query-input/1` contract and returns `rh-query-result/1` with cursor
pagination, scan-state tallies, and bounded job operations. A store-backed
resource router now exposes fixed `/api/project`, `/api/metrics`,
`/api/continuity`, `/api/graph`, `/api/findings`, `/api/evidence`, and
`/api/scan-status` paths that read only their corresponding JSON artifacts
from the report root; absent artifacts remain 404. The query contract also
accepts a caller-supplied bounded graph snapshot and returns iterative
upstream/downstream traversal with explicit truncation metadata. Upstream and downstream walks enforce `max_nodes` for every candidate insertion and report truncation only when the selected projection actually hides an unseen node; `tests/test_query_cli.sh` covers high-degree upstream fan-out. Cursor pagination rejects negative, duplicate, or unsorted IDs, cursor values below the `-1` start sentinel, and negative page limits; accepting those values could silently skip/repeat rows or misreport a malformed request as a successful empty page. The migration persists bounded graph-query requests/results, absorbs exact enqueue replays, and publishes results only under the current unexpired fencing token after checking result/request kind agreement. `rh_cli postgres` exposes bounded enqueue, `claim_graph_query_job`, `publish_graph_query_result`, and scope-bound `get_graph_query_job`; polling reports lifecycle state and returns output only after success. Fake-libpq tests cover replay, claimed/empty responses, polling across running/succeeded/not-found states, bound request/result JSON, and malformed requests rejected before connecting. The static migration gate covers the database contract, while the opt-in live rehearsal covers claim/request binding, visibility isolation, stale fencing, mismatched result rejection, and atomic publication/polling. Retry policy integration remains open. A bounded `GET`/`HEAD` lookup now serves
verified content-addressed blobs below the report's `evidence/` directory at
`/api/store/<16-hex-digest>`; missing blobs are 404 and digest mismatches are
internal failures, never silently published. The
listener reads split requests through the header terminator and bounded
`Content-Length`, rejecting malformed or oversized bodies before dispatch.

**M06-02: Report generation.** Produce pinned JSON and Markdown reports with evidence cutoff, graph/identity versions, coverage, metric definitions, findings, limitations, and replayability status.

**M06-03: Accessible UI.** Build server-rendered project pages, metric tables, continuity timelines, and bounded graph neighborhoods. Every visual has a keyboard-accessible table or textual alternative.

The static renderer and the server-rendered `/_report.html` path now read
optional `continuity.json` and `continuity-metrics.json` artifacts beside
`report.json`, publishing semantic continuity and metric tables with coverage
basis, first-observation basis, event totals, identity revision, and explicit
unknown states. The continuity tables are covered by renderer and live
loopback regression fixtures; no value is inferred when either artifact is
absent.

**M06-04: Policy parser and evaluator.** Implement validated declarative rules, typed comparisons, required input freshness, minimum sample sizes, four-valued results, and explicit precedence.

**M06-05: Agent integration.** Provide a small tool contract for checking exact dependencies or inventories and explaining findings. Do not allow repository prose to override policy rules.

**M06-06: Exceptions.** Add scoped, approved, expiring waivers tied to rules, package versions/artifacts, and deployment contexts. Record who approved each exception and why.

**M06-07: Correction workflow.** Accept identity, mapping, and measurement disputes with supporting evidence. Implement review states, accepted corrections, publication notices, and invalidation/replay.

The correction CLI now requires a nonempty `evidence_ref` on every dispute and retains it on the corresponding result entry across open, accepted, and rejected states. Accepted and rejected records also require `reviewed_by` and nonnegative `reviewed_at`; open records emit null review metadata. When `--evidence-store` is supplied, every reference must be a 16-character digest of a present blob and is recomputed before applying or persisting corrections; missing/corrupt objects fail closed. New accepted corrections emit notice records in `rh-correction-notices/1` with subject, revision, review provenance, evidence reference, and invalidation count; idempotent replays emit no duplicate notices. Evidence registration/access-policy verification and delivery of notices to configured subscribers remain open work.

**M06-08: Notifications.** Support authorized user-configured destinations, alert deduplication, cooldowns, acknowledgment, resolution, and source-outage suppression. Do not send unsolicited accusations to upstream maintainers.

**M06-09: Structured external findings.** Add an optional Scorecard findings adapter preserving original tool/check/probe version, subject revision, assessment time, typed outcome, polarity, locations and remediation. Unknown, omitted, inconclusive and error are distinct from false or failed. Three delivery paths for one run remain one origin assessment. Bind decisions to these findings and local rule versions; delivery time does not refresh assessment age. Evidence drill-down must reach both source payload and transformation/loss metadata. (Paper §§11, 20.) `rh_cli findings` now also writes a digest-bound `rh-adapter-transformation-report/1` sidecar for the exact assessment input and normalized findings result, with field states for preserved assessment/finding data, transformed outcome counts, discarded provider fields, and source-evidence references not published in the result; `tests/test_findings_cli.sh` verifies both hashes and the versioned configuration digest.

### 11.3 Policy truth-table tests

For every comparison operator, test observed passing value, observed failing value, unavailable input, stale input, partial input, not-applicable input, conflicted evidence, and insufficient sample.

A rule requiring complete resolved inventory returns unknown for an incomplete graph. A rule with a documented blocking advisory match returns deny even if another rule's data is unknown. A warning must not override a deny.

When an integration chooses to block unknown results, its exit code can reflect blocked execution while the structured decision remains unknown. This prevents a pipeline transport convention from rewriting analytical semantics.

### 11.4 Time-of-check/time-of-use tests

Evaluate a package version and artifact digest, then change the requested registry, digest, platform, or lockfile. The prior decision must no longer apply unless its scope explicitly permits that variation.

If a source changes bytes under the same package-version label, the result is a new artifact identity and requires renewed evaluation. A cached favorable project report is not enough to admit different bytes.

### 11.5 User acceptance scenarios

A maintainer inspects their project and understands why a concentration finding appeared. A developer compares two libraries with different source coverage without being misled by blank cells. An agent attempts to add a dependency and receives a structured unknown because the graph is unresolved. An administrator approves a time-limited exception, which later expires automatically.

A contributor challenges an incorrect account merge. The correction is accepted, affected metrics are recomputed, and the previous report is marked superseded rather than silently rewritten without an audit trail.

### 11.6 Exit gate

The complete workflow—from source/inventory submission through evidence, graph, metrics, policy, explanation, and correction—is usable without direct database access. Public-facing text makes no unsupported claim that a project or person is safe or trustworthy.

## 12. M07 — Security, privacy, operations, and public beta

### 12.1 Goal

Validate that the useful product can be operated without endangering its users, leaking private dependency information, overburdening source hosts, or publishing misleading conclusions.

### 12.2 Security work packages

**M07-01: Independent threat-model review.** Have a reviewer not responsible for the collector implementation inspect URL handling, subprocess isolation, archive parsing, credentials, plugin boundaries, and public/private graph flows.

**M07-02: Adversarial transport tests.** Exercise loopback/private/link-local addresses, IPv6 variants, encoded addresses, redirects, DNS rebinding, unexpected ports, internal submodule URLs, and credential-forwarding attempts. The public crawler must reject them according to policy. HTTPS fetches resolve names with a bounded resolver, reject the complete answer set if any address is non-public, and pin every accepted address in cURL's DNS cache; proxies and user cURL configuration are disabled. Address policy conservatively excludes IANA special-purpose ranges. Tests inject mixed public/private A/AAAA answers to prove the request never reaches cURL, and safe mixed-family answers to prove every accepted address is pinned. [P05]

**M07-03: Source-parser hardening.** Deterministic offline mutation checks exercise JSON, Cargo's inline and legacy `[metadata]` checksum paths, npm, pnpm v9, and Yarn Classic v1 lockfiles, Go/RubyGems/Composer/NuGet/Maven/PyPI/PEP 621, SemVer/PEP 440, Mercurial/Subversion/Fossil, and archive-metadata parsers. The harness checks structured results, output bounds, and returned span bounds where applicable. `tests/test_m07_sanitizer.sh` recompiles and runs the deterministic mutation harness with AddressSanitizer and UndefinedBehaviorSanitizer. `src/fuzz_m07.elisa` exposes the same parser families to LLVM libFuzzer with sanitizer coverage; checked-in seeds and `tests/test_m07_fuzz.sh` provide a bounded 1,000-run offline campaign, while `tools/fuzz-m07.sh` supports longer local runs. A fresh 100,000-run campaign from 22 checked-in seeds completed without a crash using Homebrew clang 23.1.1, with coverage counters increasing from 1,197 to 1,876. Fuzzing beyond this run and independent review remain open. The campaign's earlier iterations exposed malformed NuGet attribute spans and overflowing patch-series decimal fields; both now fail safely and have regression seeds and deterministic tests.

**M07-04: Publication integrity.** Sign released software and optionally report manifests under a documented key policy. Protect signing keys separately from collection workers. Verification is evidence integrity, not a claim that measurements are infallible.

**M07-05: Dependency review.** Inventory repo-health's own dependencies, build-time tools, and native components. Document update procedures and isolate unavoidable native parsing surfaces.

### 12.3 Privacy and rights work packages

**M07-06: Source review register.** Record access terms, redistribution permissions, attribution requirements, personal-data fields, retention policy, contact routes, and authorized capability scope for every source integration.

**M07-07: Publication review.** Confirm that project aggregates do not leak private dependents or unnecessary personal identities. Establish suppression thresholds as product policy and test differencing risks; do not claim formal anonymity without a defined method.

**M07-08: Correction and deletion drills.** Revoke identity links, remove restricted raw payloads, invalidate caches, and regenerate authorized reports. Confirm replayability labels change when required inputs are no longer retained.

**M07-09: Data-provider dependency review.** Check whether third-party feeds are active and legally usable. Do not assume historical datasets are current; the Criticality Score cloud-data retirement is a concrete example of why this review is necessary. [P09]

### 12.4 Operations work packages

**M07-10: Backups and restore.** Back up the database and evidence store with a manifest linking them. Restore to a clean environment and replay a sample of published reports.

**M07-11: Monitoring.** Instrument queue age, source freshness, error rates, parser rejection rates, cursor lag, evidence-object failures, policy unknown rates, and graph truncation rates. Separate service health from project health.

**M07-12: Source-respect controls.** Apply per-host quotas, retry backoff, cancellation, contact identity, crawl exclusions where applicable, and a stop mechanism for a source operator's request.

**M07-13: Incident runbooks.** Define actions for credential leakage, corrupted evidence, incorrect identity mass merge, provider schema change, advisory mismatch, and publication of misleading findings.

### 12.5 Pilot design

Recruit a small opt-in set of projects spanning different sizes, workflows, and hosts. Include a mature quiet library, an active framework, a mailing-list-oriented project where feasible, a single-maintainer utility, a project with many occasional contributors, and a project that migrated hosts.

Ask maintainers whether the report accurately describes observed processes, whether caveats are understandable, and which findings suggest useful action. Record corrections and false alarms. Do not define success solely as agreement with the system's own score.

The pilot must also validate package-to-project mappings and downstream inclusion manually before evaluating decision usefulness. Record mistaken mappings/merges, misleading role labels, correction effort, findings that changed decisions, and evidence that resolved unknowns. Include inaccessible projects in coverage and mature low-churn/self-hosted projects in the sample. Publish sample limits; neither high rejection rates nor the paper's miniature tests establish safety. Monitor upstream availability/schema/license changes and exercise stale/unknown fallback. (Paper §§18–21.)

### 12.6 Beta release checklist

The beta ships only when critical safety tests pass, rights and privacy reviews are recorded, report explanations are traceable, restoration has been exercised, source coverage is honest, and the pilot reveals no unresolved systematic misrepresentation.

A smaller beta with accurate supported capabilities is preferable to a broad launch that invents data. Publish a clear support matrix and a list of known limitations.

## 13. M08 — Broader source and ecosystem coverage

### 13.1 Goal

Demonstrate that the architecture works beyond GitHub-like forges, Git histories, and the first two package ecosystems.

### 13.2 Expansion lanes

| Lane | Candidate implementations | Architectural challenge |
|---|---|---|
| Forge APIs | Gitea, Bitbucket Cloud, additional self-hosted instances. | Capabilities, identity IDs, authorization, pagination. |
| Review workflows | Gerrit, mailing-list patch archives, standalone trackers. | Patch-set revisions, explicit trailers, non-PR semantics. |
| Native VCS | Mercurial, Subversion, Fossil; CVS/Breezy imports later. | Revision identity, global revisions, branch conventions. |
| Source hosting | SourceHut, SourceForge, cgit/gitweb-fronted servers. | Generic VCS plus separate metadata channels. |
| Package ecosystems | PyPI, Maven, NuGet, RubyGems, Composer, Go, distribution packages. | Ecosystem-native names, versions, ranges, support lines. |
| Inventory formats | Additional SPDX/CycloneDX versions and formats. | Lossless import, unknown fields, provenance. |
| Distribution data | Bounded Debian `debian/control` metadata with source assertions and declared relations. | Upstream mapping, patches, distribution versions. |
| Archives/releases | Release-only sites, source archives, archival identifiers. | Useful reports without invented development history. |

This is a candidate queue, not a promise that every source exposes the same data. Order work by user value, feasible access, data rights, and which abstraction boundary it tests.

The first bounded execution slice now covers native Mercurial, Subversion, and
Fossil collection through `rh_cli vcs --repo`, plus guarded URL capture for
forge payloads, release-only feeds (including explicit withdrawal and support-line state), and
CycloneDX/SPDX inventory documents.
Each capture retains source, status, and error evidence before normalization;
provider-specific authentication, pagination, and live permission collection
remain separate admission work; bounded captured GitHub/GitLab permission
imports are covered by `src/rh_roles_provider.elisa` and
`tests/test_roles_provider_cli.sh`.

Registry enrichment now has one provider-shaped adapter at the boundary:
`src/rh_registry_pypi.elisa` accepts bounded PyPI project JSON, normalizes its
release-file map and `info.requires_dist` metadata into the canonical
`rh-registry-meta/1` input, and preserves unknown file-level yank state rather
than guessing a version is safe. The adapter is exercised through the same
`rh_cli registry-meta` command and remains separate from package identity and
resolved dependency edges.

The same boundary now accepts npm project metadata through
`src/rh_registry_npm.elisa` and crates.io's `crate` envelope through
`src/rh_registry_crates.elisa`. npm `versions` objects retain publish times,
repository/homepage assertions, and runtime/optional/dev dependency counts;
crates.io versions retain `created_at`, tri-state yanks, and the crate-level
repository assertion. Both adapters reject malformed provider shapes and emit
the canonical contract without package-manager resolution.

RubyGems versions are now covered by the same bounded boundary through
`src/rh_registry_rubygems.elisa`. It accepts the versions endpoint array and a
retained project wrapper, maps `number`/`created_at`/`yanked`, keeps
runtime/development dependency counts, and preserves source/homepage URI
assertions. Missing yanks remain null and malformed version records fail
closed; no gem resolver or installation is invoked.

NuGet registration pages are now covered by the same bounded boundary through
`src/rh_registry_nuget.elisa`. It accepts `items` pages and nested
`catalogEntry` records, maps `listed=false` to a retained yanked version,
preserves publication time and project URL assertions, and counts declared
dependency groups without resolving package ranges. Malformed entries fail
closed and the normalized output remains the canonical `rh-registry-meta/1`
input to the report path.

PyPI declared dependencies also accept the bounded PEP 621
`project.dependencies` and `project.optional-dependencies` TOML subset;
exact pins become scoped edges and ranges remain explicit unresolved
requirements. The bounded NuGet `packages.config` subset accepts exact
`id`/`version` package entries, preserves `developmentDependency` as a
development scope, and leaves version ranges as explicit unresolved
requirements; malformed entries fail closed without publishing a partial
graph.

The bounded Maven `pom.xml` subset accepts project and dependency
`groupId`/`artifactId` coordinates, emits exact literal-version edges, maps
`test`/`provided` and `optional` scopes, and skips dependency-management
entries. Property interpolation, ranges, profiles, and malformed dependency
blocks remain explicit unresolved or fail-closed cases.

The first distribution slice is `src/rh_distribution.elisa` with
`rh_cli distribution --input <debian/control> --out <file>`. It accepts a
bounded Debian control subset, preserves source versions, package metadata,
VCS/homepage assertions, build/runtime relation scopes, alternatives, and
unresolved relation states, and counts unknown fields. Maintainer and
description text are deliberately omitted; no upstream mapping, patch
provenance, or dependency resolution is inferred. The public result is
`rh-distribution-result/1`, covered by `schemas/distribution.schema.json` and
`tests/test_distribution_cli.sh`; malformed stanzas fail closed without
replacing a prior output.

The archive lane is `src/rh_archive.elisa` with `rh_cli archive --input
<file> --out <file>`. Its `rh-archive-input/1` subset records unique
publisher-declared source, snapshot, or binary archive identifiers, approved
HTTPS/file links, SHA-256 digest claims, published times, and sizes. The
result is `rh-archive-result/1` with explicit `history_supported`,
`identity_supported`, and `extraction_supported` false capabilities. Archive
bytes are never fetched, expanded, or executed, and malformed or duplicate
metadata fails closed.

The distribution ecosystem slice also includes a bounded Homebrew formula
adapter: `src/rh_homebrew.elisa` and `rh_cli homebrew` consume
`rh-homebrew-formula/1`, retain stable version/link/digest assertions and
runtime/build/optional/test dependency declarations, and emit
`rh-homebrew-result/1`. Formula descriptions, install outcomes, package
manager execution, and dependency resolution remain outside the adapter.

The RPM distribution path is `src/rh_rpm.elisa` with `rh_cli rpm-spec
--input <file.spec> --out <file>`. It reads only the spec preamble, preserves
name/version/release/epoch, URL/license/architecture, source and patch
declarations, and build/runtime/recommendation/provide/conflict relation
scopes. Macro references and unsupported relation forms remain unresolved;
section bodies are never expanded or executed. The public result is
`rh-rpm-spec-result/1`, covered by `schemas/rpm-spec.schema.json` and
`tests/test_rpm_spec_cli.sh`.

The Arch distribution path is `src/rh_arch.elisa` with
`rh_cli arch-pkgbuild --input <PKGBUILD> --out <file>`. It parses only bounded
top-level assignments before the first shell function, preserves package
version/release/epoch, licenses, architectures, sources, checksums, and
declared runtime/build/check/optional/provide/conflict/replace relations.
Shell substitutions remain unresolved evidence; functions are never sourced,
expanded, or executed. The public result is
`rh-arch-pkgbuild-result/1`, covered by
`schemas/arch-pkgbuild.schema.json` and
`tests/test_arch_pkgbuild_cli.sh`.

### 13.3 Connector admission checklist

Every new connector needs a source documentation review, capability manifest, authentication model, URL/transport security review, pagination tests, incremental/reconciliation design, source-to-canonical mapping table, fixture corpus, resource budgets, rights review, and operator documentation.

Record exact unsupported capabilities. A release-only website can legitimately report artifact and release observations while returning unavailable for maintainer retention.

### 13.4 Non-Git acceptance criteria

At least one native non-Git history adapter must produce valid activity and identity observations without inventing Git commit hashes or treating global SVN revision increments as project changes.

At least one non-PR workflow must preserve review/proposal semantics without demanding a GitHub-style merge request. A patch series revised three times should not automatically become three independent accepted changes.

### 13.5 SourceHut validation task

The SourceHut manual could not be retrieved during document preparation. Its native API work therefore begins with a fresh official-documentation and controlled-instance validation task. Generic Git/Mercurial coverage can proceed independently.

Do not copy speculative endpoint names into implementation tasks and then treat them as contractual APIs.

### 13.6 Ecosystem parser admission

For each package ecosystem, document name normalization, version ordering, prerelease behavior, constraints, aliases, registry identity, optional/platform conditions, local/path dependencies, and lockfile guarantees. The current bounded admission set includes Cargo, npm package/shrinkwrap, pnpm v9.0 and Yarn Classic v1 lockfiles, PyPI requirements/PEP 621, Go modules, RubyGems, Composer, NuGet `packages.config`, and Maven `pom.xml`. Pnpm is limited to one root importer; exact locked versions map through snapshot keys, peer-specific paths remain separate graph nodes, and workspace/Git/path conditions stay unresolved. It fails closed on other pnpm revisions, multiple importers, unknown fields, and unsupported constructs. Yarn resolves only exact name/range selectors from v1, rejects Berry revisions and aliases, and is used only when the npm and pnpm lockfiles are absent. Node lock selection prefers npm shrinkwrap, npm package lock, pnpm, then Yarn. NuGet IDs compare case-insensitively with punctuation preserved, while Maven coordinates use exact `groupId:artifactId` names. Exact versions resolve to registry nodes, and range/property syntax remains unresolved with an unsupported-range metric.

Support begins at a declared format/version subset. Unsupported versions return unsupported, not partial success disguised as completeness. Add official examples plus adversarial fixtures and an independent oracle where feasible.

### 13.7 Exit gate

The system's expanded support matrix includes tested non-Git and non-PR paths, additional ecosystems, and release-only sources. No expansion requires changing the definition of project health to match one provider.

## 14. M09 — Expand the metric catalog responsibly

### 14.1 Goal

Grow toward the architecture's 360 concrete definitions while maintaining measurement quality. The catalog is a research and delivery backlog, not a demand to compute every metric on every project.

The first denominator-version admission is now executable: `coverage.window_completeness@2.0.0` is emitted beside v1 from the M01 report, with the full requested-window denominator retained for shallow and truncated scans. The two `(key, version)` entries remain separately addressable and are covered by the F003/F038 fixture assertions.

The release-note key is versioned by population: `release.release_note_presence@1.0.0` reports recognized note/changelog path presence in retained repository evidence, while `@2.0.0` reports the explicit release-feed ratio of releases with retrievable associated notes. The v2 numerator/denominator is observed only when each accepted release has an explicit retrieval outcome; incomplete states do not silently become zero.

The scanner also publishes `history.reachable_merge_count` as a separate
low-cost count sourced from reachable parent evidence. It deliberately does
not reuse the requested-window `history.commit_count` definition, so history
scope and activity-window scope remain explicit in the metric registry and
profile.

The same report now publishes `history.rejected_record_count`, a low-cost
parser-integrity count sourced from structurally rejected Git log records.
Malformed evidence remains visible as a count instead of being silently
coerced into an accepted zero-event population; the definition is covered by
the shallow/history fixture path and stays project-aggregate only.

### 14.2 Suggested measurement waves

| Wave | Families | Dependency on capabilities | Publication rule |
|---|---|---|---|
| A: foundational | History, activity, contributors, coverage. | Native metadata and evidence. | Publish after deterministic fixture validation. |
| B: continuity | Persistence, roles, concentration, succession, reviews, issues. | Longitudinal workflow and role evidence. | Publish with identity and censoring coverage. |
| C: ecosystem | Dependencies, freshness, downstream condition, graph structure. | Version-aware graph and project mappings. | Publish with projection scope and completeness. |
| D: engineering | Builds, testing, code, documentation, compatibility. | Structured run reports or supported static analyzers. | Distinguish declared configuration from execution. |
| E: integrity | Advisories, provenance, licensing, recovery. | Advisory feeds, artifacts, attestations, inventories. | Keep verification and applicability limitations explicit. |
| F: sustainability | Governance, funding, attention, support outcomes. | Public/authorized records and rights review. | Avoid personal or causal inference. |
| G: experimental | Forecasts, anomalies, proof evidence, benchmarks. | Independent validation and stronger isolation. | Opt-in; excluded from default hard gates. |

### 14.3 Metric admission template

```yaml
key: persistence.retained_90d
version: 1.0.0
implementation_status: planned
owner: metrics-maintainers
subject_kind: project
inputs:
  - qualifying_events
  - collection_coverage_intervals
  - identity_revision
output:
  kind: rational
  unit: ratio
  numerator: eligible_actors_with_return_event
  denominator: eligible_actors_with_complete_return_window
parameters:
  return_start_days: 90
  return_end_days: 120
missing_data:
  insufficient_followup: censored
  incomplete_return_window: exclude_from_eligible_and_report
  empty_eligible_population: not_applicable
confounders:
  - first_observed_is_not_necessarily_first_ever_contribution
  - workflow_coverage_can_change_after_migration
validation:
  fixtures_required:
    - retained
    - not_retained
    - right_censored
    - coverage_gap
    - identity_revoked
privacy_class: project_aggregate
cost_class: low
```

This template is a contract draft. Its schema should be finalized in M00 and enforced mechanically thereafter.

### 14.4 Admission process

A metric author supplies the definition and fixture oracle before implementation. A reviewer checks unit and denominator semantics, source feasibility, privacy, cost, confounders, and potential gaming. The code then implements the accepted contract.

A second review verifies that explanations and labels do not overstate the metric. For example, an observed revert relationship is not automatically a mistake by the original author; a missing test report is not proof that the project never tests.

### 14.5 Cost and availability planning

Assign collection and computation costs separately. A metric may be cheap to calculate but depend on expensive historical data. Use shared aggregates without silently changing definitions.

For each source family, publish which metrics are available from public metadata, which require authorized access, which need optional analysis, and which are unsupported. The system should explain why a metric is absent rather than merely displaying a blank tile.

### 14.6 External practice and provenance tools

Import named check results from tools such as Scorecard with their tool/check versions and evidence. Do not transform an imported score into a repo-health primitive fact or assume every provider supports every check.

For attestation verification, use established verification libraries and pinned trust policies. Store presence, syntax validity, cryptographic verification, subject-digest match, source binding, and policy satisfaction as distinct outcomes.

Reproducible-build checks require a defined source, build environment, and instructions; a successful build by itself is not a reproducibility result. [P10]

### 14.7 Metric retirement

A metric can be deprecated when it proves misleading, unobservable, too expensive, or redundant. Preserve historical definitions and migration notes. A dashboard should not silently switch from one interpretation to another under the same key/version.

The goal is maximal useful measurement, not maximal permanent metric count regardless of value.

## 15. M10 — Scale only after measuring

### 15.1 Goal

Support larger observed ecosystems while preserving exactness, privacy boundaries, replay, and source-respect constraints.

### 15.2 Establish a reference workload

Create deterministic datasets at several scales. A suggested synthetic sequence is 100 projects, 1,000 projects, and 10,000 projects with explicitly specified event counts and graph distributions. These are benchmark configurations, not claims about average real projects.

Include a long-tail degree distribution, a few highly central dependencies, cycles, many package versions, mirrored projects, partial coverage, and historical corrections. Report hardware, dataset digests, warm/cold cache state, concurrency, latency percentiles, memory, disk, and external-request budgets.

**Current repository checkpoint:** the local deterministic harness covers 100, 1,000, and 10,000 graph nodes, with uniform, long-tail, central-hub, cycle, and an ecosystem profile. It records ten timed samples after one warmup batch, latency median/p95/variance, per-process peak RSS, source and binary identity, toolchain settings, host hardware/disk context, cache conditions, and measured batches of 1–32 concurrent local processes. It profiles graph construction, bounded reverse traversal, indegree concentration, and synthetic package-version/mirror/coverage workloads through temporal graph projections, per-metric coverage, and correction invalidation/replay. A separate temporary corpus passes 17 evidence files (13 unique objects) through the real local content-addressed store and records logical and filesystem-allocated bytes after verification. The deterministic workloads remain synthetic and do not cover arbitrary historical correction replay. The worker pass tests due-full priority and deterministic rotating service under bounded capacity, but not fairness under deployed worker contention. Setting `RH_PROFILE_REPO` adds an opt-in full-history scan of a real local Git repository; the manifest records the source revision, digest, counts, latency, and memory samples, while temporary reports and raw identity data are discarded. The concurrent harness records a 1 ms target-poll series summing live-child RSS reads per driver pass with missed batches explicit, plus a conservative sum of individual child peak RSS values; brief peaks may fall between polls. It does not measure worker-scheduler load shedding or deployment/database/remote-object-store load. The downstream shared-cache path now emits `rh-projection-snapshot/2` with a minimized public graph: private nodes and incident edges are removed, visible IDs are remapped, and unknown fields, unresolved rows, and advisory witnesses are omitted. A regression exercises two visibility policies against one content-addressed root and checks that each immutable object contains only its own visible graph; this verifies local snapshot payload isolation, not deployed tenant authorization. See [`docs/operations/BENCHMARKS.md`](docs/operations/BENCHMARKS.md); the M10 exit gate remains open.

### 15.3 Work packages

**M10-01: Profiling.** Identify whether bottlenecks are network rate limits, VCS retrieval, parsing, database writes, graph queries, metric computation, or report rendering. Do not optimize the graph database before measuring it.

**M10-02: Incremental aggregates.** Maintain validated daily/weekly event aggregates and role counts with input partitions and correction invalidation. Test equivalence against full recomputation.

**M10-03: Query plans and indexes.** Inspect real query plans, add justified indexes, batch lookups, avoid per-node network/database calls, and test high-degree nodes.

**M10-04: Object storage.** Move evidence blobs behind an object-store interface if local storage is operationally limiting. Preserve digest verification, access policy, and restore manifests.

**M10-05: Columnar snapshots.** Add exportable batch-analysis snapshots when historical scans justify them. Keep them rebuildable and rights-filtered.

**M10-06: Distributed workers.** Add more workers only after leases, quotas, idempotency, and source-instance fairness are proven. Partition work by source/capability and avoid coordinated retry storms.

**M10-07: Optional graph acceleration.** Evaluate a dedicated projection store only against measured workload and correctness tests. It cannot become an untracked second source of truth.

### 15.4 Complexity budgets

A bounded breadth-first traversal should do work proportional to the visited nodes and edges. SCC analysis should be linear in the included graph and avoid recursion-depth failures on hostile inputs. Global centrality needs explicit iteration and convergence limits.

Do not materialize every transitive dependency relationship for every node. Cache targeted results and provide asynchronous exports for large requests. A graph result that hits a budget returns truncation, not a fabricated total.

### 15.5 Exit gate

Publish benchmark results and capacity limits for the tested deployment. Demonstrate that load shedding disables optional work before corrupting basic evidence, that correction replay still works, and that private/public scopes remain isolated under shared caches.

## 16. M11 — Experimental models and advanced verification evidence

### 16.1 Goal

Explore higher-value analytics without weakening the evidence-first foundation. These capabilities are optional and must remain separate from ordinary measurements until validated.

### 16.2 Forecasting maintenance discontinuity

Define an outcome that is actually observable, such as “no qualifying release/review/change events during a specified future interval, among projects with complete follow-up.” Do not label it a person's abandonment or personal reliability.

Use temporal splits, project-family separation, censoring, and data available at the prediction cutoff. Compare against simple baselines such as prior activity and project age. Report calibration, false positives, subgroup coverage, and alert burden.

A forecast is a model result with a horizon and population—not a fact that the project will fail. It cannot silently change default policy decisions.

**Current repository checkpoint:** `rh_cli forecast` consumes `rh-forecast-input/2` and emits `rh-forecast-result/2`. The envelope requires an observable binary outcome, temporal/family-separated/censoring-aware split declarations, and exact model and baseline Brier scores with a matching submitted cohort identifier and sample count. It validates captured evaluation evidence; it does not train the model or independently verify the supplied split membership or cohort identity, and remains opt-in and separate from policy.

### 16.3 Publication anomaly analysis

Study deviations in artifact digests, source mappings, publishing actors, release cadence, and dependency changes. A model may flag an unusual event for review; unusual does not mean malicious.

Prefer concrete first-level findings such as “artifact digest changed under the same version label” before a generic anomaly score. Explicit evidence is easier to validate and explain.

### 16.4 Formal-proof evidence

Create an adapter for proof claims with proposition identifiers, source revision, checker version, assumptions, trusted computing base, proof digest, replay result, and artifact binding.

An Elisa or elisa-proof integration can use this contract later. It should not require the rest of repo-health to be implemented in Elisa. Proof validity and source-to-binary correspondence remain separate fields.

Example distinctions include “bounds-safety proof replayed for source revision X,” “source revision bound to artifact Y,” and “all native dependencies included in the proof assumptions.” Do not collapse them into “whole application formally safe.”

### 16.5 Benchmark evidence

Benchmarks require a reproducible workload, environment, compiler/runtime settings, warmup policy, repetition count, variance, baseline identity, and measurement units. A single noisy run is not a verified regression.

Dynamic execution uses a separately approved sandbox and budget. No benchmark plugin receives production service credentials.

### 16.6 Intervention evaluation

The graph can identify support opportunities and track subsequent observations. Estimating the causal benefit of funding or maintenance work requires an evaluation design beyond before/after counts.

Record intervention scope, selection rationale, baseline, comparison approach, outcomes, and limitations. Do not advertise a precise number of prevented incidents from a maintenance dashboard alone.

### 16.7 Exit gate

Each experimental feature has its own evaluation report, opt-in controls, clear labels, and rollback path. A failed experiment can be removed without affecting canonical evidence or stable metrics.

## 17. M12 — Stable production release and stewardship

### 17.1 Goal

Make the project dependable as long-lived infrastructure: stable contracts, reproducible data products, transparent methodology, operational continuity, and a sustainable support model.

### 17.2 Release criteria

Version 1.0 requires documented supported source/format versions, stable public schemas, migration guarantees, correction procedures, security review, tested backup/restore, observed service limits, metric-definition governance, and a public limitations statement.

It does not require all 360 metrics to be implemented on every source, global coverage, a universal score, machine-learning forecasts, or complete formal verification. Those would be inappropriate prerequisites for a useful stable observatory.

### 17.3 Governance deliverables

Publish how metric definitions change, how source integrations are reviewed, how contributors appeal incorrect attributions, how conflicts of interest are handled, and how paid services relate to public reports.

Maintain at least two people capable of performing critical project operations where feasible, and document release/recovery procedures. Apply repo-health's own continuity concepts to its stewardship without claiming that self-measurement is independent assurance.

### 17.4 Sustainability options

Potential funding models include hosted private inventories, organizational integrations, support contracts, research partnerships, and public-interest grants. Core factual definitions and correction access should not depend on payment.

Do not sell favorable public health labels or quietly reduce a sponsor's finding severity. Commercial features can improve workflow and deployment convenience without corrupting the evidence model.

### 17.5 Ongoing maintenance

Schedule connector compatibility reviews, dependency updates, schema migration testing, source-rights reviews, restoration drills, metric-validity reviews, and user research. Track repo-health's own source coverage and data quality as first-class operational outputs.

A stable release is the beginning of sustained operation, not the end of implementation responsibility.

## 18. Concrete storage and ingestion blueprint

### 18.1 Identifier conventions

Use typed internal UUIDs or another explicitly chosen opaque ID scheme. Public identifiers may render as `project:<opaque-id>` or `package:<opaque-id>`, but the prefix is part of the type contract, not a heuristic for inferring identity.

Source-native IDs remain stored separately and are unique only within their source instance and object kind. Package coordinates have their own normalized uniqueness rules. Digests always include an algorithm identifier.

Avoid natural keys based solely on display names, email strings, mutable usernames, or repository URLs. Those values can change or collide.

### 18.2 Minimal migration excerpt

The following SQL is an illustrative starting contract, not the complete production schema. Full migrations must add domain tables, foreign-key policies, temporal constraints, tenant enforcement, indexes, and tests described in the architecture.

```sql
CREATE TABLE source_instance (
    id uuid PRIMARY KEY,
    kind text NOT NULL,
    base_url text NOT NULL,
    visibility_scope text NOT NULL,
    configuration_revision bigint NOT NULL CHECK (configuration_revision > 0),
    created_at timestamptz NOT NULL
);

CREATE TABLE evidence_object (
    id uuid PRIMARY KEY,
    visibility_scope text NOT NULL,
    digest_algorithm text NOT NULL,
    digest_value text NOT NULL,
    media_type text NOT NULL,
    byte_length bigint NOT NULL CHECK (byte_length >= 0),
    storage_key text NOT NULL,
    retention_class text NOT NULL,
    transformation_kind text NOT NULL,
    created_at timestamptz NOT NULL,
    UNIQUE (visibility_scope, digest_algorithm, digest_value)
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
    status text NOT NULL,
    completeness text NOT NULL,
    coverage_details jsonb NOT NULL,
    CHECK (requested_end IS NULL OR requested_start IS NULL
           OR requested_end > requested_start),
    CHECK (finished_at IS NULL OR finished_at >= started_at)
);

CREATE TABLE canonical_event (
    id uuid PRIMARY KEY,
    source_instance_id uuid NOT NULL REFERENCES source_instance(id),
    source_object_type text NOT NULL,
    source_object_id text NOT NULL,
    source_revision text NOT NULL,
    event_kind text NOT NULL,
    subject_id uuid NOT NULL,
    actor_account_id uuid,
    occurred_at timestamptz,
    observed_at timestamptz NOT NULL,
    time_basis text NOT NULL,
    evidence_id uuid NOT NULL REFERENCES evidence_object(id),
    parser_version text NOT NULL,
    payload jsonb NOT NULL,
    UNIQUE (source_instance_id, source_object_type,
            source_object_id, source_revision, event_kind)
);

CREATE TABLE metric_definition (
    metric_key text NOT NULL,
    metric_version text NOT NULL,
    definition_digest text NOT NULL,
    definition jsonb NOT NULL,
    implementation_status text NOT NULL,
    PRIMARY KEY (metric_key, metric_version)
);

CREATE TABLE metric_observation (
    id uuid PRIMARY KEY,
    visibility_scope text NOT NULL,
    subject_id uuid NOT NULL,
    metric_key text NOT NULL,
    metric_version text NOT NULL,
    run_id uuid NOT NULL,
    status text NOT NULL CHECK (status IN (
        'observed', 'not_observed', 'unavailable', 'unauthorized',
        'partial', 'stale', 'not_applicable', 'error',
        'conflicted', 'suppressed', 'unsupported'
    )),
    value jsonb,
    unit text NOT NULL,
    window_start timestamptz,
    window_end timestamptz,
    input_manifest_digest text NOT NULL,
    configuration_digest text NOT NULL,
    identity_revision text NOT NULL,
    graph_projection_id uuid,
    quality_dimensions jsonb NOT NULL,
    computed_at timestamptz NOT NULL,
    FOREIGN KEY (metric_key, metric_version)
        REFERENCES metric_definition(metric_key, metric_version),
    CHECK (window_end IS NULL OR window_start IS NULL
           OR window_end > window_start),
    CHECK (
        (status = 'observed' AND value IS NOT NULL)
        OR status IN ('partial', 'stale')
        OR (status NOT IN ('observed', 'partial', 'stale') AND value IS NULL)
    )
);

CREATE INDEX event_subject_time
    ON canonical_event (subject_id, occurred_at, id);

CREATE INDEX metric_subject_lookup
    ON metric_observation
       (visibility_scope, subject_id, metric_key, metric_version, computed_at);
```

The JSON payloads are validated against registered discriminated schemas before insertion. SQL alone does not validate every ratio, histogram, or event subtype. Missing foreign keys in this minimal excerpt must be completed in the real migration set; the excerpt must not be copied and mistaken for a finished database design.

### 18.3 Ingestion transaction protocol

For every page or bounded batch:

```text
acquire scoped fetch permission and current job fencing token
fetch under transport limits
sanitize secret-bearing metadata
write and verify immutable evidence objects
parse into candidate canonical records
validate schemas and domain invariants
begin transaction
    verify current job fencing token and lease
    insert deduplicated source records and canonical events
    record parser rejections and exact coverage
    insert outbox invalidation events
    commit next cursor and page-completion record
commit transaction
acknowledge batch completion
```

Object writes happen before the database references them. Unreferenced finalized objects can be garbage-collected later. Database failures do not require refetching unchanged content, but retries still verify the correct scope and digest.

Do not perform arbitrary network requests inside the database transaction. Do not hold row locks while waiting for a slow source host.

### 18.4 Pagination and completeness

Store the cursor and source query scope together. A cursor for “recent open issues” cannot be reused for “all issue history.” Track source filters, cutoff, ordering, page size, and provider truncation limits.

An absent next-page token establishes only completion according to the provider's response contract. The capability manifest still describes whether that endpoint omits older, private, deleted, or otherwise inaccessible objects.

When the source has unstable offset pagination, use overlap reconciliation and immutable object IDs. Completeness means the declared population was enumerated under documented assumptions, not that every fact about the project is known.

### 18.5 Job state machine

```text
queued -> leased -> running -> succeeded
                    |   |
                    |   +-> retry_wait -> queued
                    +-----> failed_terminal
queued/running -> canceled
leased/running with expired lease -> reclaimable
```

Store attempt history rather than replacing one error string. Distinguish permanent unsupported requests, authorization failures, rate-limit delays, transient network errors, malformed input, and resource-budget exhaustion.

A canceled job cannot later publish under an old lease. A stale worker can still finish an external fetch, but its result is rejected or retained as uncommitted evidence unless an active authorized job adopts it through the normal path.

### 18.6 Canonical result identity

A metric result identity includes subject, definition version, input-manifest digest, configuration digest, visibility scope, identity revision, graph projection, window, and algorithm implementation digest where relevant.

This supports safe caching and prevents a result computed under one actor merge or graph scope from being reused under another. Repeated execution can reuse an equivalent result only when the complete identity matches.

## 19. Algorithm implementation notes

### 19.1 Exact concentration implementation

Use integer event counts and rational arithmetic where feasible. Sort positive counts descending with a deterministic actor-ID tie-break for membership explanations. The count of actors reaching a share threshold is invariant to equal-count ordering, but the displayed membership set still needs deterministic ordering.

```text
input: actor counts x[1..n], threshold a/b
require: a > 0, b > 0, a <= b, all counts nonnegative
remove zero counts
if total == 0: return not_applicable
sort counts descending
cumulative = 0
for each count at position k:
    cumulative += count
    if cumulative * b >= total * a:
        return k
```

Use overflow-safe integer multiplication or arbitrary-precision/rational helpers where totals can exceed the chosen integer range. Unit tests include very large counts and thresholds exactly on a boundary.

HHI can be stored as `sum(x_i²) / total²`, retaining an exact rational value. The effective count is its reciprocal. Rounded decimal display must not become the stored authoritative value.

### 19.2 Persistence implementation

Build an actor-by-complete-month event-presence matrix from qualifying events. Compute active-month counts, first-to-last span, recent-month presence, and declared-role membership separately.

Do not count multiple commits on one day as multiple active months. Do not include the current partial month in a metric defined over complete months. Retain role/event filters in the result configuration.

The default profile can be changed, but changing it produces a new configuration digest and may require a new profile version. Historical comparisons must use equivalent definitions or clearly display the change.

### 19.3 Retention implementation

```text
for each eligible newcomer candidate:
    t0 = first observed qualifying event under the selected history policy
    return_interval = [t0 + start_days, t0 + end_days)
    if return_interval ends after cutoff:
        classify right_censored
    else if required coverage does not cover the return_interval:
        classify unobservable
    else:
        increment eligible_denominator
        if a qualifying event exists inside return_interval:
            increment retained_numerator
```

First-event eligibility may additionally require a complete lookback interval so established contributors are not misclassified as newcomers after a migration. Report how many candidates were excluded for that reason.

Return intervals are evaluated per actor. Do not approximate them by comparing annual totals or treating everyone active in two calendar years as 12-month retained.

### 19.4 Reverse-dependency traversal

Run traversal over a prefiltered graph projection so edge scope, version context, and visibility cannot be forgotten inside individual query handlers.

```text
visited = {subject}
frontier = [(subject, depth=0)]
results = empty set
while frontier is not empty:
    check time, memory, node, and edge budgets
    pop next node in deterministic order
    inspect incoming consumer edges allowed by the projection
    for each not-yet-visited consumer:
        if depth limit prevents expansion:
            record pending frontier and truncation
        else:
            mark visited
            add consumer to results
            enqueue consumer
remove subject from results
project to requested node kind using accepted mapping revision
deduplicate according to requested project-family policy
return results, scope, coverage, and truncation metadata
```

Keep path witnesses bounded. Enumerating every path through a graph with cycles or diamonds can explode even when the unique-node count is moderate. A few deterministic witness paths are sufficient to explain reachability; they are not the full path count.

### 19.5 Downstream aggregation

The input manifest lists dependent project IDs, their mapping provenance, and the exact intrinsic observations joined. For each requested downstream metric, calculate its own covered denominator.

Do not use one overall coverage number to imply that every intrinsic metric is available for the same projects. A dependent may have history coverage but no review data.

Weighted indices are a separate model layer. Basic counts and distributions remain accessible even when a user does not accept the model's weights.

### 19.6 Advisory matching

Normalize package identity using the ecosystem contract, evaluate ranges with a supported implementation, preserve advisory aliases and withdrawal revisions, and record applicability context. Unsupported ranges produce unknown matching status.

Do not remove a match merely because an advisory was later amended; retain historical known-time behavior. Do not attribute the advisory to a contributor unless a separate reviewed factual attribution exists and publication rules permit it.

### 19.7 Identity correction and invalidation

Store accepted identity edges, not only the resulting cluster. On revocation, recompute affected connected groups under the accepted policy. Generate a new identity revision and invalidate cluster-sensitive metrics and downstream derivations.

Raw source events retain source-native actor references. This makes the correction reversible and prevents one mistaken merge from permanently contaminating every historical record.

### 19.8 Trend and model calculations

Descriptive slopes and variances include exact window definitions and sample counts. An activity decline can be displayed without calling it deterioration in software quality.

Predictive models are never executed implicitly by the basic metric layer. Their training data, temporal cutoff, feature definitions, artifact digest, calibration report, and intended population are required inputs to the experimental model registry.

## 20. Comprehensive test strategy

### 20.1 Test pyramid

Unit tests validate parsers and formulas. Property tests validate invariants across many generated inputs. Integration tests validate storage, connectors, and orchestration. End-to-end tests validate real user workflows. Adversarial tests validate trust boundaries. Replay tests validate provenance. Performance tests validate limits rather than marketing claims.

No single layer substitutes for the others. A unit-tested formula can still be fed the wrong cohort by an API handler. A secure collector can still publish a misleading report if coverage is discarded downstream.

### 20.2 Golden fixture inventory

| Fixture ID | Scenario | Required result |
|---|---|---|
| F001 | Empty repository/history population. | Empty counts; undefined ratios not applicable. |
| F002 | Full history with multiple authors. | Exact counts and time windows. |
| F003 | Shallow clone. | No complete-lifetime claim. |
| F004 | Partial clone with missing blobs. | History metrics available; blob-dependent metrics partial. |
| F005 | Duplicate commits across mirrors. | Project-level deduplication under accepted mapping. |
| F006 | Cherry-pick with equivalent patch. | Distinct revisions; optional equivalence assertion. |
| F007 | Force-pushed branch. | Historical ref observations retained. |
| F008 | Future author timestamps. | Flagged source times; no silent manipulation of observed-time metrics. |
| F009 | Shared display name across accounts. | No automatic person merge. |
| F010 | Accepted identity link later revoked. | Derived metrics recomputed; raw events unchanged. |
| F011 | Known bot and unresolved account. | Stratified counts; unknown not forced human. |
| F012 | Many one-offs plus stable core. | No automatic negative one-off finding. |
| F013 | Few contributors, one release actor. | Concentration visible. |
| F014 | Review-only maintainer. | Maintenance activity represented without commit authorship. |
| F015 | Newcomer without follow-up time. | Retention censored. |
| F016 | Provider outage in return interval. | Retention unobservable, not failed. |
| F017 | Planned handover with overlap. | Explicit continuity and overlap measurements. |
| F018 | Diamond dependency graph. | Unique nodes counted once. |
| F019 | Dependency cycle. | Termination; subject excluded from own dependent count. |
| F020 | Multiple versions of one package. | Version and package counts distinguished. |
| F021 | Optional dependency disabled on target. | Context-specific resolved graph excludes inactive edge. |
| F022 | Unsupported version expression. | Unresolved/unknown, not guessed resolution. |
| F023 | False repository metadata claim. | Mapping remains unverified/conflicted. |
| F024 | Artifact bytes change under version label. | New artifact identity and finding evidence. |
| F025 | Advisory aliases. | Accepted aliases deduplicated; unrelated records preserved. |
| F026 | Advisory later withdrawn. | Current and historical-known results differ correctly. |
| F027 | Missing required policy input. | Unknown, not allow. |
| F028 | Deny plus unknown rule. | Overall deny; individual unknown preserved. |
| F029 | Expired exception. | Exception no longer authorizes admission. |
| F030 | Private dependent connected to public package. | No public identity/count leakage. |
| F031 | Duplicated webhook/page delivery. | Exactly one analytical event. |
| F032 | Worker lease expires during fetch. | Stale worker cannot commit publication. |
| F033 | Object finalized before DB failure. | Safe retry and eventual orphan cleanup. |
| F034 | Evidence blob missing/corrupt. | Replay fails explicitly; no fabricated success. |
| F035 | SSRF through redirect or submodule. | Fetch blocked; source token not forwarded. |
| F036 | Archive traversal/compression bomb. | Bounded rejection without unsafe extraction. |
| F037 | Malicious README instructions. | Treated as data; policy unaffected. |
| F038 | Metric version changes denominator. | Historical versions remain distinct. |
| F039 | Graph budget exhaustion. | Truncation metadata; no exact-total claim. |
| F040 | External feed becomes unavailable. | Stale/unknown source status; other capabilities remain usable. |

### 20.2a Research conformance fixtures

Use `RP-F01`–`RP-F48` to refer to the paper's [Appendix C](REPO_HEALTH_RESEARCH_PAPER.md#appendix-c-proposed-conformance-fixture-catalog); these must not collide with local F001–F040. The paper reports 16 miniature checks in Appendix D, not 48 completed integration tests. The local `ops/research-conformance.json` ledger records the product-path crosswalk: all 48 cases are covered with no remaining partial assertions. Do not cite the paper's Appendix D helper results as locally rerun evidence.

| Research cases | Owning work packages | Required product-path evidence |
|---|---|---|
| RP-F01–F09 | M02-09 | Duplicate/page/crash/lease/watermark/backdating and capability failures preserve events and missingness. |
| RP-F10–F18 | M03-10, M05-10 | Host namespaces, aliases, migrations, mirrors, forks, multi-package projects, relation types and capped populations. |
| RP-F19–F26 | M00-10, M03-10/11, M02-09 | Declared/resolved separation, parser loss, unsupported/empty/failed snapshot replacement and transformation-aware cache keys. |
| RP-F27–F30 | M03-11, M05-10 | Diamond/cycle traversal, repeated resolution instances and environment differences. |
| RP-F31–F42 | M04-10 | Reversible grouping, unknown affiliations, threshold/tie/empty behavior, eligible cohorts, role grain and join cardinality. |
| RP-F43–F47 | M00-09/10, M06-09 | Shared assessment lineage, probe polarity, inconclusive inputs, visible coverage and definition changes. |
| RP-F48 | M04-10, M07-08 | Correction/suppression invalidates affected views and updates retention/replayability labels. |

Each case needs retained inputs, expected canonical objects/statuses, independent expected observations, an owning test path, and a recorded execution result before validation. Reuse existing local fixtures where equivalent, but document the crosswalk and missing assertions. These cases supplement each milestone's existing exit gate; a synthetic helper passing alone cannot close an adapter or end-to-end gate.

### 20.3 Property tests

Adding a duplicate source record must not change counts. Reordering independent events must not change deterministic results. Splitting one account into unresolved aliases must not silently claim a larger number of unique people. Revoking an accepted mapping must remove its projected edges in new snapshots.

The sum of contributor shares equals one for a complete nonempty attributed population. HHI lies between `1/n` and `1` for `n` positive contributors. The effective actor count lies between one and `n`. Concentration counts are monotone in their requested share threshold.

For a fixed graph and scope, increasing the depth limit cannot reduce the exact reachable-node set before other budgets intervene. Public results cannot depend on private edges unless a separately approved publication mechanism explicitly permits that aggregation.

### 20.4 Mutation tests

Deliberately change unknown to zero, remove a graph visited-set check, ignore an identity revision in a cache key, drop a pagination cursor transaction, treat a tag as a release, or sum daily unique cloners. The corresponding tests must fail.

Mutation testing is especially valuable for invariants that are easy to accidentally simplify during AI-assisted refactoring.

### 20.5 Provider fixtures and live tests

Sanitize fixtures without removing behavior essential to the test. Maintain schema-version labels and source retrieval dates. Do not put credentials or unnecessary personal data into recorded responses.

Live tests use approved test repositories and scoped tokens. They do not create unsolicited issues or modify third-party projects. Distinguish a provider outage from a code regression in test reporting.

### 20.6 Security test success criteria

A blocked attack is successful only when the sensitive destination or operation was not reached, not merely when the API eventually returned an error. Use network/process/file canaries to verify the boundary.

Resource tests measure actual peak memory, output bytes, child-process count, and cancellation latency. A timeout that leaves a runaway child process is a failed test.

### 20.7 Report and documentation tests

Validate every structured example. Check reference links, metric keys, definition versions, enum values, and command names against the current schema. Test that reports label synthetic examples and do not display a generic “safe” conclusion.

For key user-facing explanations, snapshot the text parameters and assert that coverage caveats remain present when required. A UI redesign must not remove uncertainty merely to fit a smaller card.

## 21. Performance validation and capacity planning

### 21.1 Benchmark harness

The harness generates repeatable histories and graphs from a fixed seed and writes a workload manifest. Each benchmark records dataset digest, code revision, compiler settings, database configuration, hardware, operating system, concurrent jobs, cache state, and repetition count.

Report median and tail latency, throughput, resource use, and error/truncation rates. Do not compare two runs with different graph scopes or cache conditions as though the difference measured an optimization.

### 21.2 Workload classes

**Local scan:** many small commits, a few large commits, merge-heavy history, old imported history, shallow repositories, and very large trees.

**Ingestion:** many small API pages, large metadata records, duplicate delivery, bursty webhooks, late edits, and high source latency.

**Graph:** chains, diamonds, cycles, high-degree popular dependencies, many versions, optional contexts, and cross-scope edges.

**Analytics:** long contributor histories, frequent identity corrections, complete versus partial cohorts, and large downstream joins.

**Publication:** cached summaries, evidence drill-down, bounded graph views, report exports, and policy checks under mixed freshness.

### 21.3 Capacity worksheet

Measure, rather than assume, the following quantities:

```text
average and p95 retained evidence bytes per fetched object
revisions and tree objects per scanned repository
API requests per capability refresh
CPU time per parsed revision and manifest
normalized bytes per event and edge
metric observations materialized per project/profile
correction invalidation fan-out
high-degree graph query memory
backup size and verified restore duration
```

Use these measured distributions to estimate an intended deployment. Include safety margins and source quotas. Cost estimates should clearly separate one-time historical backfill from ongoing incremental refresh.

### 21.4 Performance gates

A release passes when it meets its declared workload targets without dropping correctness or safety checks. If a target is missed, publish the measured limit and reduce supported workload or optimize; do not remove denominator checks or graph deduplication to obtain a favorable number.

Any approximate mode must be explicit and separately tested. Exact policy thresholds cannot unknowingly consume approximate values.

## 22. Operational runbooks

### 22.1 Provider outage or API change

Pause failing capability jobs with backoff, preserve the last successful cursor, mark affected observations stale/partial, and suppress project-health alerts caused solely by coverage loss. Notify operators through service-health channels.

Capture a sanitized response sample, update compatibility tests, and deploy a versioned connector correction. Reconcile the affected interval before declaring coverage restored.

### 22.2 Incorrect identity merge

Freeze publication of affected person-sensitive results where necessary. Revoke the incorrect assertion, create a new identity revision, recompute impacted metrics and graph projections, and publish correction notices for materially affected reports.

Do not delete raw source events to make the correction easier. Record the cause and add a regression fixture that reproduces the mistaken merge.

### 22.3 Corrupted evidence or projection

Stop publishing derived results from the corrupted inputs. Verify object digests, compare with backup manifests, and restore or refetch permitted evidence. Rebuild projections from authoritative records.

Mark affected reports as not currently replayable until verification succeeds. Do not silently substitute live data into a report claiming a historical pinned input set.

### 22.4 Credential exposure

Revoke the credential, stop relevant jobs, inspect access logs, identify affected evidence/log payloads, and rotate dependent secrets. Review whether a redirect, debug log, source error body, or plugin boundary caused the exposure.

Restore service only after the leak path has a regression test. The incident record avoids redistributing the secret itself.

### 22.5 Misleading mass alert

Pause the offending rule version, preserve its input sets, and separate data defects from rule-design defects. Retract or supersede false findings with an explanation. Re-evaluate affected projects after correction.

A rule rollout should have shadow mode and a maximum alert-volume circuit breaker so a parser bug cannot immediately publish thousands of abandonment warnings.

### 22.6 Source operator removal request

Locate source-specific data rights and contact records. Suspend collection if required while the request is reviewed. Apply the accepted deletion or publication restriction to raw evidence, projections, caches, and exports according to policy.

Record resulting replay limitations. Do not continue crawling through an alternate mirror merely to evade an access restriction.

### 22.7 Backup restore

Restore the database and evidence manifest to a clean environment, verify digest integrity, rebuild selected projections, replay representative reports, and compare policy outputs. Record what was restored, what was unavailable, and the resulting service state.

A backup that has never been restored is not sufficient operational evidence for the release gate.

## 23. Risk register and mitigation ownership

| Risk | Failure mode | Mitigation | Owning workstream |
|---|---|---|---|
| Scope explosion | Hundreds of partial connectors and metrics; no useful end-to-end product. | Vertical slices, explicit support matrix, milestone gates. | Product/integration |
| GitHub-centric design | Non-GitHub projects appear unhealthy or unsupported by the domain. | Generic VCS baseline, multiple early adapters, capability states. | Domain/connectors |
| Metric overinterpretation | Commit counts become trust or quality claims. | Exact contracts, independent dimensions, wording review. | Metrics/research |
| Identity mistakes | Two contributors merged or one person overcounted. | Conservative reversible assertions, revisioned clusters. | Identity/privacy |
| Selection bias | Popular projects dominate coverage and comparison baselines. | Multiple discovery sources and explicit coverage strata. | Data/research |
| Circular reputation | Dependents and dependencies manufacture one another's health. | Intrinsic metrics independent from adoption models. | Graph/metrics |
| Dependency ambiguity | Version ranges presented as deployed exact dependencies. | Requirement/resolution separation and context bindings. | Packages/graph |
| Source API changes | Silent missing data or duplicate records. | Contract fixtures, capability monitoring, reconciliation. | Connectors/operations |
| External feed retirement | Stale enrichment treated as current. | Source lifecycle review and freshness propagation. | Data/operations |
| SSRF and parser compromise | Collector attacks internal services or executes source commands. | Restricted transport, isolation, fuzzing, resource limits. | Security/collectors |
| Private graph leakage | Public totals reveal a customer's dependencies. | Scope-aware projections/caches and adversarial tests. | Security/storage |
| Gaming | Fake stars, forks, commits, or packages inflate findings. | Avoid volume-based trust; deduplicate and separate evidence. | Metrics/graph |
| Volunteer harm | Reports shame maintainers or infer personal motives. | Project-level framing, neutral metrics, corrections. | Product/privacy |
| Operational overload | Expensive scans starve basic freshness. | Cost tiers, quotas, fair scheduling, graceful degradation. | Operations |
| Method drift | Same metric key changes meaning over time. | Versioned definitions, immutable historical results. | Metrics/governance |
| Commercial conflicts | Paying projects receive hidden favorable treatment. | Public methodology and conflict disclosure. | Governance |

Every serious risk should map to at least one fixture, operational monitor, or review gate. A risk register without executable follow-through is documentation, not mitigation.

## 24. Team structure and AI-assisted implementation

### 24.1 Suggested workstreams

Separate domain/measurement semantics, collectors/security, packages/graph, product/API, and operations/privacy. A small team can cover multiple workstreams, but code review should cross the relevant trust boundary.

The most important early coordination is between metric definitions and data collection. Collectors must know what evidence a metric requires; metrics must know what a source actually exposes.

### 24.2 Good tasks for coding agents

Agents can implement schema-validated parsers, adapters behind fixed contracts, fixture generators, deterministic formulas, migration tests, documentation checks, and narrowly scoped UI components.

Assign bounded tasks with explicit input/output contracts and adversarial tests. Require a change summary, tests run, untested cases, and any deviation from the contract. Do not reward output volume or a large number of generated metric files.

### 24.3 Human review boundaries

Require explicit review for identity-merge rules, privacy/publication policy, source access terms, security-sensitive transport changes, arbitrary-execution capabilities, new composite scores, new prediction outcomes, and changes to missing-data behavior.

An agent may propose these changes, but it should not silently redefine them while completing an unrelated task.

### 24.4 Agent task template

```text
Task:
Implement one named capability or metric against the approved contract.

Required inputs:
List schemas, fixtures, source docs, and existing interfaces.

Required outputs:
List code paths, tests, documentation, and expected report behavior.

Invariants:
Unknown is not zero. No hidden network calls in metrics.
No source-code execution. No new identity assumptions.
No changes to unrelated metric definitions.

Validation:
Run specified unit, property, integration, and negative tests.
Report exact results and any tests not run.

Completion:
The real execution path uses the implementation.
No hardcoded fixture values, silent fallbacks, or success placeholders.
```

### 24.5 Integration discipline

Use small pull requests, migration compatibility checks, fixture-first changes, and a stable integration branch. Parallel agents should work behind agreed interfaces and avoid broad simultaneous refactors of domain types.

Maintain an architecture decision log. When a change conflicts with these documents, update the decision and tests explicitly rather than letting the specification and implementation quietly diverge.

## 25. Initial executable backlog

The original bootstrap ordering below remains a dependency reference. Reconcile it with existing implementation evidence before repeating work. The research follow-up queue in §25.1 takes priority over optional breadth and metric expansion; mandatory correctness and release gates remain in force.

| Order | Task | Tangible completion artifact |
|---|---|---|
| 1 | Create repository baseline and ADR-000. | Toolchain, license decision, local checks, status statement. |
| 2 | Implement identifiers, intervals, and observation states. | Passing domain/schema tests. |
| 3 | Create metric-definition schema and linter. | Rejection of invalid units, duplicate versions, missing denominator rules. |
| 4 | Build synthetic history and graph fixtures. | Independent expected-output manifests. |
| 5 | Implement bounded subprocess and public-URL policy. | Hostile-input and resource-limit tests. |
| 6 | Implement local bare-Git metadata extraction. | Real normalized events from fixture repositories. |
| 7 | Implement evidence bundle and digest verification. | Offline replay input directory. |
| 8 | Implement the first ten foundational metrics. | Exact values and unavailable states with provenance. |
| 9 | Add JSON/Markdown report and explain command. | Useful local report with no fake global claims. |
| 10 | Extend to the initial 30–40 metric subset. | Explicit implemented-support list. |
| 11 | Add PostgreSQL ingestion, cursor transaction, and lease tests. | Crash-safe durable collection. |
| 12 | Add first forge adapter and controlled-instance fixtures. | Reviews/issues/releases normalized. |
| 13 | Add second forge plus generic self-hosted URL support. | Cross-forge domain invariance tests. |
| 14 | Implement package identity and first lockfile parser. | Exact contextual dependency graph. |
| 15 | Add second ecosystem and advisory matching. | Unknown ranges and known matches correctly separated. |
| 16 | Implement persistent cohorts and role concentration. | Continuity comparison fixtures passing. |
| 17 | Add temporal reverse dependencies and downstream condition. | Reproducible observed-graph report. |
| 18 | Implement four-valued policy evaluation. | No unknown-to-allow fallback. |
| 19 | Complete security/privacy/rights and restore reviews. | Beta gate evidence packet. |
| 20 | Conduct opt-in maintainer pilot and correct defects. | Published limitations and validated beta scope. |

The first ten tasks should result in a useful tool even before a hosted service exists. Tasks 14–18 establish the distinctive ecosystem and agent-admission capabilities rather than postponing them indefinitely.

### 25.1 Research follow-up queue

Rows below distinguish completed research artifacts from remaining acceptance work. A `covered` case in the RP-01 ledger means its named local test asserts the invariant; `partial` keeps the missing assertion visible.

| Order | Work / owner | Dependencies | Completion artifact |
|---|---|---|---|
| RP-01 | Reconcile current code/status and research fixture coverage / core + QA | Existing baseline | `ops/research-conformance.json` and `tests/test_research_conformance.sh` map all RP-F01–48 cases to paths/tests; all 48 covered, no Appendix D overclaim. **Implemented crosswalk; no partial assertions remain.** |
| RP-02 | Evidence envelope, lineage, transformation losses and semantic crosswalk / core | RP-01 | `src/rh_lineage.elisa`, `rh-lineage-result/1`, and `tests/test_lineage_cli.sh` preserve delivery/origin identity, transformations, metric classes, and loss metadata. **Implemented product path.** |
| RP-03 | Watermark, lease and snapshot semantics / ingestion | RP-02 | `src/rh_ingest_conformance.elisa`, `rh-ingest-result/1`, and `tests/test_ingest_conformance_cli.sh` cover durable event-before-cursor replay, duplicate absorption, successful empty, failed/partial preservation, and stale fencing. The fixture also pins collection start, reports one late/backdated event, and records that reconciliation is required. |
| RP-04 | One lookup/parser integration and graph-instance identity / packages | RP-02–03 | `src/rh_adapter_manifest.elisa`/`rh-adapter-manifest-result/1` plus existing parser-diff and resolution paths pin reviewed source/rights, interface, cache identity, and graph snapshot context. **Implemented product path; provider adoption remains bounded.** |
| RP-05 | Role/event grain and reversible identity corrections / continuity | RP-02–03 | `src/rh_role_grain.elisa`, `rh-role-grain-result/1`, and `tests/test_role_grain_cli.sh` cover one-event/one-role cardinality, distinct actor counts, threshold inputs, and current-corrected/as-known correction fan-out. **Implemented product path.** |
| RP-06 | Focal-library downstream slice / graph + reports | RP-04–05 | `src/rh_population.elisa`, `rh-population-result/1`, and `tests/test_population_cli.sh` report bounded selected population, family deduplication, path witnesses, unresolved mappings, per-metric coverage/distributions, and policy unknowns. **Implemented product path.** |
| RP-07 | Structured findings and evidence drill-down / policy + reports | RP-02, RP-06 | `src/rh_drilldown.elisa`, `rh-evidence-drilldown/1`, and `tests/test_drilldown_cli.sh` bind lineage to findings and retain source payload/transformation metadata; findings polarity/missingness remain version-bound. **Implemented product path.** |
| RP-08 | Pilot and operational adoption review / operations + QA | RP-03–07 plus existing M07 gates | `rh_cli pilot-review` and `rh-pilot-review-result/1` now record manual mapping review, correction effort, decision-usefulness inputs, provider-outage behavior, and measured costs with a non-audit caveat. Independent maintainer pilot, correction-effort sample, and governance sign-off remain open. |

Only after these artifacts pass should additional collectors, breadth providers, shared metric projections or distributed infrastructure be scheduled. Candidate integrations that fail the adoption gate remain disabled with an explicit reason; the canonical local evidence path must remain useful.

## 26. Release evidence packet

Every public release should include a machine-readable and human-readable record of:

- Supported source instances/families, capabilities, and format versions.
- Implemented metric keys and definition versions.
- Known missing or experimental capabilities.
- Source/data-rights review status and redistribution boundaries.
- Test results, security review scope, and unresolved limitations.
- Performance workload manifest and measured results.
- Database/schema migration instructions and rollback limitations.
- Evidence retention and replayability guarantees actually provided.
- Correction procedure and operator incident contacts.

Do not present a roadmap feature as a released feature. Do not hide unsupported metrics behind a generic score that appears complete.

## 27. Success measurements for repo-health itself

Measure whether reports are factually correct, whether users understand limitations, whether corrections are processed, whether alerts are useful, and whether observed source coverage is improving.

Useful initial measures include replay match rate, fraction of displayed observations with complete lineage, false findings in reviewed pilot samples, correction turnaround, source-freshness distributions, cross-forge capability parity, and the proportion of policy unknowns that correctly identify a specific missing input.

Longer-term value measures can include documented dependency changes, resolved support requests, added release-role redundancy, and maintained alternatives discovered through the graph. These are observable outcomes. Claims about prevented global harm require much stronger evidence and should not be inferred from usage counts.

The product's own growth metrics—downloads, stars, or number of indexed repositories—are not substitutes for its mission. A smaller, accurate, explainable observatory can be more useful than a huge dataset of misleading confidence.

## 28. Primary implementation references

These primary sources were checked while preparing the design and the current implementation changes on 2026-09-20. Revalidate provider behavior and pin supported interfaces during each connector implementation. The companion architecture contains the broader reference list and source-specific support boundaries.

[P01]: https://docs.github.com/en/rest/metrics/traffic "GitHub traffic API and authorization/reporting limitations"
[P02]: https://docs.deps.dev/api/v3/ "deps.dev package/dependency API and coverage"
[P03]: https://google.github.io/osv.dev/ "OSV vulnerability API and data model"
[P04]: https://www.chaoss.community/kb/metric-contributor-absence-factor/ "CHAOSS Contributor Absence Factor"
[P05]: https://cheatsheetseries.owasp.org/cheatsheets/Server_Side_Request_Forgery_Prevention_Cheat_Sheet.html "OWASP SSRF prevention guidance"
[P06]: https://git-scm.com/docs/git-clone "Git clone behavior and partial/shallow retrieval"
[P07]: https://spdx.github.io/spdx-spec/v2.3/ "SPDX 2.3 compatibility target"
[P08]: https://cyclonedx.org/specification/overview/ "CycloneDX inventory specification overview"
[P09]: https://github.com/ossf/criticality_score "Criticality Score data availability notice"
[P10]: https://reproducible-builds.org/docs/definition/ "Reproducible Builds definition"
[P11]: https://www.postgresql.org/docs/current/explicit-locking.html "PostgreSQL transactional locking primitives"
[P12]: https://ecosyste.ms/ "ecosyste.ms optional data and tooling services"
[P13]: https://google.github.io/osv.dev/post-v1-query/ "OSV package/version query request, response, and pagination contract"
[P14]: https://google.github.io/osv.dev/post-v1-querybatch/ "OSV ordered package query batch and per-query result contract"
[P15]: https://google.github.io/osv.dev/get-v1-vulns/ "OSV full vulnerability record lookup by ID"
[P16]: https://doc.rust-lang.org/nightly/nightly-rustc/cargo/resolver/resolve/enum.ResolveVersion.html "Cargo lockfile versions and unstable version 5 status"
[P17]: https://docs.npmjs.com/cli/v11/configuring-npm/package-lock-json/ "npm package-lock version semantics and layouts"
[P18]: https://www.w3.org/TR/sri-2/ "Subresource Integrity metadata grammar, algorithm priority, and reserved options"
[P19]: https://go.dev/ref/mod#go-sum-files "Go module checksum records and h1 SHA-256 Base64 encoding"
[P20]: https://go.dev/src/cmd/vendor/golang.org/x/mod/sumdb/dirhash/hash.go "Go h1 directory hash construction and ZIP file-content hashing"
[P21]: https://learn.microsoft.com/en-us/nuget/consume-packages/package-references-in-project-files "NuGet lock files and per-target-framework resolved dependency closures"
[P22]: https://github.com/NuGet/Home/wiki/Enable-repeatable-package-restore-using-lock-file "NuGet lock file format and package dependency/content-hash fields"
[P23]: https://cyclonedx.org/guides/sbom/external-references "CycloneDX composition completeness aggregates and scoped assertions"
[P24]: https://docs.npmjs.com/cli/v11/commands/npm-deprecate/ "npm version deprecation messages and empty-message undeprecation"
[P25]: https://learn.microsoft.com/en-us/nuget/api/registration-base-url-resource "NuGet registration catalog deprecation metadata"
[P26]: https://docs.npmjs.com/cli/v11/configuring-npm/npm-shrinkwrap-json/ "npm-shrinkwrap package-lock format and precedence"
[P27]: https://doc.rust-lang.org/nightly/nightly-rustc/src/cargo_util_schemas/lockfile.rs.html "Cargo serialized lockfile schema, separated root, and legacy checksum metadata"
[P28]: https://docs.ecosyste.ms/docs/guides/first-api-call/ "ecosyste.ms packages lookup route and optional ecosystem query"
[P29]: https://docs.ecosyste.ms/docs/usage/licences/ "ecosyste.ms data licence and attribution requirements"
[P30]: https://creativecommons.org/licenses/by-sa/4.0/ "Creative Commons Attribution-ShareAlike 4.0 International licence"
[P31]: https://docs.ecosyste.ms/docs/usage/authentication/ "ecosyste.ms unauthenticated shared request pools and user-agent/mailto identification"
[P32]: https://classic.yarnpkg.com/en/docs/yarn-lock "Yarn Classic v1 lockfile selectors and resolved dependency records"
[P33]: https://github.com/pnpm/spec/blob/master/lockfile/9.0.md "pnpm lockfile v9 packages, snapshots, peer paths, and importer resolutions"
[P34]: https://docs.github.com/en/rest/about-the-rest-api/api-versions "GitHub REST API supported versions and version header"

| Reference | Implementation use |
|---|---|
| [P01] | Optional traffic adapter; interval deduplication and access-state tests. |
| [P02] | Optional package/version enrichment with explicit coverage. |
| [P03] | Advisory matching, source identities, and range-support handling. |
| [P04] | Compatibility with the named 50% concentration definition. |
| [P05] | Public-URL transport threat model and adversarial cases. |
| [P06] | Git acquisition behavior and coverage flags. |
| [P07] / [P08] | Versioned software-inventory import contracts. |
| [P09] | Source lifecycle/freshness review; no assumed live cloud dataset. |
| [P10] | Distinguishing successful builds from reproducible builds. |
| [P11] | Transactional foundation for durable scheduling and ingestion. |
| [P12] | Optional metadata reuse after terms, rights, and provenance review. |
| [P13] / [P14] / [P15] | OSV single-query full advisory evidence, bounded ordered batch summaries, and full-record lookup by returned ID. |
| [P16] / [P17] | Pin accepted Cargo/npm lockfile revisions and reject unsupported declared revisions. |
| [P18] | Apply SRI strongest-algorithm selection and option-token parsing to npm integrity verification. |
| [P19] | Validate Go `h1` checksums as canonical Base64 SHA-256 before accepting checksum evidence. |
| [P20] | Verify Go `.mod` and module ZIP h1 values with Go's one-file and `HashZip`/`Hash1` semantics, within explicit ZIP/DEFLATE bounds. |
| [P21] / [P22] | Parse only the declared NuGet lock subset, preserve target-framework and content-hash evidence, and reject unsupported format versions and multi-target ambiguity. |
| [P23] | Preserve CycloneDX composition completeness by declared scope and avoid upgrading partial or unknown assertions into a whole-inventory claim. |
| [P24] / [P25] | Normalize npm and NuGet deprecation notices without treating missing signals in other providers as non-deprecation. |
| [P27] | Preserve Cargo's optional separated root and map legacy checksum metadata to one exact name/version/source package identity. |
| [P28] / [P29] / [P30] / [P31] | Constrain ecosyste.ms to its documented one-package GET route; retain source attribution, the CC BY-SA 4.0 licence link, modification notice, and shared-quota failure semantics. |
| [P32] | Pin Yarn support to Classic lockfile v1, resolve exact selectors, and keep other Yarn revisions outside this parser. |
| [P33] | Pin pnpm support to lockfile v9.0; join exact importer and snapshot versions while preserving peer-suffixed paths as distinct resolution nodes. |

## 29. Final implementation rule

> **Never make the system look more knowledgeable than its evidence allows.**

A correct unknown is better than an invented measurement. A clearly scoped observed graph is better than a false claim of complete ecosystem visibility. A concrete maintenance-continuity report is better than a vague contributor-trust score. A small, replayable end-to-end implementation is better than a large collection of disconnected dashboards.

Build outward from that foundation, and repo-health can become both a useful everyday development tool and a durable observatory of the software infrastructure on which other systems depend.
