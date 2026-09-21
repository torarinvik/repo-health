# repo-health — Architecture

**Document version:** 0.1.0  
**Status:** Proposed architecture; not a statement of implemented functionality  
**Prepared:** 2026-09-18  
**Companion:** [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md)  
**Primary audience:** Project founders, implementers, maintainers, data engineers, security reviewers, researchers, and authors of coding-agent integrations

> **Mission:** Make the condition of open-source software infrastructure observable, explainable, and actionable—so that humans and automated development tools can choose dependencies more responsibly, detect deteriorating foundations, and direct help toward important projects before preventable failures occur.

This document specifies a forge-agnostic, evidence-first, temporal observatory of open-source projects and their relationships. Its central object is not a repository popularity score. It is a time-aware software knowledge graph with independently inspectable measurements of development, maintenance, dependencies, downstream use, engineering practices, and continuity of stewardship.

The design deliberately separates facts from interpretations. A recorded commit, a public release timestamp, a dependency declaration, an authenticated package publication, and an observed review are evidence. “Reliable,” “healthy,” “trusted,” and “at risk” are interpretations that require an explicit definition, a declared scope, and sufficient evidence. No implementation may silently collapse this distinction.

All example projects, accounts, quantities, policies, and thresholds in this document are synthetic unless explicitly attributed to a source. Proposed endpoint names, commands, schemas, and configuration formats are design contracts, not existing tools. External capabilities were checked against the primary references listed at the end; connectors must revalidate them during implementation.

## Contents

- [1. Product definition and scope](#1-product-definition-and-scope)
- [2. Non-negotiable design principles](#2-non-negotiable-design-principles)
- [3. Product capabilities and workflows](#3-product-capabilities-and-workflows)
- [4. Relationship to existing infrastructure](#4-relationship-to-existing-infrastructure)
- [5. Logical system architecture](#5-logical-system-architecture)
- [6. Canonical data model](#6-canonical-data-model)
- [7. Source acquisition and connector architecture](#7-source-acquisition-and-connector-architecture)
- [8. Contributor identity, roles, and continuity](#8-contributor-identity-roles-and-continuity)
- [9. Dependency graph semantics and analytical projections](#9-dependency-graph-semantics-and-analytical-projections)
- [10. Metric engine and measurement contracts](#10-metric-engine-and-measurement-contracts)
- [11. Extensive metric catalog](#11-extensive-metric-catalog)
  - [11.1 Repository history and collection scope](#111-repository-history-and-collection-scope)
  - [11.2 Development activity and trajectory](#112-development-activity-and-trajectory)
  - [11.3 Contributor participation](#113-contributor-participation)
  - [11.4 Persistence and retention](#114-persistence-and-retention)
  - [11.5 Maintainer roles and authority evidence](#115-maintainer-roles-and-authority-evidence)
  - [11.6 Concentration and operational redundancy](#116-concentration-and-operational-redundancy)
  - [11.7 Succession and continuity of responsibilities](#117-succession-and-continuity-of-responsibilities)
  - [11.8 Change proposals and review process](#118-change-proposals-and-review-process)
  - [11.9 Issues and responsiveness](#119-issues-and-responsiveness)
  - [11.10 Releases and supported versions](#1110-releases-and-supported-versions)
  - [11.11 Direct dependencies and resolution](#1111-direct-dependencies-and-resolution)
  - [11.12 Dependency changes and freshness](#1112-dependency-changes-and-freshness)
  - [11.13 Downstream adoption counts](#1113-downstream-adoption-counts)
  - [11.14 Downstream condition and feedback](#1114-downstream-condition-and-feedback)
  - [11.15 Graph structure and ecosystem criticality](#1115-graph-structure-and-ecosystem-criticality)
  - [11.16 Advisories and security exposure](#1116-advisories-and-security-exposure)
  - [11.17 Supply-chain provenance and artifact integrity](#1117-supply-chain-provenance-and-artifact-integrity)
  - [11.18 Build and CI observations](#1118-build-and-ci-observations)
  - [11.19 Testing, fuzzing, and regressions](#1119-testing-fuzzing-and-regressions)
  - [11.20 Codebase and static-analysis observations](#1120-codebase-and-static-analysis-observations)
  - [11.21 Documentation and onboarding](#1121-documentation-and-onboarding)
  - [11.22 Compatibility and interface stability](#1122-compatibility-and-interface-stability)
  - [11.23 Governance and organizational continuity](#1123-governance-and-organizational-continuity)
  - [11.24 Funding and maintenance support](#1124-funding-and-maintenance-support)
  - [11.25 Licensing and distribution metadata](#1125-licensing-and-distribution-metadata)
  - [11.26 Downloads, traffic, and references](#1126-downloads-traffic-and-references)
  - [11.27 Forks, mirrors, and recovery options](#1127-forks-mirrors-and-recovery-options)
  - [11.28 Data quality, provenance, and observability](#1128-data-quality-provenance-and-observability)
  - [11.29 Policy findings and intervention outcomes](#1129-policy-findings-and-intervention-outcomes)
  - [11.30 Advanced evidence and explicitly experimental analytics](#1130-advanced-evidence-and-explicitly-experimental-analytics)
- [12. Findings, interpretation, and policy evaluation](#12-findings-interpretation-and-policy-evaluation)
- [13. Persistence, storage, and query design](#13-persistence-storage-and-query-design)
- [14. APIs, CLI, and evidence interchange](#14-apis-cli-and-evidence-interchange)
- [15. User interface and reporting](#15-user-interface-and-reporting)
- [16. Security and threat model](#16-security-and-threat-model)
- [17. Privacy, data rights, and governance](#17-privacy-data-rights-and-governance)
- [18. Statistical validity and interpretation limits](#18-statistical-validity-and-interpretation-limits)
- [19. Performance, scheduling, and operating costs](#19-performance-scheduling-and-operating-costs)
- [20. Worked example: continuity, upstream risk, and downstream condition](#20-worked-example-continuity-upstream-risk-and-downstream-condition)
- [21. Architectural decisions and open questions](#21-architectural-decisions-and-open-questions)
- [22. Definition of architectural success](#22-definition-of-architectural-success)
- [23. Primary references and verification notes](#23-primary-references-and-verification-notes)

## 1. Product definition and scope

### 1.1 The problem being addressed

A dependency decision is not just a decision about current API behavior. It also creates reliance on people, release processes, upstream packages, publishing infrastructure, and the downstream ecosystem that discovers defects and funds maintenance. repo-health makes these relationships visible without pretending that visibility is a proof of safety.

The project is intended to answer questions such as:

- Does this project have a persistent maintenance core, or merely a large historical contributor list?
- Is maintenance distributed across several people, or concentrated in one account that performs most releases and reviews?
- Are apparently quiet periods normal for this kind of mature software, or part of a longer change in maintenance activity?
- Which dependencies introduce known maintenance, provenance, or security concerns into an application?
- Which active projects currently depend on this package, and what is the condition of those dependent projects?
- Are users adopting recent releases, remaining on older supported branches, or replacing the package?
- How much of a conclusion is actually supported by observed data, and how much is unobserved?
- Which important projects could benefit from funding, a second release maintainer, improved testing, or a documented succession process?

A project may be widely used and fragile. It may be small and well maintained. It may have excellent continuity but an affected dependency. It may have few recent commits because it is stable. These are different situations and must remain distinguishable.

### 1.2 The four primary analytical views

**Intrinsic condition** describes evidence inside a project: maintenance continuity, contributor participation, review activity, releases, documented practices, test results, and direct technical observations.

**Upstream exposure** describes what the project depends on: exact versions where known, unresolved requirements where not, advisory matches, concentration of dependencies under common control, and maintenance concerns along dependency paths.

**Downstream ecosystem condition** describes projects that depend on it: their independent activity and stewardship measurements, recency of dependency observations, upgrade behavior, contribution feedback, and distribution across unrelated project families.

**Criticality and resilience** describe how much observed infrastructure relies on the project and how replacement, replication, succession, and maintenance alternatives affect recovery. Criticality is not safety. Centrality is not social importance. Resilience is not the absence of vulnerabilities.

Each view is accompanied by a fifth, mandatory view: **evidence coverage and uncertainty**.

### 1.3 Intended users

The initial users are maintainers inspecting their own projects, developers comparing dependencies, and coding agents requesting evidence before adding packages. Later users include organizations maintaining software inventories, ecosystem stewards coordinating support, security teams investigating dependency exposure, and researchers studying longitudinal software maintenance.

Maintainer-facing reports should be useful even when the project is not popular. A public-interest observatory must not reserve detailed explanations exclusively for large organizations or highly starred projects.

### 1.4 What “all repositories and source-code sites” means

The architecture must not require a particular forge, version-control system, issue tracker, or package registry. Any source can be integrated through an adapter or an evidence-import format.

This is an architectural extensibility commitment, not a claim that every site can be completely crawled. Some sites have no public API, block automated access, expose only source archives, use private trackers, or retain little history. Their missing capabilities must be represented rather than fabricated.

A supported source has an explicit capability matrix. The minimum useful source might expose only a downloadable release artifact and timestamps. A richer source may expose history, changes, reviews, releases, issues, publishing roles, and authorized traffic statistics.

### 1.5 Non-goals

repo-health is not a proof that a package is secure, a replacement for testing or audits, a universal vulnerability scanner, or an employee-performance system. It must not assign people moral trustworthiness, infer their personal health, or rank their worth from public activity.

It is not a source-code execution service in its initial form. Collecting metadata does not require running arbitrary build scripts. It is not a package manager, although package managers and policy engines can consume its outputs.

It is not an unrestricted crawler of private infrastructure, an archive of every personal statement made by contributors, or a source of precise global installation counts. It must not claim complete visibility into private repositories, vendored code, unpublished applications, or offline installations.

It is not automatically an Elisa implementation. Elisa and elisa-proof are potential consumers and future evidence providers. The implementation language remains an explicit project decision.

## 2. Non-negotiable design principles

### 2.1 Store observations; derive judgments

The canonical database stores timestamped claims and observations with provenance. An interpretation such as “maintenance continuity concern” is the result of a versioned rule applied to specified observations. The result links back to its complete inputs.

The following is forbidden as a primitive fact:

```json
{"contributor_is_trustworthy": 0.97}
```

The following is acceptable as a measurable observation:

```json
{
  "metric_key": "maintainer.review_share",
  "metric_version": "1.0.0",
  "subject": "project:example-parser",
  "dimensions": {"account_id": "account:example-alex"},
  "window": {"start": "2025-09-01T00:00:00Z", "end": "2026-09-01T00:00:00Z"},
  "value": {"kind": "rational", "numerator": 173, "denominator": 210},
  "status": "observed",
  "basis": "submitted non-bot reviews in the observed review dataset"
}
```

The second example does not establish expertise, safety, effort, working hours, or exclusive responsibility. It establishes a share of a defined set of recorded review events.

### 2.2 An exact number is not necessarily a valid measurement

Counts can be exact over an incomplete or misleading population. “There are 20 contributors” can mean 20 raw author strings, 20 forge accounts, 20 accepted identity clusters, or 20 accounts with qualifying maintenance activity. These are not interchangeable.

Every metric must identify its unit, population, filters, time basis, denominator, exclusion rules, completeness, and definition version. The product must prefer a precisely qualified claim over an apparently simple but ambiguous number.

### 2.3 Missing is not zero

At minimum, measurement status distinguishes:

| Status | Meaning |
|---|---|
| `observed` | The stated value was computed or obtained for the declared scope. |
| `not_observed` | No relevant observation has been collected yet. |
| `unavailable` | This source does not expose the required information. |
| `unauthorized` | Information may exist, but the current collector lacks permission. |
| `partial` | A value is available, but collection is incomplete for its intended scope. |
| `stale` | A formerly valid observation exceeds its freshness requirement. |
| `not_applicable` | The metric does not apply to this entity or workflow. |
| `error` | Collection or computation failed. |
| `conflicted` | Sources or assertions disagree and no resolution has been accepted. |
| `suppressed` | A privacy, redistribution, or policy rule prevents disclosure. |
| `unsupported` | The connector or parser does not implement this capability. |

Zero is a value only when the measurement population is sufficiently defined and collection supports concluding that the count is zero. Even then, “zero known advisories in the queried databases” is not “zero vulnerabilities.”

### 2.4 No universal health score

The default product exposes metric families, distributions, trends, and named findings. A customer can define a transparent policy score, but it must disclose its inputs and weights and must not be presented as objective universal health.

A missing optional metric must not lower a project's score merely because it uses a different forge. A critical finding must not disappear inside a favorable average. In particular, popular downstream adoption must never cancel a verified advisory match.

### 2.5 Continuity matters, but one-off contributors are not a defect

The user's intended distinction is between a project supported by a durable maintenance core and a project whose headline activity conceals weak continuity. The implementation must express that distinction directly.

A project can have many occasional contributors and a strong core. Another can have no occasional contributors because it is inaccessible to newcomers. Therefore, the one-off contribution ratio is descriptive, not inherently negative.

Continuity, concentration, succession, newcomer retention, and contribution quantity are separate dimensions. The relevant concern is **insufficient persistent stewardship for the project's maintenance responsibilities**, not the existence of drive-by patches.

### 2.6 Do not infer maintainer status from commit volume alone

Distinguish declared roles, observed permissions, observed maintenance actions, and activity-derived participation cohorts. A prolific contributor need not have release authority. A maintainer may spend most of their time reviewing or coordinating rather than authoring commits.

Where roles cannot be established, use labels such as `persistent_contributor` or `observed_release_actor`, not `maintainer`.

### 2.7 The graph must be temporal and version-aware

Dependencies belong to package versions, build contexts, manifests, resolved environments, or observed software artifacts. They do not exist as timeless universal project-to-project edges.

A project-level graph is a projection of those finer-grained observations. Every projection must declare its time, scope, version-selection policy, edge classes, and deduplication rules.

### 2.8 Safety practices, provenance, and correctness are different

A signature establishes a cryptographic relationship under a verification policy. It does not prove that the code is safe. A test run establishes the result of particular tests in a particular environment. It does not prove all program behavior. A formal proof establishes a proposition under assumptions and a trusted toolchain; it is not automatically a proof about a distributed binary.

The evidence schema preserves these boundaries. Automated dependency admission is a policy decision, not a theorem about software safety unless an actual proof establishes the required property.

### 2.9 Reproducibility must include the data interpretation

A reproducible metric result requires more than the repository revision. It requires the observation set, parser versions, identity-resolution revision, metric definition, configuration, time windows, graph projection, and policy version. Reports should be reproducible from an authorized evidence bundle even when live sources later change.

### 2.10 Collect broadly, but not indiscriminately

“As many metrics as possible” means a large, extensible catalog of useful and lawful measurements—not unlimited personal surveillance, expensive duplicate counts, or numbers whose interpretation cannot be defended.

Metric admission requires an exact definition, feasible sources, costs, privacy classification, confounders, test fixtures, and an explanation of how the measurement might inform a decision. Experimental measurements are labeled experimental and cannot silently enter production gate policies.

## 3. Product capabilities and workflows

### 3.1 Inspect a repository

A user supplies a public URL, authorized private source, local repository path, package coordinate, or source archive. The system discovers the source type, records the discovery evidence, collects supported observations, computes available metrics, and produces a coverage-aware report.

A generic Git source must produce useful history-based results without requiring GitHub. Git's own history and clone interfaces provide a forge-independent substrate; forge APIs enrich that substrate with information outside version-control history. [S01] [S02]

### 3.2 Inspect a project spanning multiple repositories

A project can include a main repository, platform ports, packaging repositories, documentation, a separate issue tracker, release infrastructure, and packages published to multiple registries. A project manifest or reviewed identity assertion links these without overwriting their distinct histories.

Project-level totals deduplicate the same commit or change represented in mirrors. Component reports remain available so that activity in a documentation repository does not conceal inactivity in a security-sensitive library component.

### 3.3 Inspect a dependency inventory

Users can submit a lockfile, supported SBOM, or previously exported graph snapshot. repo-health resolves components conservatively, enriches known package versions, and produces an upstream-exposure report.

Unresolved version requirements remain unresolved. Missing transitive edges are listed. The service does not invent a full dependency closure from a manifest containing version ranges.

### 3.4 Examine downstream adoption

For a package or project, users can inspect known direct and transitive dependents, their intrinsic-condition distributions, retained adoption, update lag, and replacement observations.

The view distinguishes package versions from package names and project families. Thousands of versions of one package are not thousands of independent projects. Fork farms and mirrors do not automatically count as independent endorsements.

### 3.5 Examine contributor and maintenance continuity

A project view shows role-specific activity across complete calendar periods, persistent cohorts, response activity, release concentration, review concentration, and documented handovers. It can display a contributor's project-relevant history across accepted public identity links without creating a moral reputation score.

The most prominent individual-level views are about operational roles and observed responsibilities. Project-level continuity is the primary outcome; generalized public people-ranking is not a product goal.

### 3.6 Compare candidate dependencies

Comparison requires a user-specified function and context. repo-health supplies comparable measurements; it does not infer API interchangeability from package names or shared keywords.

The comparison shows which requirements each candidate meets, which facts are unknown, and which tradeoffs remain. A mature small library and a rapidly developing framework should not share an unqualified commit-frequency benchmark.

### 3.7 Detect change, not just state

Users can monitor meaningful changes: loss of observed release redundancy, newly affected resolved versions, an upstream release withdrawn from a registry, a change in package-to-repository mapping, or an increase in unreviewed release activity.

Alerts must distinguish changes in the world from changes in measurement coverage. A connector outage must produce a collector-coverage alert, not an abandonment alert for thousands of projects.

### 3.8 Support coding agents and package admission

An agent can request an evidence report, evaluate a versioned policy, and receive `allow`, `warn`, `deny`, or `unknown`. Dependency identities and artifact digests are bound to the decision where available.

The agent cannot turn an unknown result into an allow result by describing the package favorably. Repository content is untrusted data, not an instruction channel for the policy engine.

### 3.9 Identify places where help may be valuable

An ecosystem steward can find projects with many independently observed dependents, concentrated maintenance responsibilities, and documented support needs. Outputs should describe concrete opportunities—such as adding a release maintainer or improving test infrastructure—rather than imply personal failure by volunteers.

Funding-impact estimates are scenario models, not established causal measurements. The graph can show exposure and observed capacity; proving the effect of an intervention requires additional evaluation.

## 4. Relationship to existing infrastructure

repo-health should reuse established formats, observations, and tools wherever appropriate. Its differentiation is the integration of temporal evidence, cross-forge continuity, upstream exposure, downstream condition, and explainable policy—not a claim to have invented repository analytics.

| Existing infrastructure | Role in repo-health | Important boundary |
|---|---|---|
| CHAOSS metrics | Reference definitions and terminology for community measurement. | Preserve original semantics when claiming compatibility; label deviations. |
| OpenSSF Scorecard | Import individual practice-check observations and their versions. | A third-party check or aggregate score is not a universal health fact. |
| OpenSSF Criticality Score | Methodological comparison and optional historical imported data. | Criticality is distinct from health; verify dataset freshness and availability. |
| deps.dev | Optional package/version/dependency enrichment. | Coverage is bounded; declared repository links require validation. |
| ecosyste.ms | Optional cross-source metadata, dependency, and event enrichment. | Preserve attribution, terms, licensing, provenance, and source limitations. |
| OSV | Known-vulnerability observations with package/version or commit context. | No advisory match does not establish absence of vulnerabilities. |
| Package URL | Package coordinate interchange. | Coordinates do not by themselves establish source identity or artifact integrity. |
| SPDX and CycloneDX | Versioned software-inventory import and export. | An SBOM's completeness and origin remain evidence attributes. |
| SLSA | Structured provenance and supply-chain evidence interpretation. | Record verified properties, not unsupported certification claims. |
| SWHID | Optional content-oriented archival identifiers. | An archive identity does not establish ongoing maintenance or deployment. |

CHAOSS defines Contributor Absence Factor using the smallest contributor set responsible for half of the measured contributions; repo-health can expose that exact measure alongside separately named 80% and role-specific concentration metrics. [S03]

Scorecard provides automated security-practice checks, while Criticality Score addresses project influence. Import their outputs as named, versioned external evidence instead of relabeling them as repo-health's own measurements. [S04] [S05]

A source-availability check matters immediately: the Criticality Score repository states that its Google Cloud-hosted datasets were discontinued in August 2026 and directs users to repository data. It must not be treated as an assumed live dependency. [S05]

The deps.dev API documents package-system coverage and exceptions, including restrictions on the projects it gathers. Its dependency information is useful enrichment, not an exhaustive graph of all public or private software. [S06]

The ecosyste.ms service exposes several relevant data and tooling categories. Any integration must evaluate the applicable service and dataset terms rather than assume all upstream data can be redistributed without conditions. [S07]

## 5. Logical system architecture

### 5.1 End-to-end flow

```text
User seeds, package inventories, approved discovery sources
                         |
                         v
             Source catalog and capability probes
                         |
                         v
        Scheduler -> isolated collectors -> raw evidence
                         |                    |
                         |                    v
                         |          parsers and normalizers
                         |                    |
                         v                    v
                 collection ledger     canonical event ledger
                                              |
                               identity and entity assertions
                                              |
                                              v
                                temporal knowledge graph
                                              |
                         +--------------------+-------------------+
                         |                    |                   |
                         v                    v                   v
                 intrinsic metrics    dependency analytics   time-series analysis
                         |                    |                   |
                         +--------------------+-------------------+
                                              |
                                  findings and policy engine
                                              |
                        API / CLI / website / exports / agent tools
```

A separate control plane manages credentials, tenant access, scheduling quotas, source permissions, schema versions, and publication policies. It does not grant arbitrary collectors access to every secret.

### 5.2 Module boundaries

| Module | Owns | Must not own |
|---|---|---|
| `domain` | Identifiers, typed events, observation states, temporal semantics. | Forge-specific API response structures. |
| `sources` | Source registry, capability observations, transport configuration. | Health judgments. |
| `collectors` | Fetching approved resources, pagination, cursors, fetch provenance. | Unrestricted execution of fetched code. |
| `normalization` | Parsing source records into canonical events and assertions. | Quietly deleting inconvenient conflicting evidence. |
| `identity` | Alias claims, project mappings, accepted link revisions, corrections. | Guessing personal identity from names alone. |
| `graph` | Typed temporal edges, projections, bounded traversal, snapshots. | Treating every reachable package as deployed software. |
| `metrics` | Deterministic metric execution and exact measurement contracts. | Network calls or hidden live data dependencies. |
| `findings` | Evidence-linked rule outcomes and explanations. | Unexplained all-purpose scores. |
| `policy` | Admission evaluation and exception handling. | Mutating source projects or installing dependencies. |
| `publication` | Access filtering, reports, redaction, exports, citations. | Leaking tenant-private evidence through public totals. |
| `operations` | Job control, quotas, observability, backup, recovery. | Rewriting analytical results to conceal operational failures. |

### 5.3 Initial deployment strategy

Begin as a modular application with independently isolated collection workers, PostgreSQL for durable canonical state, and a filesystem-backed content-addressed evidence store. The CLI and HTTP API use the same domain logic. No distributed message broker, dedicated graph database, or separate analytical warehouse is required for the first usable release.

A local scan can create an evidence directory and deterministic report without a running server. Its graph scope is local or imported; it must not imply internet-wide reverse-dependency knowledge.

The recommended reference implementation is a Rust service/CLI with a small TypeScript enhancement layer for the web UI, subject to a bootstrap architecture decision. This is a project recommendation, not a user-mandated language choice. Go is a credible alternative if the implementation team prefers it; schema and analysis contracts should not depend on language-specific object layouts.

### 5.4 Evolution without premature distribution

Introduce object storage when evidence no longer fits operationally on local disks. Introduce columnar snapshots when historical scans become too expensive for transactional tables. Introduce a dedicated graph projection store only after measured query workloads justify it.

Each new store is a rebuildable projection unless explicitly designated otherwise. The authoritative source remains the evidence and assertion ledger plus required source artifacts. A dashboard cache must never become the only surviving copy of a measurement's inputs.

### 5.5 Trust boundaries

Collectors handle untrusted URLs and responses. VCS parsers handle untrusted repository objects. Archive parsers handle untrusted filenames and compression. Document renderers handle untrusted text. Plugins handle extensible third-party logic. Each is a distinct attack surface.

The metrics engine consumes validated immutable inputs and has no default network or credential access. The policy engine consumes metric results, not arbitrary repository prose. A successful fetch is not a trust grant.

## 6. Canonical data model

### 6.1 Entities

| Entity | Purpose | Identity rules |
|---|---|---|
| `Project` | A coherent software effort. | Internal stable ID; mappings to repositories are assertions. |
| `ProjectComponent` | Subproject, subsystem, package-producing path, or maintained branch family. | Scoped to a project and versioned definition. |
| `Repository` | A source-history location or logical repository. | Internal ID plus source-native ID and location history. |
| `RepositoryLocation` | A URL and provider instance valid during an interval. | Never assume a URL identifies one owner forever. |
| `RepositorySnapshot` | Exact observed refs and retrieval coverage. | Content/manifest digest plus collection run. |
| `Revision` | VCS-specific commit or revision object. | Namespace includes VCS and hash/revision scheme. |
| `ChangeProposal` | A proposed change, including patch-series workflows. | Source-scoped native identifier; revisions remain distinct. |
| `Review` | A submitted review or structured review event. | Event identity and target revision/proposal. |
| `Issue` | A tracked report or request. | Tracker identity, not repository identity alone. |
| `Release` | A declared release event or release line. | Distinct from a tag or package publication. |
| `Package` | A named registry or distribution package. | Ecosystem, registry instance, namespace, canonical name. |
| `PackageVersion` | A package release version. | Ecosystem-native version semantics and publication facts. |
| `Artifact` | Exact downloadable bytes. | Cryptographic digest plus media type and locations. |
| `DependencyRequirement` | A declared relation that may not resolve to one version. | Parent snapshot/version, raw expression, context, source span. |
| `ResolutionSnapshot` | A resolved dependency environment. | Resolver version, inputs, platform, features, registry snapshot. |
| `Advisory` | A vulnerability or security notice. | Source-native identity; aliases are separately modeled. |
| `Account` | A source-specific technical account. | Instance-scoped immutable provider ID when available. |
| `ActorCluster` | Accepted grouping of technical identities. | Versioned, reversible evidence-based grouping. |
| `SigningIdentity` | Key, certificate identity, or attestation subject. | Algorithm and fingerprint/issuer-subject semantics. |
| `RoleAssignment` | Declared or observed authority over an entity. | Role type, issuer, evidence, validity interval. |
| `Organization` | Public organization relevant to governance or maintenance. | Verified source reference; uncertain affiliation stays unknown. |
| `SourceInstance` | Forge, registry, tracker, archive, or feed instance. | Base location, kind, capability revisions. |
| `ReferenceDocument` | Documentation, citation, release announcement, or permitted external reference. | Canonical location and retrieved version. |
| `EvidenceObject` | Retained source payload or authorized redacted form. | Content digest, scope, rights, retention, and fetch record. |
| `Observation` | A typed directly recorded fact or measurement. | Stable metric/event key and complete provenance. |
| `Assertion` | A proposed relationship or interpretation of evidence. | Method, status, issuer, and supporting evidence. |
| `Finding` | A rule result requiring attention or explaining context. | Rule version, inputs, scope, state history. |
| `PolicyEvaluation` | A decision for a specific requested use. | Policy digest, subject digest, context, evidence cutoff. |

### 6.2 Relationships

The graph has typed edges such as `contains`, `publishes`, `built_from`, `declares_dependency`, `resolves_to`, `depends_on`, `contributed_to`, `reviewed`, `released`, `has_role`, `mirrors`, `forked_from`, `supersedes`, `mentions`, `distributed_as`, and `affected_by`.

Each edge declares allowed source and target entity kinds. A `mentions` edge cannot be treated as a dependency. A `contributed_to` edge cannot automatically imply `has_role`. A `mirrors` edge cannot imply common ownership or continued synchronization.

### 6.3 Project, package, and repository separation

One repository can produce many packages. One project can maintain several repositories. A package can change its upstream repository. A distribution package can bundle or patch upstream components. A project can move forges without becoming a new project.

These are many-to-many, time-dependent mappings with evidence, not columns containing one supposedly definitive URL. The user interface may show a preferred current homepage, but the underlying model retains its provenance and history.

### 6.4 Package identity and version identity

Package URL is the preferred interchange representation where supported. Store the original coordinate and the ecosystem-normalized coordinate. Preserve registry identity when a private or alternate registry can serve a colliding package name. [S08]

Never compare arbitrary version strings lexicographically. Each ecosystem parser owns normalization, ordering, range matching, prerelease behavior, aliases, and special versions. Unsupported expressions remain raw requirements with an explicit unresolved status.

An artifact digest is independent of a version label. Multiple artifacts can share a version, and one artifact can be distributed through multiple locations. Tag movement and republished bytes must not be hidden by a package-version primary key.

### 6.5 Bitemporal records

A temporal assertion contains two time dimensions:

- **Valid time:** when the assertion concerns the external world, to the extent known.
- **System time:** when repo-health learned, accepted, superseded, or retracted it.

Example: a maintainer-role change effective on June 1 is discovered on June 20. A historical query “what do we now know about June 10?” can include it; “what did the system know on June 10?” cannot.

Use half-open intervals `[start, end)` throughout. Unknown start times are not guessed from the first successful API fetch. A current observation can establish existence at one observation time without establishing uninterrupted historical validity.

### 6.6 Source timestamps are not interchangeable

Record author time, committer time, provider event time, release publication time, artifact retrieval time, and system ingestion time separately. Preserve original timezone information where supplied, while storing normalized UTC instants for computation.

A historical Git commit's timestamp does not establish when it first became publicly visible. A newly imported repository can contain old commits. Activity metrics must declare whether they measure authoring time, integration time, or observed publication events.

### 6.7 Minimal event envelope

```json
{
  "schema_version": "1.0.0",
  "event_id": "event:01-example",
  "tenant_scope": "public",
  "source_instance_id": "source:forge-example",
  "source_object_type": "review",
  "source_object_id": "review-89341",
  "source_revision": "etag-or-payload-digest",
  "event_kind": "review.submitted",
  "subject_id": "change:example-219",
  "actor_account_id": "account:example-alex",
  "occurred_at": "2026-08-14T10:15:00Z",
  "observed_at": "2026-08-14T10:19:31Z",
  "time_basis": "provider_event_time",
  "evidence_id": "evidence:sha256-example",
  "parser": {"name": "forge-review", "version": "1.0.0"},
  "payload": {"decision": "approved", "target_revision": "git:sha1:example"}
}
```

The envelope separates a provider's state record from an event. If an API exposes only the current state, the normalizer must not manufacture the exact transition history. Source-state snapshots and observed transitions are both useful, but distinct.

### 6.8 Observations and provenance

An observation stores a discriminated value: integer, decimal, rational, boolean, enum, timestamp, duration, histogram, bounded set, or structured record validated against a registered schema. JSON is a transport representation, not permission to store undocumented blobs.

Derived observations record the exact input-set digest and computation version. Large input memberships can be stored as a referenced manifest rather than repeated in every row. All hashes name their algorithm; “hash” alone is an incomplete field.

### 6.9 Corrections and retractions

Corrections are append-only revisions with links to superseded facts. Accepted identity links can be revoked. An incorrect package mapping can be withdrawn. Downstream projections and affected metric results are invalidated and recomputed.

Privacy-driven deletion can remove or encrypt-destroy payloads while leaving a permitted minimal tombstone. Reproducibility claims must then say which inputs are no longer available. “Append-only” is an analytical design goal, not an excuse to retain prohibited personal data forever.

## 7. Source acquisition and connector architecture

### 7.1 Capability-oriented adapters

Do not require every adapter to implement one enormous interface containing repositories, issues, releases, users, downloads, and dependency information. Use small capability interfaces that return explicit support states.

```text
SourceDiscovery
RepositoryHistory
RepositoryRefs
ChangeProposals
ReviewEvents
IssueEvents
ReleaseMetadata
PackageMetadata
DependencyMetadata
ArtifactRetrieval
RoleEvidence
AuthorizedTraffic
ReferenceDiscovery
ArchiveLookup
```

A capability result includes the adapter version, source-instance version if known, authorization scope, pagination behavior, historical retention, update cursor type, observed limits, and collection completeness. The source registry can combine a generic VCS adapter with a forge adapter and a separate issue-tracker adapter.

For example, a self-hosted Forgejo repository may use generic Git for history, Forgejo for proposals, a mailing list for review discussion, and a registry for release artifacts. None is assumed to be the exclusive source of truth for all event types.

### 7.2 Connector families and coverage targets

The following is a planned coverage roadmap, not a declaration of implemented support.

| Source family | Initial useful capability | Later enrichment | Expected limitations to model |
|---|---|---|---|
| Generic Git over HTTPS | Refs, history, tree metadata, approved blobs. | Tags, component paths, incremental object reuse. | No universal issues, releases, permissions, or traffic. |
| GitHub | Repository metadata, proposals, reviews, issues, releases. | Authorized controls and traffic. | Permissions, rate limits, retention, provider semantics. |
| GitLab.com and self-hosted GitLab | Native metadata and workflow events. | Instance-specific controls, releases, pipelines. | Version, license tier, settings, and access differences. |
| Forgejo, including independently hosted instances | Repository and workflow metadata. | Available release/control APIs. | Instance API may be disabled; major-version differences. |
| Gitea | Repository and workflow metadata. | Available packages and workflow observations. | Similarity to Forgejo does not guarantee identical APIs. |
| Bitbucket Cloud | Repository and native change metadata. | Available workspace and pipeline observations. | Must not assume compatibility with self-hosted products. |
| Gerrit | Changes, patch-set revisions, labels, reviews. | Submit conditions and contributor-role evidence. | A change is not the same object as a GitHub pull request. |
| SourceHut | Git or Mercurial substrate first. | Native metadata and mailing-list integration after validation. | Verify current API behavior during connector implementation. |
| Mercurial | Native revision history and tags. | Branch/bookmark and forge enrichment. | Revision identity and merge semantics differ from Git. |
| Subversion | Repository/path revision observations. | Branch conventions and release-path modeling. | Global revision numbers are not per-project commit counts. |
| Fossil | Native history and supported JSON metadata. | Tickets, forum, and release associations where exposed. | Capability availability depends on deployment. |
| CVS and Bazaar/Breezy | Explicit import or vetted native collector. | History normalization with known conversion losses. | Converted histories need provenance and loss markers. |
| SourceForge and other hosting sites | Generic VCS, release metadata, explicit imports. | Native tracker/download integration after capability review. | Mixed source-control and tracker models. |
| Mailing-list / patch archives | Message headers, patch series, explicit review trailers. | Proposal-to-commit associations. | Incomplete archives, duplicate messages, uncertain matching. |
| Standalone trackers | Issues, changes, status transitions. | Links to source revisions. | Tracker migration and deleted events. |
| Package registries | Package versions, declared dependencies, source links. | Downloads, publication identities, attestations if exposed. | Download counts are not user counts. |
| Distribution metadata | Packaged versions and source mappings. | Patches, support branches, build/test observations. | Distribution versions do not equal upstream versions. |
| Source archives and release websites | Artifact bytes, digests, metadata, timestamps. | Repeated snapshots and release lineage. | No invented commit or contributor history. |
| Documentation and external references | Explicit links and permitted citation metadata. | Bounded backlink or mention observations. | No claim to a complete global backlink index. |

GitLab, Forgejo, Gitea, Bitbucket Cloud, and Gerrit publish their own API contracts; implementations must follow the relevant source rather than a presumed common forge API. [S09] [S10] [S11] [S12] [S13]

Native history adapters should likewise preserve Mercurial, Subversion, and Fossil semantics instead of converting everything into an unqualified Git-shaped history. [S14] [S15] [S16]

### 7.3 Generic Git collection

The collector creates or updates a bare repository in an isolated workspace. It does not check out arbitrary files or execute repository-controlled hooks, filters, builds, or package installation scripts. It records the complete fetched ref set and shallow/partial-clone state.

Collection is tiered:

1. Retrieve advertised refs and repository identity observations within a strict transport budget.
2. Fetch enough history for the requested metric window, explicitly recording omissions.
3. Read commit/tree metadata with a bounded parser.
4. Retrieve manifests and selected metadata blobs by allowlisted size limits.
5. Perform expensive diffs, blame-based exposure analysis, or whole-history expansion only when requested or scheduled under budget.

Historical completeness cannot be inferred merely because a fetch succeeded. A shallow clone cannot support a lifetime-contributor claim. A partial clone may have commit history while omitting blobs needed for code-change classification. The report identifies which computations were actually possible. [S02]

Raw author and committer identities are preserved separately from `.mailmap`-normalized identities. The mapping is an assertion from a specific repository revision, not a global identity oracle. [S01]

### 7.4 Git deduplication and change semantics

A commit object is deduplicated by its VCS-qualified object identifier. The same commit may appear in several repositories or refs; membership is a separate relation.

A cherry-pick can have a different commit ID despite a similar patch. Store optional patch-equivalence assertions with algorithm version and confidence category. Never silently collapse distinct commits solely because their diffs resemble one another.

A merge commit, a squash merge, and an emailed patch integrated through a subsystem tree represent different workflows. Count commits and accepted change proposals separately. Neither is declared a universal unit of work.

A force-push creates a new observed ref state. Previously observed commits are not erased from the historical ledger just because they are no longer reachable. Current-branch metrics use the relevant snapshot; historical publication observations remain historical observations.

### 7.5 Repository discovery and crawl fairness

Seeds can come from user requests, registries, distribution inventories, approved aggregate datasets, project manifests, and curated lists. Discovery must not rely exclusively on stars or popularity; otherwise small and non-GitHub projects remain systematically invisible.

The scheduler reserves capacity for less-observed source families and user-requested projects. Maintain separate priority lanes for collection freshness, incident-related refreshes, long-tail discovery, and expensive historical analysis.

No public discovery mechanism follows arbitrary private-network addresses. A connector instance for internal infrastructure is explicitly registered by an authorized administrator and isolated from the public crawler.

### 7.6 Fetch provenance and completeness

Each fetch run records request purpose, source instance, sanitized request identity, auth-scope reference, start/end times, response status, pagination cursor, object counts, bytes, retry history, rate-limit observations, and a result status.

Do not retain secret headers or tokens in evidence blobs. Sensitive response fields can be stored in an encrypted restricted payload or redacted before retention. The evidence record documents whether retained bytes are original or transformed.

A page is committed together with its deduplicated object records and next cursor. A worker crash before cursor commit causes safe reprocessing; a crash after cursor commit must not lose the accepted page.

The final collection result distinguishes complete enumeration, bounded sampling, provider truncation, rate-limit interruption, and unknown total size. “Fetched 100 records” is not “there are 100 records.”

### 7.7 Traffic, clones, and external attention

Traffic is an optional capability. GitHub's documented clone endpoint covers the last 14 days and requires authorized repository access; its referral endpoints are similarly bounded. Public repository visibility alone is not sufficient. [S17]

Traffic observations retain interval boundaries, provider definition, count type, and authorization scope. Overlapping windows are not summed. Daily unique counts are not added to produce monthly unique people. Counts from different providers are not presumed comparable.

Backlinks and shares are observations from named indexes or approved crawls. Record the observed domain count, unique canonical documents, first/last observed timestamps, and index coverage. A social mention is neither a dependency nor evidence that someone has audited the software.

### 7.8 Mailing-list and patch workflows

Store message IDs, thread relations, submission timestamps, patch-series versions, authorship trailers, and explicitly stated review/test acknowledgments. A re-sent patch series is not automatically a new independent contribution.

Association between a patch and an integrated commit can use explicit links, trailer metadata, or a separately labeled content match. Exact match and heuristic match remain different evidence classes.

Kernel documentation illustrates why review, authorship, testing, and patch-delivery trailers should not be flattened into one contributor count. repo-health's canonical model retains the original role of each observed trailer. [S18]

### 7.9 Collector plugin contract

A collector plugin receives a capability request, a scoped transport handle, limits, and a continuation cursor. It returns raw evidence references, source records, capability observations, and a new cursor.

Plugins must not receive unrestricted database credentials. They write through validated ingestion interfaces. Network egress, filesystem access, subprocess execution, and credentials are separate granted capabilities.

Initially, plugins are vetted built-in modules or supervised subprocesses. A later WebAssembly or other sandboxed plugin ABI is optional; sandbox technology must be evaluated against the actual threat model rather than marketed as complete isolation.

## 8. Contributor identity, roles, and continuity

### 8.1 Identity layers

Maintain at least four layers:

1. Source-native accounts with stable provider IDs where available.
2. Raw VCS or archive identities, including author strings and email identifiers under restricted handling.
3. Signing identities and authenticated publication identities.
4. Accepted actor clusters grouping identities for a specified analytical purpose.

A cluster can represent a human account holder, a declared bot, a service account, a shared organizational identity, or an unresolved grouping. It must not assume every account represents one unique person.

### 8.2 Identity-resolution policy

The default is conservative non-merge. Strong evidence includes authenticated ownership claims, documented account migrations, or explicit verified cross-links. Repository mailmaps are useful local evidence but may be incomplete or erroneous. Name similarity alone is insufficient.

Do not publish pseudo-precise probabilities such as `same_person_probability = 0.997` unless a validated model actually supports that probability and its calibration is documented. Initially use exact evidence classes and statuses: `proposed`, `accepted`, `rejected`, `revoked`, `conflicted`.

Identity assertions carry scope. Two addresses may be treated as one contributor inside a project under that project's mailmap without being globally merged across all forges. Global joins require stronger evidence and privacy review.

Merge operations are reversible. Revoke one incorrect edge and recompute affected clusters from accepted evidence; do not destructively concatenate person records. The identity revision is part of every person-sensitive metric input.

### 8.3 Human, bot, and unknown activity

Use provider-declared account types, explicit project declarations, and versioned local classifiers. Every classifier can return `unknown`.

Publish raw totals and stratified totals. “Human-only” counts exclude known bots but must also disclose unresolved accounts. Automated commits attributed to a human do not prove manual work; AI authorship must not be inferred from writing style.

A declared bot that publishes releases is still relevant to operational concentration, but it does not reveal the people controlling its credentials. Model automation accounts and observed human approval roles separately.

### 8.4 Evidence of maintenance roles

Role evidence can include authorized permission metadata, a versioned maintainer file, a governance document, repeated release events, merge actions, and formal review authority. Each has a distinct meaning.

Store, for example:

```text
role_kind: release_publisher
basis: observed_registry_publication
subject: package:example-parser
account: account:release-service
validity: observed at listed publication events
permission_inventory_complete: false
```

This says that an account published observed releases. It does not establish that it is the only account able to publish, that the same person controlled it throughout, or that hidden administrative recovery procedures do not exist.

### 8.5 Persistent participation definition

A default activity-derived cohort can be defined as follows, with parameters versioned and visible:

- Analyze the previous 12 complete UTC calendar months.
- A qualifying contribution is an accepted change, a submitted non-bot review, or an explicitly counted maintenance event; retain the event type.
- A contributor is `persistent_12m` when qualifying activity occurs in at least 6 distinct months, the first-to-last qualifying span is at least 180 days, and activity occurs in at least one of the last 3 complete months.
- A declared maintainer meeting those criteria is also an `observed_active_maintainer_12m`; an undeclared contributor remains a persistent contributor.

These are proposed operational thresholds, not scientifically established boundaries. Expose the component measurements so users can choose other definitions. A project with annual releases may require a different cohort profile.

A complementary `persistent_24m` profile measures activity over a longer horizon. Do not require activity every month or every week: that would encode an unjustified expectation of uninterrupted work.

### 8.6 Retention with observable cohorts

For a contributor whose first observed qualifying event is at time `t0`, define a return window such as `[t0 + 90 days, t0 + 120 days)`. Include the contributor in the 90-day retention denominator only if collection covers that entire return window and the evaluation cutoff is after it.

The retained numerator counts eligible contributors with at least one qualifying event in that window. Publish the numerator, eligible denominator, censored count, and history-completeness status.

A contributor first seen last week cannot be classified as failing 12-month retention. A provider outage during the return window must not be interpreted as departure. First observed contribution and actual first-ever contribution are different when historical coverage is incomplete.

### 8.7 One-off and occasional participation

Use neutral metric names such as `single_event_contributors`, `contributors_2_to_5_events`, and `one_off_share_observed_window`. The phrase “drive-by” can appear in explanatory text, but it should not be a hidden negative label attached to accounts.

A project-level continuity finding must examine the maintenance core separately. A high one-off share with stable release and review coverage is not an automatic concern. A low one-off share with one overloaded release actor may still be fragile.

### 8.8 Concentration and effective contributor counts

For one declared event type and window, let `x_i` be the nonnegative count attributed to actor `i`, and let `s_i = x_i / sum(x)`.

```text
top_1_share = max(s_i)
HHI = sum(s_i^2)
effective_contributor_count = 1 / HHI
contributor_absence_factor_50 = minimum k whose descending shares sum to >= 0.50
concentration_count_80 = minimum k whose descending shares sum to >= 0.80
```

These formulas are exact over the specified counts. Their interpretation remains limited: event concentration is not the true number of people whose departure would make a project fail.

Compute them separately for accepted changes, reviews, releases, and issue-triage actions. Never mix a line changed, a review, and a release into “work units” without a disclosed weighting model.

### 8.9 Succession and handover

A handover is an explicitly declared transition or a separately labeled change in observed activity. Store old/new role holders, overlap interval, evidence type, and subsequent observed release/review coverage.

For activity-derived transitions, require a minimum observation window after the apparent change. Use terms such as `primary_release_actor_change_observed`, not “maintainer abandoned the project.” The system does not know why activity stopped.

Useful outputs include overlap months, number of observed releases during transition, continuity of review activity, and duration until the next observed supported release. Distinguish declared succession from an inferred shift in who performed actions.

### 8.10 Cross-project track records

A contributor's accepted public technical history can inform project-level measurements: years of observed participation, number of projects with sustained release or review activity, and prior role-overlap intervals.

Do not automatically transfer a package's popularity to a contributor's “trust.” Do not infer that a person's past involvement caused a project's success or failure. A project declining after someone left is an event sequence, not a causal attribution.

Likewise, do not mechanically attribute vulnerabilities or regressions to individuals using blame heuristics. A confirmed incident link can be stored with its evidence and scope; unvalidated attribution is experimental and excluded from personal scoring and default public reports.

### 8.11 Privacy and correction controls

Use internal opaque IDs and restrict raw email exposure. Public reports default to project-level aggregates and already-public account handles where needed. Avoid collecting private email addresses, precise location, personal demographics, inferred employment, personal health, or sentiment-based character judgments.

A contributor can request an identity correction or challenge an attribution. The resolution process preserves an audit trail without requiring disclosure of unnecessary personal information. Public aggregation thresholds and restricted exports reduce the creation of a convenient cross-forge profiling database.

Legal review is a launch requirement for collection, retention, identity linking, and redistribution. This document specifies engineering safeguards, not a conclusion that any particular deployment satisfies applicable law.

## 9. Dependency graph semantics and analytical projections

### 9.1 Dependency edges require context

A dependency edge or requirement records:

```text
consumer entity and exact snapshot/version
producer package identity
raw version requirement
resolved package version, if known
artifact digest, if known
scope: runtime | build | development | test | documentation | tool | unknown
optional flag and activation condition
platform / architecture / feature context
source: manifest | lockfile | SBOM | registry | static_scan | attestation
introduced/removed observations, if actually known
source span and evidence reference
parser/resolver versions
valid and system times
resolution completeness
```

A development or build dependency is not automatically low security risk: build tooling may have powerful execution privileges. Dependency purpose changes the exposure path; it does not establish one universal risk weight.

### 9.2 Requirements versus resolved edges

A manifest such as “B >= 2 and < 3” yields a requirement. A lockfile that identifies B 2.4.1 yields a resolved edge for its declared environment. A registry-derived hypothetical resolution is a separate resolution snapshot, not a claim about what every downstream user installed.

A graph of all versions satisfying all ranges is a possibility graph. It must never be labeled as the actual installed graph. Dependency closure for policy admission should use resolved, context-specific artifacts wherever possible.

### 9.3 Projected graph types

| Projection | Nodes and edges | Primary use |
|---|---|---|
| Requirement graph | Versions/snapshots to package requirements. | Dependency declaration analysis. |
| Resolved version graph | Exact package versions in a resolution context. | Advisory matching and concrete path analysis. |
| Package adoption graph | Deduplicated package names with declared aggregation rules. | Package ecosystem trends. |
| Project adoption graph | Accepted project mappings and independent project families. | Downstream condition and criticality. |
| Maintenance-role graph | Projects/components to role-bearing accounts or clusters. | Concentration, shared-maintainer exposure, succession. |
| Distribution graph | Upstream components to distro packages and versions. | Supported-version and patch-line analysis. |
| Reference graph | Projects to external documents and mentions. | Attention and documentation reach, not dependencies. |

Every projection has a stable ID, schema version, input cutoff, as-of time, identity revision, mapping revision, visibility scope, and completeness descriptor.

### 9.4 Direct and transitive dependents

Fix the edge direction as `consumer -> dependency`. Direct dependents of B are nodes A with an edge `A -> B`. Transitive dependents are unique nodes that can reach B through allowed dependency edges.

Use a visited set; a diamond graph must not count the same dependent twice. Exclude the root from its own dependent count even when cycles exist. Define whether counts represent package versions, packages, projects, or deduplicated project families.

Reports should say “known observed dependent projects in snapshot X,” not “all applications worldwide using this software.” Public data cannot establish that latter quantity.

### 9.5 Cycles and strongly connected components

Dependencies can form cycles in some ecosystems and projection types. The graph engine must not assume a DAG. For appropriate analyses, compute strongly connected components and use the resulting condensation DAG.

Preserve the original nodes and edges. Component contraction is an algorithmic technique, not a reason to merge distinct packages or projects. A cycle in a broad possibility graph may not exist in a particular resolved installation.

### 9.6 Downstream condition without circular reasoning

Compute each project's intrinsic metrics without incorporating downstream adoption. Then summarize those intrinsic metrics over its observed dependents.

For example, report the number of direct dependent projects with recent accepted changes, the median number of persistent contributors among covered dependents, and the share with observed release redundancy. These remain separate measurements.

An optional model may define a continuity-conditioned adoption index:

```text
index(P) = sum over independent direct dependents d of:
    relation_weight(d, P) * freshness_weight(d, P) * continuity_component(d)
```

This is an explicitly named model, not a raw observation. Its parameters are versioned. The continuity component must exclude adoption-based inputs, or it recreates circular endorsement.

Do not call it “proof of trust.” A well-maintained downstream project can inherit an insecure dependency, pin an obsolete release, or continue using a library because migration is expensive.

### 9.7 Downstream quality as distributions, not prestige

The default downstream panel shows distributions and counts: activity cohort, maintenance continuity, release coverage, observed dependency freshness, organizational independence where known, and upstream contribution feedback.

Do not define “quality” as famous company usage or use prestige labels such as “commercial-grade” without operational criteria. Major users can be shown as identifiable observed dependents, but their names do not replace measurement.

### 9.8 Adoption growth, retention, and replacement

A newly observed dependency is not necessarily newly adopted. Distinguish `first_seen_by_collector` from `introduced_in_observed_change`.

A removal event requires evidence of a relevant manifest/lockfile change, a complete snapshot comparison, or an authoritative package-version transition. A missing repository during an outage is not a dependency removal.

Replacement requires an explicit migration link or a labeled hypothesis derived from a change removing A and adding B. Merely sharing a category is insufficient to conclude that B replaced A.

Upgrade lag is calculated only when a defined eligible target release exists. Compare within the relevant supported release line, compatibility range, and publication timeline. Staying on a maintained long-term-support version is not automatically neglect.

### 9.9 Upstream exposure propagation

Report direct findings and reachable findings separately. A known advisory affecting a resolved package version can be associated with paths from an application to that version. Preserve dependency scope and platform conditions.

Maintain several distinct counts: affected dependency nodes, unique advisories after accepted alias deduplication, distinct paths or bounded path witnesses, and consumer projects with any known affected node. Do not sum path counts and present the result as affected users.

Reachability in a package graph is not runtime exploitability. Function-level reachability, configuration applicability, and deployed artifact evidence are optional additional layers, not assumptions.

### 9.10 Criticality and blast-radius scenarios

Criticality is multi-dimensional: observed direct/transitive dependents, independent project-family count, distribution presence, role concentration shared across important dependencies, and the availability of maintained alternatives.

“Blast radius” is a scenario over the observed graph: which known nodes are reachable under specified edge types and version conditions. It is not a precise number of humans, devices, or businesses affected.

Scenario analyses can simulate removal of a package node, loss of a publishing account, or withdrawal of a registry. Each scenario explicitly states whether alternate versions, mirrors, forks, and caches are assumed usable.

### 9.11 Centrality algorithms

Degree and bounded reverse reachability come first. PageRank-like centrality, sampled betweenness, and other global measures are optional derived analytics.

For a dependency-oriented PageRank, keep direction explicit: weight flows from a consumer toward its dependencies if the purpose is dependency importance. Record damping, dangling-node handling, edge normalization, convergence tolerance, iteration count, graph snapshot, and implementation digest.

Centrality may be distorted by package farms, generated packages, mirrors, and ecosystem packaging conventions. Publish family-deduplicated variants and sensitivity analyses. No centrality value is a certificate of reliability.

### 9.12 Correlated maintenance exposure

The role graph can reveal that several dependencies are maintained by the same accepted actor cluster or organization. Report known common-control concentration and its coverage.

Do not treat unknown affiliations as independent organizations. Do not infer employer identity from an email domain alone. A dependency graph with ten packages may have fewer than ten independent maintenance groups, but the exact control structure is often only partially observable.

### 9.13 Bounded graph computation

Every traversal has node, edge, depth, memory, wall-clock, and output limits. A truncated result includes the cutoff and frontier information. Exact counts require completed enumeration of the specified observed graph.

Approximate distinct counts can use documented sketches only when labeled estimated, with algorithm parameters and error behavior. Exact policy checks must not silently consume approximate counts near a threshold.

Do not precompute a full transitive-closure table for every node at global scale. Cache popular reverse-reachability queries, compute bounded subgraphs on demand, and materialize only workloads justified by measurements.

## 10. Metric engine and measurement contracts

### 10.1 Metric registry

Each metric definition has a stable key, semantic version, owner, status, entity scope, input requirements, output type, unit, time semantics, supported dimensions, complexity estimate, source coverage rules, minimum sample rules, and test fixtures.

A changed denominator, filter, identity rule, or time basis requires a version change. Presentation-only text changes do not silently alter historical data. Deprecated metrics remain interpretable through their retained definitions.

### 10.2 Metric execution is a pure transformation

The metrics engine receives a pinned input snapshot and configuration. It produces observations and an execution manifest. It does not fetch current data, read ambient clocks, infer new identities, or invoke an LLM during a deterministic measurement.

Network acquisition, parsing, identity decisions, and classification happen upstream and have their own provenance. A metric that uses a classifier records the classifier output version as an input rather than hiding it inside an opaque score.

### 10.3 Metric specification example

```yaml
key: concentration.release_actor_count_80
version: 1.0.0
status: proposed
subject_kind: project
value_kind: integer
unit: actors
window:
  kind: rolling_duration
  duration_days: 365
  interval_semantics: half_open
population:
  event: release.published
  release_class: stable
  deduplicate_by: canonical_release_event
  actor_grouping: accepted_identity_revision
formula:
  operation: minimum_descending_actor_count_for_share
  share_numerator: 4
  share_denominator: 5
coverage:
  requires_complete_release_event_collection: true
  requires_attributed_actor_for_every_included_event: true
  on_missing_actor: partial
  on_empty_population: not_applicable
interpretation:
  observation: concentration_of_observed_release_actions
  does_not_establish: actual_permission_bus_factor
cost_class: small
privacy_class: project_aggregate
```

### 10.4 Typed values and denominators

Counts use sufficiently wide nonnegative integer representations. Monetary values use exact decimal amounts and currency identifiers. Ratios preserve numerator and denominator; rounded percentages are display values.

Durations store an integer time unit and time basis. Histograms retain bucket boundaries and counts. Quantiles declare exact or approximate algorithm and sample count. Do not serialize NaN or Infinity as a valid measurement.

A zero denominator produces `not_applicable`, not zero percent. Unknown counts remain unknown. A derived ratio from partial input is partial, even if its arithmetic is exact.

### 10.5 Windows and calendar semantics

Define rolling windows as UTC durations unless explicitly specified otherwise. Define calendar-month metrics using complete UTC months. A 365-day window and 12 complete calendar months are not aliases.

Snapshot metrics such as open-issue age are evaluated at an explicit cutoff. Longitudinal metrics distinguish available history from asserted project age. The oldest observed commit is not automatically the creation date of the project.

### 10.6 Evidence quality is multi-dimensional

Instead of one unsupported confidence decimal, store:

```text
source_authenticity: authenticated | public_unverified | imported | unknown
collection_completeness: complete_for_scope | partial | unknown
identity_resolution: direct_account | accepted_link | unresolved
temporal_precision: exact_source_time | interval | first_observed_only
attribution_basis: explicit | structural | heuristic | unknown
freshness: observation_age and policy freshness limit
measurement_method: direct | deterministic_derived | estimated | model_output
```

A later calibrated probability model can add numeric uncertainty, but it must coexist with these concrete attributes. A confidence interval concerns a defined statistical quantity, not generic “confidence that the project is good.”

### 10.7 Metric family aggregation

A family report shows selected observations, trends, coverage, and findings. It can summarize a distribution without converting it to a moral judgment.

Composite models need documented weights, normalization, missing-data handling, sample requirements, validation results, and sensitivity analysis. Correlated metrics must not be counted repeatedly to create artificial certainty. Hundreds of commit-derived variants are not hundreds of independent pieces of evidence.

### 10.8 Provenance DAG and invalidation

Derived metrics form a computation DAG. A correction to an identity link invalidates only metrics depending on that identity revision and their descendants. A new advisory can update exposure findings without recomputing every historical commit metric.

Store dependency memberships or partition-level input digests so invalidation is explainable. Recomputations create new result revisions; old published reports remain tied to their original evidence and may receive a superseded/corrected notice.

### 10.9 Catalog conventions

The catalog in the next section is intentionally broad. It describes measurement candidates and initial metric contracts, not a promise that every source can provide every metric.

Unless a row overrides these rules: `W` is an explicitly supplied half-open analysis window; `T` is a snapshot cutoff; `count` is an exact count over the declared observed population; `share` preserves numerator and denominator; and unknown or incomplete inputs propagate their status.

Cost tiers are `L` for metadata aggregation, `M` for bounded history/graph work, and `H` for expensive scans or external integrations. Evidence classes are `O` direct observations, `D` deterministic derivations, `E` estimates, and `X` experimental models. These classes describe methodology, not whether a metric is implemented.

## 11. Extensive metric catalog

The following catalog contains concrete metric definitions grouped by analytical purpose. Every row inherits the measurement contract in Section 10. Additional windows and strata are parameters, not excuses to count the same measurement as hundreds of independent signals.


### 11.1 Repository history and collection scope

Sources: native VCS metadata and fetch manifests. These measurements describe observed history, not independently verified project age. Preserve default-branch versus all-ref scope and imported-history flags.

| ID | Metric key | Unit | Definition and population | Class/cost |
|---|---|---|---|---|
| M0001 | `history.revisions_observed` | revisions | Distinct VCS-qualified revision IDs included in the declared snapshot. | O/L |
| M0002 | `history.revisions_reachable_default` | revisions | Distinct revisions reachable from the recorded default-branch tip at T. | D/M |
| M0003 | `history.revisions_reachable_all_refs` | revisions | Union of revisions reachable from the explicitly recorded ref set at T. | D/M |
| M0004 | `history.first_author_time` | timestamp | Minimum valid recorded author timestamp among included revisions; label source-authored time. | D/L |
| M0005 | `history.first_observed_public_revision_time` | timestamp | Earliest collector observation of a publicly retrievable revision; not first-ever publication. | O/L |
| M0006 | `history.history_span_days` | days | Difference between earliest and latest included valid revision timestamps using the chosen time basis. | D/L |
| M0007 | `history.shallow_boundary_count` | boundaries | Number of known shallow-history boundary revisions in the collected snapshot. | O/L |
| M0008 | `history.missing_object_count` | objects | Referenced objects required by the scan but unavailable after bounded retrieval. | D/M |
| M0009 | `history.ref_rewrite_events` | events | Observed ref changes where the previous tip is not an ancestor of the new tip. | D/M |
| M0010 | `history.default_branch_changes` | events | Distinct observed changes to the default-branch designation during W. | D/L |
| M0011 | `history.history_import_declarations` | declarations | Explicit migration/import records linked to this repository during W. | O/L |
| M0012 | `history.collection_complete_windows` | windows | Requested windows for which required history and ref coverage are complete, with total requested windows. | D/L |


### 11.2 Development activity and trajectory

Sources: revisions and accepted-change events. Report raw and filtered populations separately. Filters for generated files, bots, merges, or formatting are versioned; none establishes developer effort.

| ID | Metric key | Unit | Definition and population | Class/cost |
|---|---|---|---|---|
| M0013 | `activity.commits` | commits | Distinct included commits whose selected activity timestamp falls inside W. | D/L |
| M0014 | `activity.nonmerge_commits` | commits | Included commits in W with at most one parent; root commits remain included. | D/L |
| M0015 | `activity.merge_commits` | commits | Included commits in W with more than one parent. | D/L |
| M0016 | `activity.accepted_changes` | changes | Distinct change proposals accepted during W, independent of commit count. | D/L |
| M0017 | `activity.active_days` | days | UTC dates containing at least one qualifying event in W. | D/L |
| M0018 | `activity.active_months` | months | Complete UTC calendar months containing at least one qualifying event. | D/L |
| M0019 | `activity.longest_observed_gap_days` | days | Largest gap between qualifying events inside a completely observed window; boundary gaps reported separately. | D/L |
| M0020 | `activity.median_interevent_hours` | hours | Median interval between ordered qualifying events, with event count and time basis. | D/L |
| M0021 | `activity.weekly_count_slope` | events/week² | Ordinary least-squares slope of weekly event counts against week index; descriptive trend only. | D/L |
| M0022 | `activity.weekly_count_variance` | events² | Population variance of qualifying event counts across completely observed weeks. | D/L |
| M0023 | `activity.generated_change_share` | ratio | Events touching only classifier-identified generated paths divided by classified change events. | D/M |
| M0024 | `activity.bot_event_share` | ratio | Known-bot events divided by all included events, with unresolved-actor count displayed. | D/L |


### 11.3 Contributor participation

Sources: event actors and accepted identity revisions. Count accounts and actor clusters separately. Unresolved identity and automation classifications are visible, not forced into human totals.

| ID | Metric key | Unit | Definition and population | Class/cost |
|---|---|---|---|---|
| M0025 | `contributor.raw_author_identities` | identities | Distinct raw author identifiers in the selected revision population. | D/L |
| M0026 | `contributor.source_accounts` | accounts | Distinct source-native accounts with qualifying events in W. | D/L |
| M0027 | `contributor.accepted_actor_clusters` | clusters | Distinct accepted actor clusters represented in W under the pinned identity revision. | D/L |
| M0028 | `contributor.known_human_accounts` | accounts | Accounts explicitly classified human with qualifying activity in W; unknowns excluded and shown. | D/L |
| M0029 | `contributor.known_bot_accounts` | accounts | Accounts explicitly classified bot with qualifying activity in W. | D/L |
| M0030 | `contributor.unclassified_accounts` | accounts | Active accounts whose human, bot, or shared status is unresolved. | D/L |
| M0031 | `contributor.first_observed_contributors` | actors | Actors whose first observed qualifying project event falls in W. | D/L |
| M0032 | `contributor.single_event_contributors` | actors | Actors with exactly one qualifying event in W; not a lifetime one-off claim. | D/L |
| M0033 | `contributor.contributors_2_to_5_events` | actors | Actors with between two and five qualifying events inclusive in W. | D/L |
| M0034 | `contributor.contributors_6_to_20_events` | actors | Actors with between six and twenty qualifying events inclusive in W. | D/L |
| M0035 | `contributor.contributors_over_20_events` | actors | Actors with more than twenty qualifying events in W. | D/L |
| M0036 | `contributor.single_event_share` | ratio | Single-event actors divided by all actors with qualifying events in W. | D/L |


### 11.4 Persistence and retention

Sources: complete longitudinal event cohorts. Default cohort thresholds are proposed configuration, not universal scientific cutoffs. Retention denominators exclude right-censored or unobservable return windows.

| ID | Metric key | Unit | Definition and population | Class/cost |
|---|---|---|---|---|
| M0037 | `persistence.active_3_of_12_months` | actors | Actors active in at least three of the previous twelve complete UTC months. | D/L |
| M0038 | `persistence.active_6_of_12_months` | actors | Actors active in at least six of the previous twelve complete UTC months. | D/L |
| M0039 | `persistence.active_9_of_12_months` | actors | Actors active in at least nine of the previous twelve complete UTC months. | D/L |
| M0040 | `persistence.persistent_12m` | actors | Actors meeting the versioned six-month, 180-day-span, recent-activity cohort definition. | D/L |
| M0041 | `persistence.persistent_24m` | actors | Actors meeting the separately versioned twenty-four-month persistence profile. | D/L |
| M0042 | `persistence.persistent_event_share` | ratio | Qualifying events attributable to the persistent cohort divided by all qualifying events in W. | D/L |
| M0043 | `persistence.retained_90d` | ratio | Eligible newcomer actors returning in days 90 through 119 after first observation, divided by eligible actors. | D/L |
| M0044 | `persistence.retained_365d` | ratio | Eligible newcomer actors returning in days 365 through 394 after first observation, divided by eligible actors. | D/L |
| M0045 | `persistence.retention_censored` | actors | Newcomers whose specified return interval extends beyond the evidence cutoff or lacks required coverage. | D/L |
| M0046 | `persistence.median_observed_tenure_days` | days | Median first-to-latest qualifying activity span among the declared cohort. | D/L |
| M0047 | `persistence.returning_after_gap` | actors | Actors with a qualifying return after a configured inactivity gap, with complete intervening coverage. | D/L |
| M0048 | `persistence.cohort_survival_curve` | table | Time-indexed continuation estimates under a published event/gap definition, including censored counts. | E/M |


### 11.5 Maintainer roles and authority evidence

Sources: versioned declarations, authorized permission metadata, and role-specific events. Observed actions do not establish the complete set of authorized people or accounts.

| ID | Metric key | Unit | Definition and population | Class/cost |
|---|---|---|---|---|
| M0049 | `maintainer.declared_current` | actors | Accepted current maintainer-role assignments whose stated validity includes T. | D/L |
| M0050 | `maintainer.permission_observed_current` | accounts | Accounts with relevant permissions observed at T or within a stated freshness bound. | O/L |
| M0051 | `maintainer.observed_release_actors` | actors | Distinct actors associated with included release-publication events in W. | D/L |
| M0052 | `maintainer.observed_merge_actors` | actors | Distinct actors recorded performing accepted merge or integration events in W. | D/L |
| M0053 | `maintainer.observed_review_actors` | actors | Distinct actors submitting qualifying review events in W. | D/L |
| M0054 | `maintainer.active_declared_12m` | actors | Declared maintainers who also satisfy the selected persistent-activity profile. | D/L |
| M0055 | `maintainer.role_evidence_age_days` | days | Age of the latest supporting observation for each current role assertion. | D/L |
| M0056 | `maintainer.role_assignments_with_end_dates` | assignments | Role records with an explicitly documented end timestamp, not inferred inactivity. | D/L |
| M0057 | `maintainer.permission_inventory_coverage` | ratio | Entities with complete authorized permission enumeration divided by entities requesting that enumeration. | D/L |
| M0058 | `maintainer.release_role_automation_share` | ratio | Observed publications by known service/bot accounts divided by attributed publication events. | D/L |
| M0059 | `maintainer.review_share` | ratio | One actor's qualifying submitted reviews divided by attributed project reviews in W. | D/L |
| M0060 | `maintainer.unattributed_release_count` | releases | Included release events with no accepted publication actor attribution. | D/L |


### 11.6 Concentration and operational redundancy

Sources: role-specific counts. Every result names the event type. These are observational concentration metrics, not a literal prediction of project survival after a departure.

| ID | Metric key | Unit | Definition and population | Class/cost |
|---|---|---|---|---|
| M0061 | `concentration.top1_event_share` | ratio | Largest actor event count divided by total attributed counts for the chosen event type. | D/L |
| M0062 | `concentration.top3_event_share` | ratio | Sum of the three largest actor counts divided by total attributed counts. | D/L |
| M0063 | `concentration.top5_event_share` | ratio | Sum of the five largest actor counts divided by total attributed counts. | D/L |
| M0064 | `concentration.hhi` | decimal | Sum of squared actor shares for the specified event population. | D/L |
| M0065 | `concentration.effective_actor_count` | decimal | Reciprocal of HHI when the event population is nonempty. | D/L |
| M0066 | `concentration.absence_factor_50` | actors | Smallest descending actor set accounting for at least half of attributed events. | D/L |
| M0067 | `concentration.actor_count_80` | actors | Smallest descending actor set accounting for at least eighty percent of attributed events. | D/L |
| M0068 | `concentration.release_actor_count_80` | actors | The eighty-percent concentration count restricted to attributed stable-release publications. | D/L |
| M0069 | `concentration.review_actor_count_80` | actors | The eighty-percent concentration count restricted to qualifying review submissions. | D/L |
| M0070 | `concentration.component_single_actor_share` | ratio | Measured components with one observed qualifying maintenance actor divided by measured components. | D/M |
| M0071 | `concentration.months_with_two_release_actors` | months | Complete months with at least two observed release actors, with months containing releases as denominator context. | D/L |
| M0072 | `concentration.independent_role_overlap` | table | Intersection sizes among observed merge, review, and release actor sets. | D/L |


### 11.7 Succession and continuity of responsibilities

Sources: role changes and longitudinal activity. A change of primary actor is not evidence of abandonment. Post-transition outcomes are descriptive and do not imply causality.

| ID | Metric key | Unit | Definition and population | Class/cost |
|---|---|---|---|---|
| M0073 | `succession.declared_handovers` | handovers | Explicit accepted maintainer or release-role handover declarations in W. | O/L |
| M0074 | `succession.observed_primary_actor_changes` | events | Changes in leading role-specific activity share under a fixed window and tie rule. | D/M |
| M0075 | `succession.handover_overlap_days` | days | Overlap of documented outgoing and incoming role-validity intervals. | D/L |
| M0076 | `succession.observed_activity_overlap_months` | months | Complete months with qualifying activity by both identified transition participants. | D/L |
| M0077 | `succession.post_handover_next_release_days` | days | Time from declared handover to next observed stable release; censor when not yet observed. | D/L |
| M0078 | `succession.post_transition_release_count` | releases | Observed stable releases during the configured post-transition interval. | D/L |
| M0079 | `succession.post_transition_review_count` | reviews | Qualifying reviews during the configured post-transition interval. | D/L |
| M0080 | `succession.unfilled_declared_role_days` | days | Days a documented required role is explicitly declared vacant. | D/L |
| M0081 | `succession.persistent_cohort_entries` | actors | Actors newly meeting the persistence definition relative to the preceding comparable window. | D/L |
| M0082 | `succession.persistent_cohort_exits` | actors | Previously persistent actors no longer meeting the definition, with complete comparable coverage. | D/L |
| M0083 | `succession.core_overlap_jaccard` | ratio | Intersection of consecutive persistent cohorts divided by their union. | D/L |
| M0084 | `succession.continuity_observation_coverage` | ratio | Required transition follow-up intervals completely observed divided by all requested intervals. | D/L |


### 11.8 Change proposals and review process

Sources: forge, Gerrit, or patch-workflow records. Draft, closed, rejected, withdrawn, and accepted are distinct states. Missing proposal history must not be reconstructed as exact transitions.

| ID | Metric key | Unit | Definition and population | Class/cost |
|---|---|---|---|---|
| M0085 | `review.proposals_opened` | changes | Distinct proposals whose recorded creation event falls in W. | D/L |
| M0086 | `review.proposals_accepted` | changes | Distinct proposals with an observed acceptance event in W. | D/L |
| M0087 | `review.proposals_closed_unaccepted` | changes | Proposals observed closing without acceptance in W; no automatic rejection motive. | D/L |
| M0088 | `review.proposals_open_at_cutoff` | changes | Known proposals still open at T under complete current-state enumeration. | D/L |
| M0089 | `review.first_human_response_hours` | hours | Distribution from ready-for-review time to first qualifying non-author, non-bot response. | D/L |
| M0090 | `review.acceptance_latency_hours` | hours | Distribution from ready-for-review to acceptance for accepted proposals, with open-cohort censoring context. | D/L |
| M0091 | `review.independent_review_share` | ratio | Accepted proposals with at least one qualifying non-author review divided by accepted proposals with review coverage. | D/L |
| M0092 | `review.unreviewed_accepted_changes` | changes | Accepted proposals with complete review visibility and no qualifying independent review. | D/L |
| M0093 | `review.unique_reviewers_per_change` | distribution | Distinct qualifying reviewer counts for each proposal in the declared cohort. | D/L |
| M0094 | `review.review_rounds` | distribution | Observed submit-review-revision cycles under a documented state-transition definition. | D/M |
| M0095 | `review.stale_open_proposals` | changes | Open non-draft proposals exceeding the configured age threshold, with threshold shown. | D/L |
| M0096 | `review.review_backlog_age_quantiles` | hours | Declared exact or approximate quantiles of open ready-for-review proposal ages at T. | D/L |


### 11.9 Issues and responsiveness

Sources: issue-state and transition records. Closing an issue is not necessarily solving a defect. Response latency excludes the reporter and known bots unless the metric explicitly says otherwise.

| ID | Metric key | Unit | Definition and population | Class/cost |
|---|---|---|---|---|
| M0097 | `issue.opened` | issues | Distinct issues whose recorded creation timestamp is inside W. | D/L |
| M0098 | `issue.closed` | issues | Distinct observed close transitions in W, with repeated transitions separately identifiable. | D/L |
| M0099 | `issue.reopened` | events | Observed transitions from closed to open in W. | D/L |
| M0100 | `issue.open_at_cutoff` | issues | Known issues in an open state at T under complete enumeration. | D/L |
| M0101 | `issue.backlog_delta` | issues | Open count at end minus open count at start for comparable complete snapshots. | D/L |
| M0102 | `issue.first_maintainer_response_hours` | hours | Time to first response by an actor with accepted relevant role evidence. | D/L |
| M0103 | `issue.first_nonreporter_response_hours` | hours | Time to first qualifying response not attributed to the reporter or a known bot. | D/L |
| M0104 | `issue.unanswered_over_threshold` | issues | Covered issues with no qualifying response after a configured elapsed duration. | D/L |
| M0105 | `issue.open_age_quantiles` | hours | Age distribution of open issues at T with included status classes specified. | D/L |
| M0106 | `issue.close_reason_distribution` | table | Counts by explicit provider close reason or documented classifier output, retaining unknown reasons. | D/L |
| M0107 | `issue.confirmed_defect_count` | issues | Issues explicitly classified as defects by accepted project metadata or reviewed assertion. | D/L |
| M0108 | `issue.response_censored_count` | issues | Issues lacking sufficient follow-up time or coverage for the requested response outcome. | D/L |


### 11.10 Releases and supported versions

Sources: native release records, registry publications, tags, and explicit support declarations. Tags are not automatically releases; registry publications and project releases are linked rather than indiscriminately duplicated.

| ID | Metric key | Unit | Definition and population | Class/cost |
|---|---|---|---|---|
| M0109 | `release.stable_count` | releases | Distinct accepted stable releases with publication times in W. | D/L |
| M0110 | `release.prerelease_count` | releases | Distinct accepted prereleases published in W under ecosystem-native classification. | D/L |
| M0111 | `release.latest_stable_age_days` | days | Elapsed time from latest known stable publication to T. | D/L |
| M0112 | `release.interrelease_median_days` | days | Median interval between consecutive stable publications in the declared release line. | D/L |
| M0113 | `release.interrelease_variance` | days² | Variance of observed consecutive stable-release intervals in the selected line. | D/L |
| M0114 | `release.supported_lines` | lines | Release lines explicitly declared supported at T. | O/L |
| M0115 | `release.support_end_timestamp` | timestamp | Explicit support-end declaration for a release line, retaining issuer and evidence. | O/L |
| M0116 | `release.release_note_presence` | ratio | Included releases with retrievable associated notes divided by included releases. | D/L |
| M0117 | `release.withdrawn_publications` | publications | Registry release withdrawals or yanks explicitly observed in W. | O/L |
| M0118 | `release.tag_target_changes` | events | Observed changes in the revision or object identified by an existing tag label. | D/M |
| M0119 | `release.version_artifact_digest_changes` | events | Same package/version/artifact selector observed serving different digests. | D/M |
| M0120 | `release.release_source_mapping_coverage` | ratio | Included artifacts linked to an evidenced source revision divided by included artifacts. | D/L |


### 11.11 Direct dependencies and resolution

Sources: manifests, lockfiles, SBOMs, registry metadata, or approved resolvers. Requirements, possible resolutions, and actual observed resolved environments remain separate.

| ID | Metric key | Unit | Definition and population | Class/cost |
|---|---|---|---|---|
| M0121 | `dependency.requirements_direct` | requirements | Distinct direct declared requirements in the selected consumer snapshot. | D/L |
| M0122 | `dependency.resolved_direct_versions` | versions | Distinct directly resolved package-version nodes in the selected environment. | D/L |
| M0123 | `dependency.resolved_transitive_versions` | versions | Distinct reachable resolved package-version nodes excluding the root. | D/M |
| M0124 | `dependency.unresolved_requirements` | requirements | Included requirements lacking an accepted resolution for the selected context. | D/L |
| M0125 | `dependency.runtime_direct_count` | requirements | Direct requirements classified runtime by the ecosystem parser. | D/L |
| M0126 | `dependency.build_direct_count` | requirements | Direct requirements classified build/toolchain by the ecosystem parser. | D/L |
| M0127 | `dependency.optional_direct_count` | requirements | Direct requirements explicitly optional or conditionally activated. | D/L |
| M0128 | `dependency.unknown_scope_count` | requirements | Requirements whose purpose/scope could not be established. | D/L |
| M0129 | `dependency.unpinned_requirement_count` | requirements | Requirements not binding a single immutable version/artifact under ecosystem semantics. | D/L |
| M0130 | `dependency.artifact_digest_coverage` | ratio | Resolved nodes with verified expected digests divided by resolved nodes requiring artifacts. | D/L |
| M0131 | `dependency.maximum_observed_depth` | edges | Maximum shortest-path depth reached from the root in the completed bounded graph. | D/M |
| M0132 | `dependency.resolution_complete` | boolean | Whether all required reachable requirements were resolved for the declared context and limits. | D/M |


### 11.12 Dependency changes and freshness

Sources: comparable inventory snapshots, release timelines, and observed update changes. Version freshness uses an explicit compatible or supported target policy, never just the largest string.

| ID | Metric key | Unit | Definition and population | Class/cost |
|---|---|---|---|---|
| M0133 | `dependency_change.requirements_added` | requirements | New direct requirement identities between comparable observed snapshots. | D/L |
| M0134 | `dependency_change.requirements_removed` | requirements | Direct requirements absent from a later complete comparable snapshot. | D/L |
| M0135 | `dependency_change.resolved_versions_changed` | nodes | Dependencies whose accepted resolved version differs across comparable environments. | D/L |
| M0136 | `dependency_change.update_changes_accepted` | changes | Accepted changes explicitly modifying dependency versions under parser evidence. | D/M |
| M0137 | `dependency_change.eligible_update_count` | packages | Dependencies with a newer eligible target release under the declared policy. | D/M |
| M0138 | `dependency_change.publication_lag_days` | days | Age difference between selected version and policy-selected eligible target publication. | D/M |
| M0139 | `dependency_change.security_fix_adoption_days` | days | Time from eligible fixed-version publication to an observed dependency update; censor unresolved cases. | D/M |
| M0140 | `dependency_change.supported_line_share` | ratio | Resolved packages on explicitly supported lines divided by packages with support-status evidence. | D/L |
| M0141 | `dependency_change.removed_then_readded` | packages | Dependencies removed and later reintroduced within W in fully observed comparable snapshots. | D/M |
| M0142 | `dependency_change.source_location_changes` | events | Observed changes to dependency source locations or registries in the same consumer lineage. | D/M |
| M0143 | `dependency_change.lockfile_consistency_failures` | findings | Deterministic manifest-lock consistency checks failing under a named ecosystem validator. | D/M |
| M0144 | `dependency_change.unresolved_freshness_count` | packages | Dependencies for which eligible-target selection cannot be established. | D/L |


### 11.13 Downstream adoption counts

Sources: declared graph snapshots and accepted project mappings. All counts are counts in the observed graph, not global installations. Always name node type, edge filters, as-of time, and deduplication revision.

| ID | Metric key | Unit | Definition and population | Class/cost |
|---|---|---|---|---|
| M0145 | `downstream.direct_version_dependents` | versions | Distinct consumer versions with an allowed direct edge to the subject. | D/L |
| M0146 | `downstream.direct_package_dependents` | packages | Distinct consumer package identities after version deduplication. | D/M |
| M0147 | `downstream.direct_project_dependents` | projects | Distinct accepted consumer projects with allowed direct dependency evidence. | D/M |
| M0148 | `downstream.transitive_project_dependents` | projects | Unique accepted projects reaching the subject through allowed dependency paths, excluding the subject. | D/H |
| M0149 | `downstream.independent_project_families` | families | Known dependent project families after accepted mirror/fork-family deduplication. | D/M |
| M0150 | `downstream.runtime_project_dependents` | projects | Known projects with an active runtime dependency relation in the selected context. | D/M |
| M0151 | `downstream.build_project_dependents` | projects | Known projects with an active build/tool dependency relation in the selected context. | D/M |
| M0152 | `downstream.optional_project_dependents` | projects | Known projects with optional dependency declarations, activation status retained. | D/M |
| M0153 | `downstream.fresh_relation_share` | ratio | Dependency relations refreshed within the declared age bound divided by observed relations. | D/L |
| M0154 | `downstream.first_seen_dependents` | projects | Projects first observed as dependents during W; explicitly not proven new adoption. | D/L |
| M0155 | `downstream.confirmed_new_adoptions` | projects | Projects with evidenced dependency-introduction changes during W. | D/M |
| M0156 | `downstream.confirmed_removals` | projects | Projects with evidenced removal of the subject dependency during W. | D/M |


### 11.14 Downstream condition and feedback

Sources: independent intrinsic metrics of observed dependents. These measurements avoid recursive reputation. Covered and uncovered dependent populations must both be shown.

| ID | Metric key | Unit | Definition and population | Class/cost |
|---|---|---|---|---|
| M0157 | `downstream_condition.intrinsic_coverage_share` | ratio | Known dependent projects with requested intrinsic measurements divided by known dependent projects. | D/M |
| M0158 | `downstream_condition.active_change_dependents` | projects | Covered dependents with qualifying accepted-change activity in their declared recent window. | D/M |
| M0159 | `downstream_condition.persistent_core_dependents` | projects | Covered dependents with at least the configured persistent-contributor count. | D/M |
| M0160 | `downstream_condition.median_persistent_contributors` | actors | Median persistent-contributor count among covered independent dependent projects. | D/M |
| M0161 | `downstream_condition.release_redundancy_dependents` | projects | Covered dependents meeting the explicitly defined observed release-actor redundancy threshold. | D/M |
| M0162 | `downstream_condition.mature_supported_dependents` | projects | Dependents explicitly supported and meeting the declared maturity profile, not inferred from quietness. | D/M |
| M0163 | `downstream_condition.supported_version_adoption_share` | ratio | Covered dependency relations selecting a supported subject release line divided by support-classifiable relations. | D/M |
| M0164 | `downstream_condition.upgrading_dependents` | projects | Known dependents with an evidenced subject-version upgrade during W. | D/M |
| M0165 | `downstream_condition.upstream_contributing_dependents` | projects | Dependent projects with explicit accepted contributor/project links to upstream contributions in W. | D/M |
| M0166 | `downstream_condition.median_adoption_duration_days` | days | Median continuously observed dependency interval length, with censoring and gap rules. | D/M |
| M0167 | `downstream_condition.replacement_evidence_count` | events | Explicitly linked migrations away from the subject, separate from heuristic substitutions. | D/M |
| M0168 | `downstream_condition.continuity_conditioned_adoption_index` | index | Versioned weighted sum of independent dependent continuity measurements and relation freshness. | X/M |


### 11.15 Graph structure and ecosystem criticality

Sources: pinned projections. Centrality and reachability are structural measures, not safety scores. Approximate algorithms report parameters and uncertainty; bounded results report truncation.

| ID | Metric key | Unit | Definition and population | Class/cost |
|---|---|---|---|---|
| M0169 | `graph.node_count` | nodes | Distinct visible nodes in the specified projection. | D/L |
| M0170 | `graph.edge_count` | edges | Distinct visible typed edges satisfying projection rules. | D/L |
| M0171 | `graph.strongly_connected_components` | components | Count of SCCs under the projection edge direction and filters. | D/M |
| M0172 | `graph.cyclic_node_share` | ratio | Nodes in nontrivial SCCs or self-loops divided by included nodes. | D/M |
| M0173 | `graph.reverse_reachability_count` | nodes | Unique reachable consumer nodes from a subject over reversed allowed edges. | D/H |
| M0174 | `graph.pagerank` | decimal | Dependency-oriented damped rank under the recorded graph and parameter set. | D/H |
| M0175 | `graph.sampled_betweenness` | estimate | Betweenness estimated from a recorded deterministic sample of sources and normalization. | E/H |
| M0176 | `graph.root_to_subject_shortest_path` | edges | Shortest allowed dependency path from a selected root to the subject. | D/M |
| M0177 | `graph.independent_control_group_count` | groups | Known control groups among dependencies, with unknown-control nodes reported separately. | D/M |
| M0178 | `graph.shared_maintainer_pairs` | pairs | Dependency pairs sharing accepted relevant maintenance actors under the selected role definition. | D/M |
| M0179 | `graph.traversal_truncated` | boolean | Whether any configured traversal limit was reached before complete enumeration. | O/L |
| M0180 | `graph.projection_mapping_coverage` | ratio | Package nodes with accepted project mappings divided by package nodes requiring project projection. | D/L |


### 11.16 Advisories and security exposure

Sources: versioned advisory records, accepted aliases, explicit disclosure timelines, and resolved inventories. Absence of records is not proof of safety; exposure and exploitability remain distinct. [S19]

| ID | Metric key | Unit | Definition and population | Class/cost |
|---|---|---|---|---|
| M0181 | `security.known_advisory_records` | records | Advisory records matched to the subject before accepted cross-source alias deduplication. | D/L |
| M0182 | `security.known_unique_advisories` | advisories | Accepted advisory groups matching the subject and selected version/context. | D/M |
| M0183 | `security.affected_resolved_nodes` | nodes | Resolved dependency nodes matching at least one current known affected range. | D/M |
| M0184 | `security.advisory_match_unknown_nodes` | nodes | Inventory nodes for which supported version/range matching could not be completed. | D/M |
| M0185 | `security.fixed_version_available` | boolean | At least one policy-eligible unaffected/fixed release is documented for the selected advisory context. | D/M |
| M0186 | `security.public_disclosure_to_fix_days` | days | Elapsed time between evidenced public disclosure and fixed-release publication; negative intervals retained and explained. | D/M |
| M0187 | `security.acknowledgment_latency_hours` | hours | Time from an evidenced received report to acknowledgment when both are legitimately observable. | D/M |
| M0188 | `security.security_policy_present` | boolean | An accepted security-disclosure policy document is retrievable for the selected snapshot. | O/L |
| M0189 | `security.disclosure_contact_documented` | boolean | A designated disclosure route is explicitly documented; no unsolicited test messages are sent. | O/L |
| M0190 | `security.advisory_feed_age_hours` | hours | Elapsed time since the newest successful complete applicable advisory-feed refresh. | D/L |
| M0191 | `security.withdrawn_advisory_count` | advisories | Matched advisory records explicitly withdrawn by their issuer. | O/L |
| M0192 | `security.applicability_assertion_distribution` | table | Counts of affected, not-affected, fixed, investigating, or unknown assertions with issuer and evidence. | D/M |


### 11.17 Supply-chain provenance and artifact integrity

Sources: artifact digests, signature verification, attestations, and authorized control observations. Verification results identify trust roots, tool versions, and policy; presence is not verification. [S22]

| ID | Metric key | Unit | Definition and population | Class/cost |
|---|---|---|---|---|
| M0193 | `provenance.artifact_digest_present_share` | ratio | Selected artifacts with expected cryptographic digests divided by selected artifacts. | D/L |
| M0194 | `provenance.artifact_digest_verified_share` | ratio | Artifacts whose retrieved bytes match the expected digest divided by artifacts actually checked. | D/M |
| M0195 | `provenance.signature_present_share` | ratio | Selected artifacts with associated signature material divided by selected artifacts. | D/L |
| M0196 | `provenance.signature_verified_share` | ratio | Checked signatures passing the declared cryptographic identity policy divided by checked signatures. | D/M |
| M0197 | `provenance.signature_verification_unknown` | artifacts | Artifacts whose signatures cannot be evaluated under available trust material or supported formats. | D/L |
| M0198 | `provenance.attestation_present_share` | ratio | Artifacts with retrievable provenance attestations divided by selected artifacts. | D/L |
| M0199 | `provenance.attestation_subject_match_share` | ratio | Checked attestations whose subject digest matches the selected artifact divided by checked attestations. | D/M |
| M0200 | `provenance.source_revision_verified_share` | ratio | Checked artifacts with accepted source-revision bindings under the declared provenance policy. | D/M |
| M0201 | `provenance.builder_identity_count` | identities | Distinct verified builder identities in included attestations. | D/L |
| M0202 | `provenance.release_control_change_events` | events | Explicit observed changes to publishing permissions or accepted release-control declarations. | O/L |
| M0203 | `provenance.sbom_present_share` | ratio | Selected artifacts with associated retrievable SBOMs divided by selected artifacts. | D/L |
| M0204 | `provenance.artifact_source_mismatch_findings` | findings | Reproducible checks identifying disagreement between artifact and claimed source/provenance bindings. | D/H |


### 11.18 Build and CI observations

Sources: CI configuration, run records, and optional isolated reproducibility checks. A configuration file does not prove that the workflow executed. Canceled and skipped runs are not failures.

| ID | Metric key | Unit | Definition and population | Class/cost |
|---|---|---|---|---|
| M0205 | `build.ci_configuration_present` | boolean | A supported CI configuration is found in the selected source snapshot. | O/L |
| M0206 | `build.observed_runs` | runs | Distinct CI runs with a known final or current state in W. | D/L |
| M0207 | `build.successful_completed_runs` | runs | Completed runs whose source-native result maps to success. | D/L |
| M0208 | `build.failed_completed_runs` | runs | Completed runs whose source-native result maps to failure. | D/L |
| M0209 | `build.canceled_runs` | runs | Runs explicitly canceled in W, separate from failure counts. | D/L |
| M0210 | `build.success_share_completed` | ratio | Successful runs divided by completed success-or-failure runs in the declared cohort. | D/L |
| M0211 | `build.run_duration_quantiles` | seconds | Duration distribution for completed runs under consistent job/workflow scope. | D/L |
| M0212 | `build.rerun_count` | runs | Runs explicitly linked to a previous run attempt, not inferred from similar names. | D/L |
| M0213 | `build.matrix_environment_count` | environments | Distinct declared or observed OS/architecture/runtime build configurations, labeled by evidence type. | D/M |
| M0214 | `build.reproducibility_checks_completed` | checks | Independent rebuild comparisons performed under recorded source, environment, and instructions. | O/H |
| M0215 | `build.reproducible_artifact_share` | ratio | Byte-matching rebuild outcomes divided by completed comparable rebuild checks. | D/H |
| M0216 | `build.ci_coverage_age_hours` | hours | Age of latest successful complete enumeration for the requested CI run scope. | D/L |


### 11.19 Testing, fuzzing, and regressions

Sources: verified test reports, coverage artifacts, explicit regression records, and fuzzing reports. Test-file counts are not test quality; discovered defects do not automatically imply worse engineering.

| ID | Metric key | Unit | Definition and population | Class/cost |
|---|---|---|---|---|
| M0217 | `testing.test_files_observed` | files | Files classified as tests by a named path/language rule at the selected revision. | D/M |
| M0218 | `testing.test_cases_reported` | cases | Cases enumerated by a supported test-result artifact, not guessed from filenames. | O/L |
| M0219 | `testing.passing_cases` | cases | Test cases explicitly reported passing in a selected run. | O/L |
| M0220 | `testing.failing_cases` | cases | Test cases explicitly reported failing in a selected run. | O/L |
| M0221 | `testing.skipped_cases` | cases | Test cases explicitly reported skipped in a selected run. | O/L |
| M0222 | `testing.line_coverage` | ratio | Covered instrumented lines divided by eligible instrumented lines in a named report. | O/L |
| M0223 | `testing.branch_coverage` | ratio | Covered branches divided by instrumented eligible branches in a named report. | O/L |
| M0224 | `testing.fuzz_targets_observed` | targets | Distinct declared or reported fuzz targets, with declaration versus execution evidence separated. | D/M |
| M0225 | `testing.fuzz_execution_hours` | hours | Execution time explicitly reported by an authorized fuzzing system for the declared interval. | O/L |
| M0226 | `testing.sanitizer_run_count` | runs | Observed test/build runs with recorded sanitizer instrumentation and outcomes. | D/L |
| M0227 | `testing.confirmed_regression_links` | links | Explicit accepted links between a change/release and a regression report; no blame-only attribution. | O/M |
| M0228 | `testing.revert_links` | links | Explicit revert relationships between revisions, with reason unknown unless separately evidenced. | D/M |


### 11.20 Codebase and static-analysis observations

Sources: bounded static parsers and imported analysis reports. These are language/tool-specific measurements; unsafe syntax or complexity counts do not independently establish exploitability.

| ID | Metric key | Unit | Definition and population | Class/cost |
|---|---|---|---|---|
| M0229 | `code.source_file_count` | files | Files classified as source under the pinned language classifier and exclusion rules. | D/M |
| M0230 | `code.source_bytes` | bytes | Total bytes of classified source files excluding explicitly classified generated/vendor paths. | D/M |
| M0231 | `code.logical_lines` | lines | Logical source lines under a named language-aware counting algorithm. | D/M |
| M0232 | `code.generated_bytes_share` | ratio | Classifier-identified generated bytes divided by classified source bytes. | D/M |
| M0233 | `code.vendored_bytes_share` | ratio | Classifier-identified vendored bytes divided by classified source bytes. | D/M |
| M0234 | `code.language_distribution` | table | Source-byte counts by language classifier output, retaining unknown files. | D/M |
| M0235 | `code.complexity_distribution` | table | Function-level complexity values under a declared language/tool definition. | D/H |
| M0236 | `code.static_findings_by_rule` | table | Validated tool findings grouped by exact rule ID and severity scheme. | D/H |
| M0237 | `code.unsafe_construct_count` | constructs | Language-specific syntactic unsafe constructs under a named parser, with semantic limitations stated. | D/H |
| M0238 | `code.ffi_boundary_count` | boundaries | Supported-parser observations of external/native interface declarations or calls. | D/H |
| M0239 | `code.binary_blob_count` | files | Files classified as binary artifacts in the selected repository snapshot. | D/M |
| M0240 | `code.analysis_coverage_share` | ratio | Eligible source files successfully analyzed divided by eligible source files. | D/M |


### 11.21 Documentation and onboarding

Sources: source snapshots, documentation builds, and explicit links. Document presence is a process observation, not proof that instructions are accurate or that newcomers feel welcome.

| ID | Metric key | Unit | Definition and population | Class/cost |
|---|---|---|---|---|
| M0241 | `documentation.readme_present` | boolean | A recognized project overview document is present in the selected snapshot. | O/L |
| M0242 | `documentation.contributing_guide_present` | boolean | A recognized contribution guide is present or explicitly linked and retrievable. | O/L |
| M0243 | `documentation.installation_guide_present` | boolean | An installation/build guide is identified by an accepted document classification. | O/L |
| M0244 | `documentation.api_reference_present` | boolean | A retrievable API reference is explicitly associated with the selected release line. | O/L |
| M0245 | `documentation.example_program_count` | examples | Distinct documented example entry points under a declared source/path rule. | D/M |
| M0246 | `documentation.documentation_build_success_share` | ratio | Successful documentation builds divided by completed checked documentation builds. | D/M |
| M0247 | `documentation.broken_internal_links` | links | Internal documentation links failing a deterministic snapshot-local resolution check. | D/M |
| M0248 | `documentation.broken_external_links` | links | External links failing the declared bounded checking policy, with transient errors separate. | D/M |
| M0249 | `documentation.doc_last_change_age_days` | days | Time since latest recorded change to a specified documentation component. | D/M |
| M0250 | `documentation.release_documentation_binding_share` | ratio | Selected releases with explicitly version-matched documentation divided by selected releases. | D/L |
| M0251 | `documentation.onboarding_issue_labels_count` | issues | Open issues explicitly carrying configured newcomer-oriented labels. | D/L |
| M0252 | `documentation.translation_locale_count` | locales | Explicitly provided documentation locales, without inferring contributor geography. | D/L |


### 11.22 Compatibility and interface stability

Sources: support declarations, artifact metadata, test matrices, and supported API/ABI comparison tools. Platform support claimed in text and support demonstrated by tests remain separate.

| ID | Metric key | Unit | Definition and population | Class/cost |
|---|---|---|---|---|
| M0253 | `compatibility.declared_platforms` | set | Explicit platform identifiers in accepted support metadata. | O/L |
| M0254 | `compatibility.tested_platforms` | set | Platform identifiers represented in successful observed test runs. | D/L |
| M0255 | `compatibility.declared_architectures` | set | Explicit architecture identifiers in accepted support metadata. | O/L |
| M0256 | `compatibility.runtime_version_constraints` | set | Raw and normalized supported runtime/compiler constraints from accepted metadata. | O/L |
| M0257 | `compatibility.api_break_findings` | findings | Changes detected by a named API-compatibility tool between specified versions. | D/H |
| M0258 | `compatibility.abi_break_findings` | findings | Binary-interface incompatibilities reported by a supported tool for a specified target. | D/H |
| M0259 | `compatibility.deprecation_notice_days` | days | Time between an explicit deprecation declaration and documented removal, with unresolved cases censored. | D/M |
| M0260 | `compatibility.compatibility_test_count` | tests | Explicit cross-version compatibility test cases reported in selected runs. | O/M |
| M0261 | `compatibility.semver_claim_present` | boolean | Project explicitly declares a SemVer policy; not inferred solely from numeric version syntax. | O/L |
| M0262 | `compatibility.semver_policy_exception_events` | events | Documented or tool-confirmed changes conflicting with the project's declared policy under a reviewed rule. | D/H |
| M0263 | `compatibility.supported_line_fix_coverage` | ratio | Declared affected supported lines with an observed fix divided by declared affected supported lines. | D/M |
| M0264 | `compatibility.compatibility_evidence_unknown` | contexts | Requested platform/version contexts lacking adequate declared or demonstrated support evidence. | D/L |


### 11.23 Governance and organizational continuity

Sources: public versioned governance documents and authorized role evidence. No political, demographic, or personal-character inference is included. Unknown affiliations remain unknown.

| ID | Metric key | Unit | Definition and population | Class/cost |
|---|---|---|---|---|
| M0265 | `governance.governance_document_present` | boolean | A retrievable document explicitly describes project decision or stewardship processes. | O/L |
| M0266 | `governance.release_process_document_present` | boolean | A retrievable document explicitly describes release responsibilities and procedure. | O/L |
| M0267 | `governance.succession_process_document_present` | boolean | A retrievable document explicitly addresses handover or continuity of responsibility. | O/L |
| M0268 | `governance.code_ownership_rules_present` | boolean | Supported code-ownership or maintainer-path rules exist in the selected snapshot. | O/L |
| M0269 | `governance.public_decision_records` | records | Explicit governance decision records published during W. | D/L |
| M0270 | `governance.role_declaration_changes` | events | Observed changes to accepted governance or maintenance-role declarations. | D/M |
| M0271 | `governance.known_contributing_organizations` | organizations | Organizations linked through explicit accepted contribution-affiliation evidence valid during W. | D/M |
| M0272 | `governance.unknown_affiliation_event_share` | ratio | Attributed events lacking accepted organization affiliation divided by relevant events. | D/L |
| M0273 | `governance.organization_event_hhi` | decimal | HHI of events among known organizations, with known-coverage fraction and unknown bucket separately shown. | D/M |
| M0274 | `governance.independent_release_organizations` | organizations | Known independent organizations represented among observed release-role actors. | D/M |
| M0275 | `governance.governance_document_age_days` | days | Age of latest accepted revision of a specified governance document. | D/L |
| M0276 | `governance.project_archived_declaration` | boolean | An authoritative source explicitly marks the project or repository archived at T. | O/L |


### 11.24 Funding and maintenance support

Sources: explicitly public or authorized financial records and support declarations. Do not infer personal income, financial need, employment, or full-time capacity from contribution activity.

| ID | Metric key | Unit | Definition and population | Class/cost |
|---|---|---|---|---|
| M0277 | `funding.funding_links` | links | Distinct accepted public funding/support links associated with the project. | D/L |
| M0278 | `funding.public_funding_amount` | money | Published receipts for W in their original currencies and stated accounting basis. | O/L |
| M0279 | `funding.recurring_sponsors_reported` | sponsors | Recurring sponsors explicitly reported by a permitted source at T. | O/L |
| M0280 | `funding.funding_source_count` | sources | Distinct explicitly recorded funding sources for the declared project interval. | D/L |
| M0281 | `funding.funding_concentration_share` | ratio | Largest disclosed source amount divided by total disclosed amount in the same currency/accounting scope. | D/M |
| M0282 | `funding.funding_observation_age_days` | days | Age of the latest permitted funding observation. | D/L |
| M0283 | `funding.paid_maintenance_declarations` | declarations | Explicit public declarations of funded maintenance roles or contracts, without inferred hours. | O/L |
| M0284 | `funding.support_contract_options` | options | Distinct explicitly advertised project-maintenance support offerings. | O/L |
| M0285 | `funding.funded_deliverables_completed` | deliverables | Explicitly reported completion events for scoped funded maintenance deliverables. | O/L |
| M0286 | `funding.support_requests_open` | requests | Current explicit project requests for maintenance assistance under an accepted source. | D/L |
| M0287 | `funding.funding_history_complete` | boolean | Whether the available records are explicitly complete for the requested funding interval. | O/L |
| M0288 | `funding.intervention_outcome_records` | records | Documented before/after observations for support interventions, not causal impact estimates. | O/M |


### 11.25 Licensing and distribution metadata

Sources: manifests, license files, SBOMs, and explicit rights metadata. Parsing a license expression is not a legal opinion on compatibility or on a particular use.

| ID | Metric key | Unit | Definition and population | Class/cost |
|---|---|---|---|---|
| M0289 | `licensing.license_declaration_present` | boolean | An explicit license declaration is present for the selected project/package version. | O/L |
| M0290 | `licensing.license_expression_parseable` | boolean | The declared expression parses under the selected SPDX-expression grammar version. | D/L |
| M0291 | `licensing.license_file_count` | files | Files explicitly classified as license texts under the configured detector. | D/M |
| M0292 | `licensing.license_unknown_components` | components | Inventory components lacking an accepted license declaration. | D/L |
| M0293 | `licensing.license_expression_changes` | events | Observed changes to a component's declared license expression across comparable versions. | D/M |
| M0294 | `licensing.source_notice_presence` | boolean | Required-by-project or explicitly expected notice documents are present under the selected check profile. | D/L |
| M0295 | `licensing.license_evidence_conflicts` | conflicts | Disagreements among manifest, source-file, package, and SBOM license declarations. | D/M |
| M0296 | `licensing.redistribution_permission_status` | enum | Source-specific reviewed status of repo-health's ability to redistribute the collected observation class. | O/L |
| M0297 | `licensing.data_attribution_requirements` | set | Structured attribution obligations recorded for imported datasets. | O/L |
| M0298 | `licensing.dataset_terms_revision_age_days` | days | Elapsed time since the integration's terms-review record was last updated. | D/L |
| M0299 | `licensing.artifact_source_availability` | enum | Observed source availability state for an artifact, without asserting licensing compliance. | O/L |
| M0300 | `licensing.policy_license_match` | enum | Match, nonmatch, or unknown against a user's explicit accepted-license expression policy. | D/L |


### 11.26 Downloads, traffic, and references

Sources: authorized forge traffic, registry statistics, permitted reference indexes, and explicit citations. Keep source definitions and intervals separate; counts do not establish unique users, trust, or deployment.

| ID | Metric key | Unit | Definition and population | Class/cost |
|---|---|---|---|---|
| M0301 | `attention.package_downloads_reported` | downloads | Provider-reported downloads for an exact nonoverlapping interval and package scope. | O/L |
| M0302 | `attention.artifact_downloads_reported` | downloads | Provider-reported artifact download count with snapshot or interval semantics preserved. | O/L |
| M0303 | `attention.repository_clones_reported` | clones | Authorized provider-reported clone count for its exact reporting interval. | O/L |
| M0304 | `attention.repository_unique_cloners_reported` | provider_uniques | Provider-reported unique-cloner measure; not unique humans and not additive across days. | O/L |
| M0305 | `attention.repository_views_reported` | views | Authorized provider-reported page views for the exact source interval. | O/L |
| M0306 | `attention.stars_snapshot` | stars | Provider-reported star or equivalent-interest count at T, kept provider-specific. | O/L |
| M0307 | `attention.forks_snapshot` | forks | Provider-reported fork count at T, not independent active project count. | O/L |
| M0308 | `attention.referring_domains_observed` | domains | Distinct canonical referring domains inside the named index or crawl scope. | D/M |
| M0309 | `attention.reference_documents_observed` | documents | Deduplicated documents explicitly linking or citing the subject in the permitted corpus. | D/M |
| M0310 | `attention.academic_citations_observed` | citations | Structured citations linked through accepted package/project identifiers or reviewed references. | D/M |
| M0311 | `attention.social_mentions_observed` | mentions | Permitted indexed mentions with source and time scope, excluding unverified sentiment judgments. | D/M |
| M0312 | `attention.attention_coverage_start` | timestamp | Earliest completely covered interval for each traffic or reference provider. | O/L |


### 11.27 Forks, mirrors, and recovery options

Sources: repository lineage, current synchronization checks, release observations, and explicit compatibility declarations. A fork is a possible recovery resource, not an automatically usable replacement.

| ID | Metric key | Unit | Definition and population | Class/cost |
|---|---|---|---|---|
| M0313 | `resilience.accepted_mirrors` | repositories | Repositories with accepted mirror relationships to the subject at T. | D/L |
| M0314 | `resilience.mirror_ref_agreement_share` | ratio | Checked relevant refs with matching target identities across a specified mirror set. | D/M |
| M0315 | `resilience.mirror_lag_hours` | hours | Observed delay between upstream ref publication and matching mirror observation, with collection bounds. | D/M |
| M0316 | `resilience.independent_hosts` | hosts | Distinct registered source instances hosting accepted usable mirrors or archives. | D/L |
| M0317 | `resilience.active_forks` | repositories | Accepted forks meeting a published activity criterion independent of upstream synchronization. | D/M |
| M0318 | `resilience.fork_unique_commits` | commits | Fork revisions not reachable from selected upstream refs under the comparison snapshot. | D/M |
| M0319 | `resilience.fork_release_count` | releases | Distinct observed releases published by the fork during W. | D/L |
| M0320 | `resilience.compatible_alternative_declarations` | alternatives | Explicit project/tool assertions of replacement compatibility, with scope and evidence. | O/M |
| M0321 | `resilience.archive_identity_coverage` | ratio | Selected source snapshots with accepted archival identifiers divided by selected snapshots. | D/M |
| M0322 | `resilience.recovery_instructions_present` | boolean | Project explicitly documents recovery, mirroring, or replacement procedures. | O/L |
| M0323 | `resilience.upstream_unavailable_checks` | checks | Authorized availability checks failing under a specified retry policy, separate from abandonment. | O/L |
| M0324 | `resilience.replacement_validation_runs` | runs | Completed explicitly authorized tests of a proposed alternative in a declared consumer environment. | O/H |


### 11.28 Data quality, provenance, and observability

Sources: repo-health's own collection and computation ledger. These metrics are mandatory, because data gaps otherwise masquerade as changes in project behavior.

| ID | Metric key | Unit | Definition and population | Class/cost |
|---|---|---|---|---|
| M0325 | `coverage.requested_capabilities` | capabilities | Distinct capability requests in the selected scan or report plan. | D/L |
| M0326 | `coverage.available_capability_share` | ratio | Available supported capabilities divided by requested applicable capabilities. | D/L |
| M0327 | `coverage.unauthorized_capabilities` | capabilities | Requested capabilities unavailable due to missing authorization. | D/L |
| M0328 | `coverage.partial_collection_count` | collections | Collection runs explicitly incomplete for their requested scope. | D/L |
| M0329 | `coverage.source_freshness_hours` | hours | Age of latest successful complete collection per source/capability. | D/L |
| M0330 | `coverage.parser_error_count` | records | Records rejected or quarantined by the selected parser version. | D/L |
| M0331 | `coverage.identity_conflict_count` | assertions | Unresolved contradictory identity assertions affecting the report population. | D/L |
| M0332 | `coverage.mapping_conflict_count` | assertions | Unresolved project/package/repository mapping conflicts affecting the selected graph. | D/L |
| M0333 | `coverage.lineage_complete_share` | ratio | Published observations with complete authorized provenance chains divided by published observations. | D/L |
| M0334 | `coverage.replay_match_share` | ratio | Replayed deterministic observations matching stored outputs divided by replayed observations. | D/M |
| M0335 | `coverage.source_retraction_count` | records | Source observations withdrawn or removed under a recorded correction/retention process. | D/L |
| M0336 | `coverage.report_unknown_metric_share` | ratio | Requested applicable metrics returning non-value unknown states divided by requested applicable metrics. | D/L |


### 11.29 Policy findings and intervention outcomes

Sources: versioned policy evaluations and explicit action records. Policy decisions express chosen requirements; they are not certificates of intrinsic project safety.

| ID | Metric key | Unit | Definition and population | Class/cost |
|---|---|---|---|---|
| M0337 | `policy.evaluations` | evaluations | Completed evaluations of a named policy version over a declared subject set. | D/L |
| M0338 | `policy.allow_count` | decisions | Evaluations returning allow with all required rule results recorded. | D/L |
| M0339 | `policy.warn_count` | decisions | Evaluations returning warn under the declared policy precedence. | D/L |
| M0340 | `policy.deny_count` | decisions | Evaluations returning deny with at least one evidenced blocking rule. | D/L |
| M0341 | `policy.unknown_count` | decisions | Evaluations unable to decide because required evidence is unavailable or insufficient. | D/L |
| M0342 | `policy.active_exceptions` | exceptions | Unexpired approved exceptions applying to the subject and exact policy scope. | D/L |
| M0343 | `policy.exception_expiry_days` | days | Remaining time until each explicit exception expires. | D/L |
| M0344 | `policy.finding_resolution_days` | days | Time between an observed finding and evidenced resolution under the same rule semantics. | D/M |
| M0345 | `policy.recurring_findings` | findings | Resolved finding identities that recur under a documented equivalence rule. | D/M |
| M0346 | `policy.maintainer_disputes_upheld` | cases | Reviewed correction requests accepted as materially changing published facts or mappings. | D/L |
| M0347 | `policy.alert_precision_reviewed` | ratio | Human-adjudicated useful/valid alerts divided by adjudicated alerts for a named rule and sample. | E/M |
| M0348 | `policy.prevented_violation_records` | records | Observed attempted admissions blocked by a specific policy rule; not a claim of prevented real-world incidents. | O/L |


### 11.30 Advanced evidence and explicitly experimental analytics

These measurements require additional evidence pipelines or model validation. They are opt-in, separately budgeted, and excluded from default hard gates until their semantics and error rates are accepted.

| ID | Metric key | Unit | Definition and population | Class/cost |
|---|---|---|---|---|
| M0349 | `advanced.formal_claim_count` | claims | Explicit machine-readable proof claims attached to a specified source or artifact. | O/M |
| M0350 | `advanced.formal_claim_replay_success` | ratio | Claims whose proof checks succeed under a pinned trusted checker divided by replayed claims. | D/H |
| M0351 | `advanced.proof_artifact_binding_coverage` | ratio | Verified claims bound to the exact consumed artifact/source mapping divided by verified claims. | D/H |
| M0352 | `advanced.resource_bound_claims_verified` | claims | Replayed proofs of named resource bounds under recorded assumptions and input domain. | D/H |
| M0353 | `advanced.benchmark_regression_ratio` | ratio | Comparable current versus baseline benchmark result under a pinned workload and environment. | D/H |
| M0354 | `advanced.benchmark_measurement_variance` | units² | Variance across repeated comparable benchmark runs, with sample count and environment. | D/H |
| M0355 | `advanced.maintenance_discontinuity_forecast` | probability | Calibrated probability for an explicitly defined future observation outcome and horizon. | X/H |
| M0356 | `advanced.anomalous_publication_score` | index | Versioned model deviation for publication metadata relative to a defined project baseline. | X/H |
| M0357 | `advanced.coordinated_activity_indicator` | index | Validated graph/event anomaly output, not an accusation of malicious intent. | X/H |
| M0358 | `advanced.maintenance_support_scenario` | record | Assumption-explicit estimate of graph exposure potentially addressed by a scoped intervention. | X/H |
| M0359 | `advanced.semantic_replacement_candidate_count` | candidates | Candidates proposed by a labeled model and awaiting explicit API/functionality validation. | X/H |
| M0360 | `advanced.model_calibration_error` | decimal | Measured calibration error on a temporally held-out, documented outcome dataset. | E/H |

**Catalog size:** 360 distinct metric definitions across 30 families. Parameterized windows, role strata, package ecosystems, and graph projections can generate many more observations without changing those definitions.

## 12. Findings, interpretation, and policy evaluation

### 12.1 Findings are named claims with reasons

A finding consists of a stable rule ID, rule version, subject, observation interval, severity under a named policy, state, evidence references, explanation parameters, and suggested actions. It must distinguish what was measured from what the rule infers.

Example:

```json
{
  "rule_id": "continuity.release_concentration_increased",
  "rule_version": "1.0.0",
  "subject": "project:example-parser",
  "status": "open",
  "classification": "maintenance_continuity",
  "observed": {
    "previous_release_actor_count_80": 3,
    "current_release_actor_count_80": 1,
    "current_attributed_releases": 12,
    "unattributed_releases": 0
  },
  "interpretation": "Observed release actions became more concentrated.",
  "limitations": [
    "This does not enumerate everyone authorized to publish.",
    "The reason for the activity change is unknown."
  ],
  "suggested_action": "Review release-role coverage and documented recovery procedures."
}
```

The finding must not say that a person is unreliable, that compromise is imminent, or that a project is abandoned unless a separate authoritative declaration actually supports that statement.

### 12.2 Policy inputs

A policy receives a subject such as an exact package version or application inventory, a declared deployment context, a graph snapshot, metric results, acceptable freshness, and explicit exceptions.

Policies can express technical requirements, observational thresholds, or organizational choices. Keep them categorized. A license allowlist is a use-policy choice. A known affected-version match is a security observation. A minimum persistent-cohort count is a maintenance preference. None should masquerade as the other.

### 12.3 Four-valued evaluation

The policy engine returns:

| Outcome | Meaning |
|---|---|
| `allow` | All required evaluated rules permit the specified use. |
| `warn` | Use is permitted but one or more nonblocking concerns apply. |
| `deny` | At least one explicit blocking rule is satisfied by sufficient evidence. |
| `unknown` | Required evidence is insufficient to determine an applicable rule. |

Suggested overall precedence is `deny > unknown > warn > allow`. Individual rules preserve their own results. A CI integration may block both deny and unknown, but it must retain the distinction in its output.

An unknown must not become allow because a score defaults to zero or a missing JSON property is false. An unavailable optional metric should not cause unknown unless the policy actually requires it.

### 12.4 Proposed policy format

```yaml
schema_version: 1.0.0
policy_id: production-balanced
version: 1.0.0
context:
  dependency_scopes: [runtime, build]
  require_resolved_inventory: true
rules:
  - id: known-affected-runtime-version
    metric: security.affected_resolved_nodes
    operator: greater_than
    value: 0
    result_when_true: deny
    result_when_unknown: unknown
    max_age_hours: 24

  - id: source-artifact-binding
    metric: provenance.source_revision_verified_share
    operator: less_than
    value: {numerator: 1, denominator: 1}
    result_when_true: warn
    result_when_unknown: warn

  - id: concentrated-release-actions
    metric: concentration.release_actor_count_80
    operator: less_than
    value: 2
    result_when_true: warn
    result_when_unknown: warn
    minimum_population: 6

unknown_execution_behavior: block_and_request_review
```

The example thresholds are illustrative policy choices. A tool must not quietly install this policy as a universal definition of acceptable open-source software. The source-artifact-binding ratio requires a documented eligible population and does not establish correctness.

### 12.5 Exceptions and waivers

An exception identifies exact subjects, rules, rationale, approver, creation time, expiry, permitted contexts, and compensating evidence. It is not a permanent global “trusted package” flag.

An exception for version 2.4.1 does not automatically cover 2.4.2. An exception for a development-only environment does not cover production. Exception renewal requires a new explicit decision and leaves the original decision auditable.

### 12.6 No autonomous punitive behavior

repo-health does not automatically file accusatory issues, contact employers, report contributors, remove packages from registries, or publish exploitability claims from a maintenance metric. Automated actions are limited to authorized local policy decisions and notification destinations configured by the user.

Maintainer notifications should be opt-in or carefully governed. Findings include correction channels and can be suppressed when coverage is inadequate. The system must not turn community measurements into a harassment amplifier.

## 13. Persistence, storage, and query design

### 13.1 Authoritative stores

Use PostgreSQL for source catalogs, fetch ledgers, identities, assertions, canonical events, metric metadata, policy evaluations, and permission state. Store large raw payloads, repository packs, and immutable report bundles in content-addressed filesystem or object storage.

The first schema should have typed tables for high-volume core records and constrained structured payloads for source-specific extensions. Avoid both extremes: hundreds of rigid per-metric columns and a single unindexed JSON table containing the entire system.

### 13.2 Suggested table groups

```text
source_instance, capability_observation, credential_reference
collection_run, collection_page, collection_cursor, job, job_attempt
entity, project, repository, repository_location, repository_snapshot
revision, revision_membership, ref_observation
account, actor_cluster_revision, identity_assertion, role_assertion
change_proposal, change_revision, review_event, issue_state, issue_event
package, package_version, artifact, artifact_location
project_package_assertion, dependency_requirement, resolution_snapshot
resolved_dependency_edge, graph_projection, projection_membership
advisory_record, advisory_alias_assertion, affected_version_assertion
evidence_object, evidence_access_rule, evidence_retention_rule
metric_definition, metric_run, metric_observation, metric_input_manifest
finding, finding_revision, policy_definition, policy_evaluation, exception
correction_case, publication_record, audit_event, outbox_event
```

Tables use tenant/visibility scope consistently. Public and private observations can share conceptual entity identities without sharing access rights or derived statistics.

### 13.3 Canonical identity and uniqueness constraints

Source-native object uniqueness includes source instance, object type, immutable source identifier, and revision or event identity as appropriate. URLs alone are not primary keys for forge accounts or repositories when providers expose stable IDs.

A normalized event and its raw source-state record can both exist. Idempotency keys prevent duplicated ingestion without discarding a changed source representation. The same payload seen through two upstream aggregators is linked as shared provenance, not counted as two independent observations.

### 13.4 Indexing strategy

Index common queries: source object lookup, project/time events, actor/project/time participation, current role assertions, package/version identity, dependency adjacency in both directions, evidence digest lookup, and metric subject/key/window lookup.

Add partial indexes for active assertions, open findings, and runnable jobs where justified. Partition event and observation tables by time and, when measured necessary, by source or tenant. Partitioning is an operational choice, not a semantic shortcut that loses historical updates.

### 13.5 Bitemporal constraints

Validate interval ordering. Prevent overlapping accepted current revisions when a relationship is declared single-valued for a particular scope, while allowing multiple conflicting unaccepted assertions to coexist.

Use explicit relation-specific constraints: a project can have many repositories, while a particular provider repository ID should not have two accepted current locations with identical location roles unless mirroring semantics allow it.

Where a single database exclusion constraint cannot express the domain rule, enforce it in one transactional repository method and test concurrent writes. Document which invariants are database-enforced and which are application-enforced.

### 13.6 Raw-object commit protocol

Database and object-store writes are not one atomic transaction. Use a staged protocol:

1. Write the evidence blob to a temporary location under a byte limit.
2. Compute and verify its content digest.
3. Finalize an immutable object under a digest-addressed key.
4. Commit database references and page cursor in one transaction.
5. Garbage-collect finalized but unreferenced objects after a grace period.

Never advance the durable collection cursor before the database transaction references all accepted objects from that page. A retry reuses existing digest-addressed objects and deduplicates canonical records.

### 13.7 Job leases and concurrency

Start with database-backed jobs. A worker claims a runnable job in a short transaction, assigns a monotonically increasing fencing token, and receives a lease expiry. Heartbeats extend the lease only for the current token.

Final writes verify the token. A worker whose lease expired cannot publish results after a replacement worker has claimed the job. Treat external calls as at-least-once; ingestion must be idempotent.

PostgreSQL provides transactional locking primitives suitable for implementing this design, but the application still needs lease expiry, retry, fencing, and deduplication semantics. [S25]

### 13.8 Analytical snapshots

A graph snapshot manifest identifies entity/edge partitions, input cutoffs, mapping revisions, visibility scope, and digest checks. Snapshot publication happens only after all required partitions are present.

Columnar exports are useful for research and batch analytics, but every export has a data-rights profile and suppression rules. A public graph export must not expose private dependents through IDs, edge counts, or implicit adjacency gaps.

### 13.9 Cache correctness

A cache key includes tenant scope, subject identity, input snapshot, metric/rule version, configuration digest, identity revision, and publication policy revision. “Project ID” alone is not an adequate cache key.

Cache expiration is not the same as evidence freshness. A fresh cache can contain stale source observations. Reports include both timestamps.

### 13.10 Retention and replay

Retain enough evidence to substantiate published claims for the declared retention period, subject to rights and privacy constraints. Store large source repositories according to an explicit caching policy; it is not necessary to promise permanent full-source archiving.

A report carries a replayability status: fully replayable from retained authorized inputs, replayable with external source retrieval, partially replayable, or no longer replayable because inputs were withdrawn. Do not continue displaying a “fully reproducible” badge after losing required inputs.

## 14. APIs, CLI, and evidence interchange

### 14.1 API design rules

Use versioned HTTP/JSON APIs with stable schemas, cursor pagination, explicit result limits, request IDs, and machine-readable errors. APIs return measurement status alongside values. Dates and durations have documented representations.

Graph APIs require an explicit projection or return the default projection identifier. Historical queries distinguish `valid_at` from `known_at`. All responses include evidence cutoff and coverage summary where relevant.

### 14.2 Proposed endpoints

| Endpoint | Purpose |
|---|---|
| `POST /v1/scan-requests` | Request an authorized source or inventory scan. |
| `GET /v1/scan-requests/{id}` | Inspect status, limits, and partial results. |
| `GET /v1/projects/{id}` | Read project identity, mappings, and summary coverage. |
| `GET /v1/projects/{id}/metrics` | Read exact metric observations with filters. |
| `GET /v1/projects/{id}/continuity` | Read cohort, role, concentration, and handover evidence. |
| `GET /v1/projects/{id}/dependents` | Read bounded direct/transitive dependent projections. |
| `GET /v1/projects/{id}/dependencies` | Read upstream requirements or resolved graph views. |
| `GET /v1/packages/{id}/versions/{version_id}` | Read package-version and artifact observations. |
| `GET /v1/graphs/{id}/paths` | Request bounded path witnesses under explicit edge filters. |
| `GET /v1/metrics/definitions` | Discover versioned metric contracts. |
| `GET /v1/findings/{id}` | Read reasons, evidence, limitations, and correction state. |
| `POST /v1/policy-evaluations` | Evaluate a policy against a pinned subject/context. |
| `POST /v1/correction-requests` | Submit a supported identity or measurement correction. |
| `GET /v1/reports/{id}` | Retrieve a pinned, publication-filtered report. |
| `GET /v1/evidence/{id}` | Retrieve permitted evidence or a redaction/retention status. |

Paths are proposed contracts. Percent-encoding, request-size limits, authorization, and input validation are mandatory. Large graph jobs return job IDs rather than holding open unbounded requests.

### 14.3 Proposed CLI

```bash
repo-health scan https://forge.example.org/team/parser.git --output ./report
repo-health scan ./local-repository --offline --output ./local-report
repo-health inventory inspect ./software.cdx.json --format cyclonedx
repo-health report project:example-parser --as-of 2026-09-01
repo-health dependents package:example --projection observed-runtime
repo-health policy evaluate --inventory ./inventory.json --policy ./policy.yaml
repo-health explain finding:example
repo-health replay ./evidence-bundle --verify
```

The public server never interprets an arbitrary remote user's path as a filesystem path on the server. Local-path scans are CLI-local or explicitly mounted administrator jobs.

### 14.4 Proposed report envelope

```json
{
  "schema_version": "1.0.0",
  "report_id": "report:example",
  "subject": {"kind": "project", "id": "project:example-parser"},
  "generated_at": "2026-09-18T09:00:00Z",
  "valid_at": "2026-09-01T00:00:00Z",
  "known_at": "2026-09-18T08:30:00Z",
  "graph_projection": "projection:example-runtime",
  "identity_revision": "identity:42",
  "coverage": {
    "history": "complete_for_requested_window",
    "reviews": "partial",
    "traffic": "unauthorized",
    "private_dependents": "unobserved"
  },
  "sections": ["intrinsic", "continuity", "upstream", "downstream", "criticality"],
  "replayability": "retained_authorized_inputs",
  "limitations": ["Dependent counts describe the observed public graph only."]
}
```

### 14.5 Interchange formats

Support JSON Lines for event/evidence interchange and a manifest-based bundle for replay. Package inventories use explicit supported SPDX and CycloneDX versions. Parse formats according to their own schemas; do not silently accept fields from a newer version while claiming full compatibility. [S20] [S21]

A bundle includes schema versions, digests, source metadata, rights/retention annotations, identity assertions, metric definitions, and expected results. It may include only redacted or public subsets; the manifest states what has been omitted.

SWHID can be retained as an optional archival cross-reference, while artifact digests and source mappings remain independently represented. [S23]

### 14.6 Agent-facing contract

An agent integration returns structured facts and short evidence-linked explanations. It must not require the model to infer risk from a giant graph screenshot or scrape HTML badges.

The response can include candidate alternatives only when their functional suitability is explicitly established or clearly marked unvalidated. The agent receives exact unknowns and next actions, such as “obtain a resolved lockfile” or “review the package's missing source-artifact binding.”

The agent's action system, not repo-health alone, must enforce admission. Re-check identity and digest before installation to reduce time-of-check/time-of-use mismatch. Changes to version, registry, artifact, or platform invalidate a decision unless the policy explicitly covers them.

## 15. User interface and reporting

### 15.1 Default project page

The page opens with project identity, source coverage, latest observation times, and a small set of concrete findings. Tabs separate intrinsic condition, maintainers, upstream dependencies, downstream users, releases/security, and evidence.

Avoid a large green “safe” badge. A compact summary can say “12-month history covered; review data partial; two release actors observed; one affected resolved dependency.” This is less visually simplistic but more faithful to the evidence.

### 15.2 Continuity display

Show a role-specific activity matrix over months, persistent cohort sizes, release/review concentration, and explicit handover markers. Provide a table alternative to every visualization.

Distinguish actor identity corrections from real activity changes. Explain that gaps describe public observations, not working schedules or personal availability. Do not expose inferred daily work patterns or a contributor's presumed timezone.

### 15.3 Graph exploration

Use bounded neighborhood views and path explanations instead of rendering the entire ecosystem as an unreadable graph. Let users select runtime/build scope, version context, direct/transitive relationships, and time.

Display hidden-node counts caused by truncation separately from missing-data counts. Never show private node counts in a public graph. Export the selected graph's exact query parameters with the image or table.

### 15.4 Comparative reports

Compare like-for-like metrics with aligned windows and source coverage. Show unavailable cells explicitly. A project with private issue tracking should not look better because unresolved issues were invisible or worse because response metrics were absent.

Default ordering can be alphabetical, user-selected, or by a specific concrete measurement. Any composite ordering discloses the policy and missing-data treatment. Sponsor relationships must not secretly affect comparison order.

### 15.5 Explainability

Every metric exposes “definition,” “population,” “source,” “last observed,” “limitations,” and “reproduce.” Every finding lists the observations that triggered it and the ones that remain unknown.

A user should be able to move from a report summary to a metric ratio, from the ratio to its numerator and denominator memberships, and from those memberships to permitted source evidence.

### 15.6 Accessibility and low-cost operation

Provide semantic HTML, keyboard access, readable tables, text explanations for trends, and non-color-only state indicators. Keep the initial web interface small enough to remain usable on modest devices and slow connections.

Public reports should not require executing a heavy client application merely to read a project's data. Interactive graph rendering is progressive enhancement, not the sole way to access the information.

## 16. Security and threat model

### 16.1 Principal adversaries and failure sources

The system must withstand malicious repositories, package metadata, forged author strings, misleading project mappings, fake account activity, compromised collector credentials, hostile plugin code, malicious user-submitted URLs, and accidental provider/API changes.

It must also withstand nonmalicious distortions: history imports, bots, release freezes, vacations, migrations, large vendor drops, inaccessible private trackers, and incomplete archival data.

### 16.2 URL fetching and SSRF

Separate public-source fetching from administrator-approved internal connectors. Validate schemes, hostname resolution, actual connection destinations, redirects, ports, and every secondary fetch. Public fetching blocks loopback, private, link-local, metadata-service, and disallowed special-use destinations.

DNS and redirect validation must apply at connection time, not merely when accepting the initial URL. Use a controlled egress layer and credential audience binding. Consult OWASP's SSRF guidance when implementing the transport boundary. [S24]

### 16.3 VCS and archive isolation

Invoke VCS tools without a shell and with a minimized environment, clean home/config, bounded resources, restricted protocols, no inherited credentials, and a current patched toolchain. Disable unneeded hooks, filters, remote helpers, submodule recursion, and automatic large-file downloads.

An archive parser rejects path traversal, absolute-path extraction, unsafe links, excessive expansion, deeply nested structures, and unsupported entry types. Prefer reading bounded entries without extracting a complete archive.

No source-provided build command runs in the default pipeline. Optional dynamic checks use a stronger isolated environment with separate approval, no production credentials, explicit network policy, and disposable storage.

### 16.4 Credential management

Collectors receive only credentials for the registered source instance and capability. Store secret references rather than secrets in jobs. Redact headers, URL credentials, signed URLs, and provider error bodies before logging.

Rotate credentials, record their scope, and audit use. A redirect to another host must not receive the original source token. Plugins cannot read each other's credentials.

### 16.5 Data integrity and provenance attacks

Keep source authenticity separate from content correctness. An authenticated account can publish incorrect metadata. A signed commit can contain vulnerable code. A package can falsely claim a popular upstream repository.

Cross-check mappings with explicit project metadata, registry records, verified attestations, and reviewed assertions. Preserve conflicts. Never use a package's self-declared homepage alone to inherit another project's health measurements.

### 16.6 Metric gaming

Expected gaming includes splitting one change into many commits, creating fake forks, publishing trivial packages, coordinating stars, backdating commits, adding empty tests, creating unused CI configurations, and manufacturing contributor identities.

Defenses are mostly semantic: keep independent dimensions separate, show raw and filtered counts, distinguish configuration from execution, deduplicate project families, avoid rewards for raw volume, and label unverified identities. Anomaly detection can assist review but must not automatically accuse contributors.

### 16.7 Prompt injection and LLM use

Source text can contain instructions intended to manipulate a coding agent or report generator. Collectors and deterministic metrics treat all such text as data. A policy evaluation never delegates a blocking decision to free-form repository instructions.

LLMs may optionally draft explanations from structured observations or suggest candidate mappings for review. Store model identifiers, prompts/configuration digests, and inputs for reproducibility where appropriate. Model-generated assertions stay separate from verified evidence and cannot silently become facts.

### 16.8 Protecting the observer

repo-health itself needs dependency inventories, signed release artifacts, reproducible builds where practical, security review, backups, and documented incident response. Run its own metrics against itself while acknowledging that self-measurement is not independent assurance.

A compromise of the observatory could mislead many downstream decisions. The report-signing key and publication pipeline therefore require stronger isolation than an ordinary dashboard cache. Consumers should be able to pin report issuers and verify artifact/evidence digests.

## 17. Privacy, data rights, and governance

### 17.1 Data minimization

Collect the technical evidence required for declared measurements. Avoid unnecessary full-text retention of discussions when event metadata is sufficient. Do not infer sensitive personal attributes or combine public fragments into intrusive profiles.

Public availability does not automatically mean unlimited retention or redistribution. Every source integration receives a terms, licensing, privacy, and access review before public deployment.

### 17.2 Visibility lattice

At minimum, visibility classes are public, tenant-private, restricted-personal, embargoed-security, and suppressed. Derivations inherit restrictions from their inputs unless an explicitly approved aggregation mechanism permits broader publication.

A public report cannot include private dependent identities, private counts, or changes that reveal a tenant's adoption. Cache keys, graph snapshots, and exports are scoped accordingly. This must be tested with adversarial cross-tenant queries.

### 17.3 Contributor-facing protections

Provide a clear description of collected data, correction routes, identity-link policies, and publication limitations. Avoid leaderboards of individual “trust.” Account-level operational evidence is shown only when relevant and appropriately sourced.

Public reports must not imply that a volunteer owes continuous activity or a particular response time. Their purpose is to identify infrastructure dependencies and support needs, not to shame maintainers.

### 17.4 Metrics governance

Metric definitions live in a version-controlled registry with review history. Changes to defaults require an explanation of expected effects, example comparisons, and migration notes. A metric's author must document incentives it may create and likely confounders.

Maintainers and researchers should be able to propose corrections and alternative profiles. Public reports disclose model versions so methodology can be challenged and reproduced.

### 17.5 Funding and conflicts of interest

Core definitions and correction procedures must not depend on whether a project pays. Paid services can provide hosting, private inventories, integrations, and support, but must not secretly improve public ratings or suppress evidenced findings.

Sponsorship and commercial relationships are disclosed where they could affect prioritization. Public-interest crawl coverage should have transparent allocation rules rather than being wholly determined by customer size.

## 18. Statistical validity and interpretation limits

### 18.1 Measurement versus prediction

Most initial outputs are descriptive. Forecasting future maintenance discontinuity is a separate experimental capability requiring a defined outcome, observation horizon, training population, calibration, and uncertainty reporting.

An activity slope is not a probability of abandonment. A long-lived account is not a probability of benign intent. A model cannot learn a meaningful outcome from labels that merely repeat its own input heuristic.

### 18.2 Cohort comparability

Stratify evaluation by project age, ecosystem, forge, workflow, component type, maturity, and observed activity scale. A library maintained through emailed patches must not be evaluated as if missing pull requests meant no review.

Do not assign causal interpretations to group differences without an appropriate study. In particular, language choice, organizational affiliation, or funding level can correlate with many other variables.

### 18.3 Censoring and ascertainment

New projects have short histories. Migrated projects may have missing older records. Open issues and pending changes have unresolved outcomes. Vulnerability counts depend partly on discovery and disclosure practices.

Display censored samples and coverage limits. Do not reward a project for having fewer discovered vulnerabilities without considering observation and reporting differences. Do not punish active reporting as if it necessarily demonstrated worse underlying quality.

### 18.4 Backtesting

Historical evaluation uses data available at the historical cutoff. Future role changes, later advisories, subsequent corrections, and later repository mappings cannot leak into “what the system would have known” predictions.

Split evaluation temporally and by project family to reduce leakage from mirrors, forks, and repeated package versions. Compare against simple baselines and report false-positive burden, not only aggregate predictive accuracy.

### 18.5 Uncertainty near thresholds

A policy requiring two observed release actors should not treat incomplete attribution as a confirmed single-actor result. A graph-count estimate near a threshold should trigger exact computation or unknown, not an unjustified hard decision.

Expose sensitivity to identity merges, window choices, family deduplication, and model weights. When a conclusion changes substantially under reasonable choices, that instability belongs in the report.

## 19. Performance, scheduling, and operating costs

### 19.1 Cost-aware collection

Assign each job expected request count, bytes, CPU time, memory, and storage expansion. Budget expensive operations such as full-history diffs, blame, dependency closure, archive scanning, and benchmark execution separately from metadata refreshes.

Use conditional requests and source-supported incremental cursors when possible. Webhooks can accelerate refreshes but do not replace reconciliation because deliveries can be delayed or lost.

### 19.2 Adaptive refresh

Refresh cadence is source- and capability-specific. An advisory feed may need frequent updates; a stable archival repository may not. Newly observed releases can trigger targeted package/version enrichment rather than complete repository rescans.

A lower-priority lane must still prevent permanent starvation of quiet or less-popular projects. Explain freshness differences publicly so they are not mistaken for differences in health.

### 19.3 Initial service objectives

The following are proposed targets to validate, not performance claims:

| Objective | Initial target and qualification |
|---|---|
| Cached project summary | p95 under 500 ms on the declared reference workload. |
| Bounded one-hop dependency query | p95 under 1 second for a specified maximum edge count. |
| Metric replay | Bit-identical deterministic values and equivalent canonical output ordering. |
| Public-source freshness | Report source-specific achieved lag; do not promise a global instant view. |
| Partial-source failure | Other source results remain available with correct degraded coverage. |
| Recovery | No acknowledged committed evidence/page cursor lost within the declared backup policy. |

The implementation plan defines measurement fixtures and hardware before acceptance. Production targets should follow observed workloads, not invented global throughput estimates.

### 19.4 Storage growth

Model storage using actual retained payload sizes, revisions, evidence duplication, graph edges, and metric observation frequency. Do not assume every one of 360 metrics must be materialized for every project every day.

Materialize frequently used aggregates and compute rarely used variants on demand. Retain definitions and input manifests so recomputation is possible. Compress and deduplicate only within boundaries compatible with privacy and tenant isolation.

### 19.5 Graceful degradation

Under resource pressure, stop expensive optional scans before basic collection and evidence integrity. A report may omit advanced centrality or code complexity while preserving continuity metrics and explicit coverage.

No overload path changes unknown into healthy, hides an unresolved finding, or advances a cursor past unprocessed data.

## 20. Worked example: continuity, upstream risk, and downstream condition

Consider a synthetic project, `Example Parser`, with the following completely observed release window:

```text
12 stable releases
Alex published 9
Blair published 3
No unattributed publication events
```

The release shares are `9/12 = 0.75` and `3/12 = 0.25`. HHI is `0.75² + 0.25² = 0.625`; the effective observed release-actor count is `1 / 0.625 = 1.6`. The 50% concentration count is 1 and the 80% concentration count is 2.

Those statements are mathematically exact for the observed publication events. They do not establish that only two people have release credentials.

Suppose the project also has 100 contributor actors: 88 appear once, while 6 satisfy the persistent-12-month profile. Four declared maintainers perform reviews and two observed actors publish releases. The one-off share is 88%, but that alone does not establish poor continuity. The report examines persistent activity and role concentration directly.

Now consider the dependency projection:

```text
Application A -> Example Parser -> Utility C
Application B -> Example Parser -> Utility C
Application B -> Utility D      -> Utility C
```

Utility C has four unique transitive dependent projects in this synthetic projection: Example Parser, Utility D, Application A, and Application B. Application B is counted once even though there are two paths. If only three of those dependents have intrinsic metrics, downstream-condition coverage is `3/4`, not 100%.

Suppose Utility C's resolved version matches a known advisory. Example Parser's upstream report identifies the matched node and path. Its maintained downstream applications do not cancel that exposure. A policy can independently warn about release concentration and deny use of the affected resolved version.

The final explanation might read:

> Six persistent contributors and two observed release actors were identified in the covered window. Release actions were concentrated, with one actor publishing nine of twelve releases. Three of four known transitive dependents have intrinsic metrics. One resolved upstream dependency matches a known advisory. Repository clone statistics are unavailable under current authorization.

This is the intended product behavior: concrete, nuanced, and traceable without pretending to know more than the data supports.

## 21. Architectural decisions and open questions

### 21.1 Proposed decisions

| ADR | Decision | Rationale |
|---|---|---|
| ADR-001 | Forge-neutral canonical domain. | Prevent dependence on one provider's concepts. |
| ADR-002 | Evidence and assertion separation. | Preserve uncertainty, conflicts, and corrections. |
| ADR-003 | Bitemporal semantics. | Support historical truth and historical knowledge queries. |
| ADR-004 | Project/package/version/artifact separation. | Avoid identity and dependency errors. |
| ADR-005 | Conservative reversible identity resolution. | Reduce incorrect personal attribution. |
| ADR-006 | No universal public health score. | Preserve independent dimensions and uncertainty. |
| ADR-007 | Downstream intrinsic metrics calculated independently. | Avoid circular reputation propagation. |
| ADR-008 | Metadata-first, no arbitrary build execution. | Reduce scanner attack surface and operational cost. |
| ADR-009 | Modular application before distributed infrastructure. | Deliver a useful vertical slice with fewer failure modes. |
| ADR-010 | PostgreSQL plus content-addressed evidence storage. | Keep transactional semantics and replayable inputs. |
| ADR-011 | Versioned pure metric engine. | Make measurements auditable and reproducible. |
| ADR-012 | Four-valued admission results. | Keep insufficient evidence distinct from success or failure. |
| ADR-013 | Role-specific concentration and persistent cohorts. | Measure continuity without punishing occasional contributors. |
| ADR-014 | Public and private derivations isolated. | Prevent leakage through graph aggregates and caches. |
| ADR-015 | Open standards and upstream tools reused selectively. | Avoid unnecessary reinvention and preserve interoperability. |

### 21.2 Decisions requiring project-owner approval

The implementation language, project license, public hosting model, contributor-profile publication policy, data-retention durations, funded-data integration terms, and first package-ecosystem sequence remain explicit decisions.

This document proposes defaults where needed for planning. It does not treat those defaults as choices the user has already made.

### 21.3 Research questions

Important research questions include how continuity metrics relate to real maintenance outcomes; which downstream signals add information beyond intrinsic metrics; how to deduplicate project families without erasing genuinely independent forks; and how to quantify shared maintenance exposure without intrusive identity inference.

The project can be useful before these questions are fully answered. Start with observable facts, publish limitations, and add validated models later.

## 22. Definition of architectural success

repo-health succeeds architecturally when a project on an unfamiliar source host can be represented without changing the core domain; when a finding can be traced to retained evidence; when missing data remains explicit; when downstream condition and upstream exposure can be inspected independently; and when contributor continuity can be measured without turning the product into a personal reputation tribunal.

It should be possible to add a new metric without a schema redesign, add a new forge without changing the health engine, correct an identity without corrupting the event ledger, and replay a report without consulting an unrecorded live source.

Most importantly, an automated coding agent should receive enough structured evidence to make or request a responsible dependency decision—and should be unable to substitute a plausible-sounding story for required facts.

## 23. Primary references and verification notes

References establish external interfaces and terminology; repo-health's proposed architecture, formulas beyond attributed standards, thresholds, and roadmap are design recommendations. Web documentation can change. Implementers must pin supported API/schema versions and record access dates in connector manifests.

[S01]: https://git-scm.com/docs/git-log "Git: git-log documentation"
[S02]: https://git-scm.com/docs/git-clone "Git: git-clone documentation"
[S03]: https://www.chaoss.community/kb/metric-contributor-absence-factor/ "CHAOSS: Contributor Absence Factor"
[S04]: https://scorecard.dev/ "OpenSSF Scorecard"
[S05]: https://github.com/ossf/criticality_score "OpenSSF Criticality Score repository and dataset availability notice"
[S06]: https://docs.deps.dev/api/v3/ "deps.dev API: coverage and package/dependency contracts"
[S07]: https://ecosyste.ms/ "ecosyste.ms: data and tooling services"
[S08]: https://github.com/package-url/purl-spec "Package URL specification"
[S09]: https://docs.gitlab.com/api/ "GitLab APIs and extensibility"
[S10]: https://forgejo.org/docs/latest/user/api/usage/ "Forgejo API usage"
[S11]: https://docs.gitea.com/development/api-usage/ "Gitea API usage"
[S12]: https://developer.atlassian.com/cloud/bitbucket/rest/intro/ "Bitbucket Cloud REST API"
[S13]: https://gerrit-review.googlesource.com/Documentation/rest-api.html "Gerrit REST API"
[S14]: https://mercurial-scm.org/help/commands/log "Mercurial log command"
[S15]: https://subversion.apache.org/docs/ "Apache Subversion documentation"
[S16]: https://fossil-scm.org/home/doc/trunk/www/json-api/index.md "Fossil JSON API documentation"
[S17]: https://docs.github.com/en/rest/metrics/traffic "GitHub repository traffic API: permissions and reporting windows"
[S18]: https://docs.kernel.org/process/submitting-patches.html "Linux kernel patch submission and attribution conventions"
[S19]: https://google.github.io/osv.dev/ "OSV API and data model introduction"
[S20]: https://spdx.github.io/spdx-spec/v2.3/ "SPDX 2.3 specification; selected compatibility target, not a claim to be newest"
[S21]: https://cyclonedx.org/specification/overview/ "CycloneDX specification overview"
[S22]: https://slsa.dev/spec/v1.2/ "SLSA 1.2 specification"
[S23]: https://www.swhid.org/specification/v1.2/ "SWHID 1.2 specification"
[S24]: https://cheatsheetseries.owasp.org/cheatsheets/Server_Side_Request_Forgery_Prevention_Cheat_Sheet.html "OWASP SSRF prevention guidance"
[S25]: https://www.postgresql.org/docs/current/explicit-locking.html "PostgreSQL explicit locking documentation"
[S26]: https://reproducible-builds.org/docs/definition/ "Reproducible Builds definition"
[S27]: https://docs.github.com/en/rest/about-the-rest-api/api-versions "GitHub REST API versioning and supported versions"

| Reference | Use in this design | Verification note |
|---|---|---|
| [S01] / [S02] | VCS history and retrieval semantics. | Official Git documentation checked 2026-09-18. |
| [S03] | Contributor concentration terminology. | Preserve the published 50% definition when using the CHAOSS name. |
| [S04] / [S05] | Existing practice and criticality tools. | Criticality dataset availability was explicitly checked; do not assume a live cloud feed. |
| [S06] / [S07] | Optional ecosystem enrichment. | Coverage and applicable data terms require connector-specific review. |
| [S08] | Package coordinate interchange. | Pin supported package types and normalization rules. |
| [S09] / [S10] / [S11] / [S12] / [S13] / [S14] / [S15] / [S16] / [S27] | Source-specific adapter implementation. | Official API documentation checked 2026-09-21; instance versions and capabilities must still be probed because documentation does not prove deployment support. |
| [S17] | Authorized traffic limitations. | Fourteen-day windows and permission requirements must be modeled. |
| [S18] | Patch-series, review, testing, and attribution semantics. | Trailer meaning is retained rather than flattened. |
| [S19] / [S20] / [S21] / [S22] / [S23] | Advisory, inventory, provenance, and archival interoperability. | Pin supported format revisions and retain issuer evidence. |
| [S24] / [S25] | Transport hardening and transactional implementation. | Guidance supports implementation; it does not replace threat-model tests. |
| [S26] | Optional reproducible-build checks. | A meaningful result requires specified source, environment, and build instructions. |

SourceHut's manual could not be retrieved in this research pass. Accordingly, this architecture commits to a generic VCS baseline and an explicit future native-API validation task rather than asserting unverified endpoint behavior. No live instance, connector, database migration, or repo-health implementation was tested while preparing this design.
