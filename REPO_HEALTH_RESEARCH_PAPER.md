# Toward Evidence-Preserving Open-Source Ecosystem Intelligence

## A comparative architectural review of CHAOSS, Aveloxis, CollectOSS, GrimoireLab, ecosyste.ms, deps.dev, OpenSSF Scorecard, and Criticality Score for **repo-health**

**Review date:** September 19, 2026  
**Document version:** 1.0  
**Document type:** Technical research monograph and architectural synthesis; not a peer-reviewed publication  
**Target system:** repo-health, as proposed in [Architecture.md](Architecture.md) and [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md)  
**Evidence basis:** Targeted, read-only inspection of public repository code, interfaces, configuration, metric definitions, and official documentation  
**Companion material:** `SOURCE_MANIFEST.json`, `validation_examples.py`, and `VALIDATION_RESULTS.json`

> **Central conclusion:** repo-health should not recreate every collector, package index, identity tool, or security heuristic. Its strongest contribution would be a consistent, time-aware analytical system that preserves the meaning and provenance of existing evidence, measures maintenance continuity rigorously, and relates a project's condition to both its dependencies and the independently measured condition of its dependents.

## Abstract

The proposed repo-health project seeks to make the condition of open-source infrastructure observable through an extensive set of concrete measurements. Its intended scope includes repositories across heterogeneous hosting platforms, packages and releases, contributor and maintainer activity, upstream dependencies, downstream adoption, engineering practices, and the continuity of stewardship. Such a system should support responsible dependency selection by humans and coding agents without reducing complex evidence to a popularity score or a judgment of individual character.

This review examines the most relevant components of seven previously identified project families, with GrimoireLab and CollectOSS treated separately because their architectures differ substantially. The inspection extends into component repositories where the reusable functionality actually resides. The resulting source register contains 57 records spanning 21 repositories, plus official service documentation and the two local repo-health design baselines. The study is a purposive architectural review, not an exhaustive market survey, deployment benchmark, or security audit.

The findings substantially qualify a simple claim that repo-health would introduce an entirely new category. CHAOSS already defines contextual community-health measurements; CollectOSS and Aveloxis collect cross-project contributor activity; GrimoireLab provides heterogeneous collection, identity management, and contribution-role studies; ecosyste.ms supplies repository and package discovery and reverse-dependency interfaces; deps.dev exposes package-version resolution and provenance; and Scorecard separates raw observations, structured findings, and evaluation. Their most useful elements are complementary rather than mutually exclusive. [CH-SOFT] [AV-BREADTH] [CO-BREADTH] [GL-PERCEVAL] [GL-SH-MODEL] [EC-PKG-API] [DD-PROTO] [SC-MAINT]

The review also identifies semantic hazards that an integration must not conceal: lifetime contribution thresholds are not longitudinal retention; dependency requirements are not installed versions; provider counts can be estimates; multiple deliveries of one assessment are not independent evidence; source-host support does not imply equal metric coverage; and current API responses do not reconstruct what was known historically. Criticality Score additionally illustrates the distinction between reusable software and an available hosted feed: its documentation reports retirement of its Google Cloud infrastructure in August 2026. [AV-MET] [AV-ANALYSIS] [EC-HOST] [DD-PROTO] [CR-README]

The proposed synthesis combines reusable acquisition and analysis components with repo-health-owned measurement contracts, explicit missingness, reversible identity assertions, version- and context-aware dependency edges, temporal projections, and bounded downstream analysis. Sixteen original deterministic examples accompany the paper. They test small semantic invariants and illustrate failure modes; they do not constitute executions of the reviewed upstream systems. The recommended implementation sequence prioritizes a narrow, auditable vertical slice before broad ecosystem coverage, expensive static analysis, or predictive scoring.

**Keywords:** open-source sustainability; software repository mining; dependency graphs; software supply chain; maintainer continuity; contributor retention; measurement validity; temporal databases; provenance; software composition; reproducibility.

## Contents

- [Part I — Research framing and comparative method](#part-i-research-framing-and-comparative-method)
  - [1. The research problem](#1-the-research-problem)
  - [2. Methodology, scope, and evidential limits](#2-methodology-scope-and-evidential-limits)
  - [3. Requirements against which reuse is evaluated](#3-requirements-against-which-reuse-is-evaluated)
  - [4. Comparative synthesis at a glance](#4-comparative-synthesis-at-a-glance)
- [Part II — Detailed review of the existing systems](#part-ii-detailed-review-of-the-existing-systems)
  - [5. CHAOSS: the semantic foundation for a metric catalog](#5-chaoss-the-semantic-foundation-for-a-metric-catalog)
  - [6. Aveloxis: a reference for integrated collection and analysis](#6-aveloxis-a-reference-for-integrated-collection-and-analysis)
  - [7. CollectOSS: relational community evidence and cross-project participation](#7-collectoss-relational-community-evidence-and-cross-project-participation)
  - [8. GrimoireLab: the strongest reusable collection-and-enrichment toolkit](#8-grimoirelab-the-strongest-reusable-collection-and-enrichment-toolkit)
  - [9. ecosyste.ms: shared discovery infrastructure and the package–repository bridge](#9-ecosyste-ms-shared-discovery-infrastructure-and-the-package-repository-bridge)
  - [10. deps.dev: resolution semantics, package identity, and provenance](#10-deps-dev-resolution-semantics-package-identity-and-provenance)
  - [11. OpenSSF Scorecard: structured security evidence rather than an imported badge](#11-openssf-scorecard-structured-security-evidence-rather-than-an-imported-badge)
  - [12. OpenSSF Criticality Score: reusable signal separation and an operational warning](#12-openssf-criticality-score-reusable-signal-separation-and-an-operational-warning)
- [Part III — Architectural synthesis for repo-health](#part-iii-architectural-synthesis-for-repo-health)
  - [13. The proposed composition: reuse the components, own the semantics](#13-the-proposed-composition-reuse-the-components-own-the-semantics)
  - [14. Temporal correctness: what happened, what was observed, and what was known](#14-temporal-correctness-what-happened-what-was-observed-and-what-was-known)
  - [15. Contributor and maintainer continuity: an exact operational model](#15-contributor-and-maintainer-continuity-an-exact-operational-model)
  - [16. Downstream ecosystem health: the graph analysis repo-health should own](#16-downstream-ecosystem-health-the-graph-analysis-repo-health-should-own)
  - [17. Measurement contracts and a large metric catalog without semantic chaos](#17-measurement-contracts-and-a-large-metric-catalog-without-semantic-chaos)
  - [18. Operational architecture: correctness under failure and limited resources](#18-operational-architecture-correctness-under-failure-and-limited-resources)
  - [19. Security, privacy, and rights at the integration boundary](#19-security-privacy-and-rights-at-the-integration-boundary)
  - [20. Coding-agent integration: evidence-guided choices without false guarantees](#20-coding-agent-integration-evidence-guided-choices-without-false-guarantees)
- [Part IV — Evaluation, implementation priorities, and conclusions](#part-iv-evaluation-implementation-priorities-and-conclusions)
  - [21. Evaluation protocol](#21-evaluation-protocol)
  - [22. Reuse roadmap aligned with the existing implementation plan](#22-reuse-roadmap-aligned-with-the-existing-implementation-plan)
  - [23. Threats to validity and unresolved questions](#23-threats-to-validity-and-unresolved-questions)
  - [24. Conclusion](#24-conclusion)
- [Part V — Implementation-facing appendices](#part-v-implementation-facing-appendices)
  - [Appendix A. Component disposition and adoption gates](#appendix-a-component-disposition-and-adoption-gates)
  - [Appendix B. Concrete metric crosswalk](#appendix-b-concrete-metric-crosswalk)
  - [Appendix C. Proposed conformance-fixture catalog](#appendix-c-proposed-conformance-fixture-catalog)
  - [Appendix D. Executed synthetic examples and interpretation](#appendix-d-executed-synthetic-examples-and-interpretation)
  - [Appendix E. Source register and reproducibility notes](#appendix-e-source-register-and-reproducibility-notes)

<a id="part-i-research-framing-and-comparative-method"></a>

# Part I — Research framing and comparative method

<a id="1-the-research-problem"></a>

## 1. The research problem

### 1.1 From repository statistics to infrastructure evidence

The motivating problem is not a shortage of numbers attached to repositories. It is the difficulty of deciding what those numbers mean, how complete they are, and how they relate to the software that people actually rely upon. A count of contributors does not identify the people able to publish a release. A recent commit does not establish that an older supported branch receives security fixes. A package's dependency declaration does not establish the exact versions present in a particular deployment. A large dependent count does not reveal whether those dependents are active, independent projects or numerous historical versions and mirrors.

repo-health's original architecture correctly treats these as separate questions. It distinguishes intrinsic project condition, upstream exposure, downstream ecosystem condition, and criticality or resilience, with evidence coverage required alongside all four. This review preserves that separation. It does not propose replacing it with a single composite index. [RH-ARCH]

The distinction matters especially when software is generated quickly. An agent can select a plausible package, construct an application around it, and repeat that decision across many projects. The proposed response is not to assign moral credibility to developers or to declare every small library inadmissible. It is to make the dependency decision inspectable: identify the artifact and source project, show concrete evidence about maintenance and technical practices, disclose uncertainty, and apply a policy whose assumptions are explicit. This is the intended use of repo-health, rather than a claim that the present review has demonstrated a reduction in software failures.

### 1.2 The distinctive downstream question

A central requirement from the project discussions is to inspect not only what a project depends on, but also the condition of projects that depend on it. This is more demanding than drawing arrows in a package graph. It requires reliable package-to-project mappings, version and time semantics, deduplication, independent project measurements, and a declared population.

Consider a library with 10,000 observed dependent repositories. The useful questions include: how many still declare it in their current tracked state; how many are mirrors of the same project; how many have an independently observed maintenance core; how many upgrade promptly when a relevant release appears; and how many contribute fixes upstream. These are different estimands. Combining them without preserving their denominators creates an attractive but ambiguous dashboard.

The reviewed ecosystem already provides important prerequisites. ecosyste.ms distinguishes certain latest-version dependent queries from historical queries. CollectOSS and Aveloxis collect contributor activity beyond a project's own repository. deps.dev supplies version-scoped dependency information and project associations. None of those facts alone demonstrates the complete downstream-health model proposed here; together they make a substantial part of its implementation more attainable. [EC-PKG-API] [CO-BREADTH] [AV-BREADTH] [DD-PROTO]

### 1.3 The contributor question must be narrower than “trustworthiness”

The motivating intuition is reasonable: a stable maintenance core can provide continuity that a large number of isolated contributions does not. However, contributor counts, activity regularity, code review, release authority, and individual expertise must not be treated as interchangeable observations. Nor should a software observatory turn them into unsupported judgments about honesty, personality, intelligence, medical health, or personal circumstances.

A suitable contributor record might state that an account performed releases in eight distinct quarters, that two other accounts reviewed release changes, and that the project retained release activity after a handover. It should not state that the person is “91 percent trustworthy.” Occasional contribution is also not a defect: CHAOSS explicitly recognizes that such contributions can be meaningful and that irregular participation has many explanations. The analytical objective is to measure continuity and concentration without penalizing useful participation outside the core. [CH-OCC]

### 1.4 The practical research questions

This monograph addresses six questions:

1. **Which existing components can provide the largest amount of useful functionality without forcing repo-health to inherit their entire application architecture?**
2. **Which definitions, schemas, and algorithms should become reference material or test oracles rather than direct dependencies?**
3. **Where do apparently similar metrics have materially different meanings?**
4. **What information is lost when evidence passes through collectors, normalizers, service APIs, and dashboards?**
5. **Which capabilities genuinely need a repo-health-owned implementation to satisfy its temporal and graph requirements?**
6. **How should integration be evaluated before it influences human or automated dependency decisions?**

These questions deliberately emphasize reuse and correctness rather than a contest to name one overall winner. A package index and an identity manager solve different problems. The best component for discovery need not be the best component for longitudinal measurement.

<a id="2-methodology-scope-and-evidential-limits"></a>

## 2. Methodology, scope, and evidential limits

### 2.1 A purposive source-code review

The starting population was the shortlist from the preceding discussion: CHAOSS, Aveloxis, ecosyste.ms, deps.dev, Scorecard, Criticality Score, and GrimoireLab/CollectOSS. The review followed functionality into component repositories when a top-level README delegated the relevant work elsewhere. That expanded the corpus to include Perceval, SortingHat, GrimoireELK, Cereslib, Graal, SirMordred, and selected ecosyste.ms services and parsing infrastructure.

Repository files were retrieved through read-only GitHub access. Symbol searches were used to locate implementation files, and targeted ranges were read where files were long. Official service documentation was consulted for API behavior and operational status. The source register records the distinction between source code, configuration, documentation, specifications, and short code-search excerpts. An implementation described only in a README is not upgraded to a code-verified finding by appearing in this paper.

No upstream application was deployed. No complete upstream test suite was run. No reported fleet size, API throughput, collector success rate, or security efficacy was independently benchmarked. The review does not claim to have read every file in any repository. The supplementary Python examples are original, synthetic models of specific invariants, not substitutes for integration testing.

### 2.2 Four levels of statements

Throughout the paper, statements should be read in one of four ways:

| Level | Meaning | Example |
|---|---|---|
| **Implementation observation** | Supported by the inspected code or configuration | A queue advances a cursor only on successful completion |
| **Documented capability** | Stated in official documentation, but not independently exercised here | A parser lists support for a family of lockfiles |
| **Analytical deduction** | A consequence inferred from the observed implementation or a mathematical model | Ending-percentile classification can assign an unintuitive label at a boundary |
| **repo-health proposal** | A recommendation for the new system, not a claim about an existing product | Store both collection-attempt time and last-successful-snapshot time |

This classification is essential because a research-style document can otherwise make a proposal sound like an established result. The labels are also an appropriate model for repo-health's own evidence interface.

### 2.3 Revision handling

Many code files were read at explicit repository revisions obtained from source-search results. Those commit identifiers are recorded in the source manifest. Some documentation was read from a default branch and returned a file-object SHA. The manifest records that SHA as a **blob SHA**, not a repository commit. A blob identifies file content; it does not identify the complete state of the repository or all dependencies used to build it.

The paper's date is an access date, not a claim that every pinned revision was the newest commit on September 19, 2026. The purpose of pinning is to make the reviewed evidence identifiable. Before adoption, each integration needs a refreshed review of its chosen released version, dependency closure, and supported interfaces.

### 2.4 Reading depth varies by component

The most detailed implementation inspection concerns Aveloxis queueing and contributor breadth; CollectOSS contributor aggregation and breadth; Perceval's backend contract; SortingHat's identity and audit models; GrimoireELK and Cereslib contribution studies; ecosyste.ms repository, host, package, and parser code; deps.dev's API and resolver utilities; Scorecard's result pipeline; and Criticality Score's configuration and scorer.

Graal and SirMordred are assessed mainly through their detailed documentation. ecosyste.ms Commits, Issues, and Dashboards received scope-level README inspection, not a full source audit. Other components listed by GrimoireLab, such as KingArthur, Sigils, and Kidash, are acknowledged as adjacent tools but are not assigned code-verified capabilities in this review. This is a boundary on the conclusions, not a statement that those tools lack useful functionality. [GL-MODULES] [GL-GRAAL] [GL-MORDRED] [EC-COMMITS] [EC-ISSUES] [EC-DASH]

### 2.5 Why this is not a novelty claim

The previous conversational comparison overstated the novelty of several ingredients. Cross-project contributor discovery, contextual community metrics, contribution-role studies, reversible identity management, and evidence-oriented security checks are already present in the reviewed projects. The defensible opportunity is a more coherent combination of these capabilities around repo-health's specific requirements. [CH-CAF] [CO-BREADTH] [AV-BREADTH] [GL-ONION] [GL-SH-SPLIT] [SC-FINDING]

A complete novelty assessment would require a broader literature and product search, including additional repository-mining systems, software composition tools, research datasets, and commercial services. This paper does not establish that no existing system elsewhere performs downstream-health analysis or temporal evidence integration. It identifies what is reusable in the inspected shortlist and what remains to be designed for this particular project.

### 2.6 Source failures and incomplete retrieval

Some bulk or directory requests failed, and some long results were truncated. Targeted file reads were used instead. The mounted repo-health design documents were available locally, although conversation-file search did not retrieve their contents. These limitations do not invalidate the successful reads, but they preclude an assertion of exhaustive acquisition.

A lookup for a top-level `LICENSE` file in the inspected Bibliothecary fork returned not found. This review therefore does not assign that fork a verified license merely because a related project or earlier version used one. Resolving its actual license files and package metadata is an adoption prerequisite. This is precisely the kind of distinction repo-health should preserve instead of filling a missing field from a familiar project name.

<a id="3-requirements-against-which-reuse-is-evaluated"></a>

## 3. Requirements against which reuse is evaluated

### 3.1 The baseline is an evidence system, not a badge generator

The local architecture defines a proposed system, not an implemented platform. Its 360 candidate metrics across 30 families represent a catalog for phased development. They are not a claim that the existing repo-health software already calculates them. The implementation plan explicitly prioritizes a small vertical slice and gated milestones. [RH-ARCH] [RH-PLAN]

For this review, a component is valuable when it helps implement one or more of the following capabilities without destroying the information needed for the others:

| Capability | Required property |
|---|---|
| Multi-source acquisition | Host-independent identity, capability reporting, bounded and resumable collection |
| Evidence storage | Source, time, acquisition method, collector version, integrity and rights metadata |
| Metric calculation | Exact definitions, populations, denominators, windows, statuses and versioning |
| Contributor continuity | Distinct identities, roles, event types, persistence, retention and correction |
| Dependency analysis | Package/version/context identity, declared versus resolved edges and uncertainty |
| Downstream condition | Independent intrinsic metrics joined to a declared population of dependents |
| Security integration | Structured findings and locations rather than only aggregate scores |
| Operational resilience | Replay, freshness, failure preservation, source independence and cost controls |
| Decision support | Explainable, scoped policy results with explicit unknown states |

### 3.2 “Concrete” does not mean “automatically valid”

The user's insistence on numbers and exact data should be understood as a requirement for inspectable measurements, not as permission to assign spurious precision. A database can store `0.997` exactly enough for many purposes while the probability interpretation is completely unsupported. Conversely, a source can report an integer that is an estimate of a population rather than a count of its members.

The ecosyste.ms host model provides a concrete example: for sufficiently large hosts, the inspected implementation can derive repository counts from PostgreSQL statistics rather than enumerate every repository. That is a legitimate operational optimization. It is not the same measurement procedure as an exact count, and repo-health should preserve the distinction. [EC-HOST]

A metric contract should therefore include an estimand and a method as well as a value. “Distinct observed contributor accounts in the last 90 days” is a more defensible primitive than “maintainer quality.” “Number of verified dependency declarations in tracked current manifests” is different from “number of applications in the world using this library.”

### 3.3 Host independence includes unequal visibility

Forge-agnostic design does not mean every host can reveal every field. A generic Git repository can expose history without exposing issue responses, branch protection, release permissions, or clone traffic. An API token can change what a collector can observe. A public batch dataset may omit checks that the same tool can execute interactively.

Scorecard's documentation makes the last distinction explicit: its public weekly API results omit some checks because of acquisition cost. repo-health must not interpret their absence as failed engineering practice. [SC-README]

The correct abstraction is a capability and coverage matrix attached to observations. A connector can be healthy while an optional metric is unsupported. A project can be healthy while its host does not publish a desired signal. This is a primary acceptance criterion for every reuse decision.

### 3.4 Projects, repositories, packages, and people cannot be collapsed

A project may span several repositories; a repository may publish several packages; multiple package versions may correspond to one source revision; and one person may use several accounts. The reverse is also possible: a package can migrate repositories, an account can change control, and a source repository can contain multiple independently maintained components.

The reviewed tools offer useful pieces of this separation. SortingHat distinguishes identities from individuals and affiliations. deps.dev distinguishes package, version, and project keys. ecosyste.ms distinguishes hosts, repositories, package versions, and dependency declarations. repo-health should integrate those distinctions rather than choose whichever provider's identifier happens to be most convenient. [GL-SH-MODEL] [DD-PROTO] [EC-HOST] [EC-DEP]

<a id="4-comparative-synthesis-at-a-glance"></a>

## 4. Comparative synthesis at a glance

### 4.1 The strongest reusable contribution of each family

| Project family | Most useful contribution to repo-health | Preferred initial relationship | Principal caution |
|---|---|---|---|
| CHAOSS | Metric questions, definitions, filters, contextual interpretation | Standards crosswalk and metric contracts | A specification is not an executable or causally validated measure |
| Aveloxis | Integrated repository analysis and pragmatic durable collection patterns | Design reference, selected compatible components, optional adapter | Do not confuse documented metric labels with their exact temporal semantics |
| CollectOSS | Rich relational community events and contributor-breadth collection | Optional data import or sidecar; schema and query reference | Preserve event grain and verify aggregation cardinality |
| GrimoireLab | Heterogeneous collection, identity management, enrichment pipeline | Selective components or sidecars, not compulsory full-stack adoption | Component versions, license boundaries, and historical semantics require care |
| ecosyste.ms | Shared discovery, package/repository association and reverse-dependency access | Major enrichment and discovery source with cached evidence | Index size, estimated counts, selected coverage and current-state projections differ |
| deps.dev | Package-version interfaces, resolution utilities and provenance associations | Stable API adapter; resolver/semver utilities where appropriate | Public code is not the full service; graph context and ecosystem coverage vary |
| Scorecard | Typed security findings, raw/check/evaluation separation and remediation | Structured-result import plus bounded on-demand execution | Heuristics and unsupported checks are not security proofs or universal failures |
| Criticality Score | Raw-signal collection separated from configurable recomputation | Algorithm/configuration reference and historical snapshots | Hosted infrastructure retirement; legacy proxy names; importance is not health |

The table expresses design recommendations, not measured superiority or an exhaustive capability matrix. The detailed sections explain the evidential basis and adoption gates. [CH-CAF] [AV-QUEUE] [CO-BREADTH] [GL-PERCEVAL] [EC-PKG-API] [DD-RESOLVE] [SC-MAINT] [CR-SCORER]

### 4.2 The correct composition is not “install everything”

Deploying all reviewed systems together would introduce multiple databases, workers, caches, identity models, version schemes, and overlapping collectors. It would also create duplicate evidence and complex failure modes. There is no reason to inherit every operational dependency merely to use a useful measurement definition or parsing capability.

The recommended composition is a repo-health-owned canonical model and measurement layer, surrounded by replaceable acquisition and analysis adapters. Some adapters should call hosted APIs. Some should invoke pinned local tools in isolation. Some should read exports. Some functionality should be implemented natively because it embodies the project's core semantics. This allows reuse without making repo-health a dashboard attached to an uncontrolled collection of other dashboards.

### 4.3 The highest-value additions to the original design

The code review suggests several concrete additions to the baseline: an explicit source-lineage graph to deduplicate assessments delivered through multiple services; a distinction between collection attempt, successful acquisition, and successful projection times; a loss report for every normalization boundary; separate historical and latest-state dependency populations; and fixtures for threshold crossing, censored retention, and graph-instance identity.

These additions sharpen the original architecture rather than replacing it. They also make the first implementation more testable: correctness can be demonstrated on small fixtures before the project attempts to aggregate a large fraction of the open-source ecosystem.

<a id="part-ii-detailed-review-of-the-existing-systems"></a>

# Part II — Detailed review of the existing systems

<a id="5-chaoss-the-semantic-foundation-for-a-metric-catalog"></a>

## 5. CHAOSS: the semantic foundation for a metric catalog

### 5.1 What should be reused

CHAOSS is most useful to repo-health as a source of measurement questions, terminology, filters, and interpretation constraints. It should not be treated as one monolithic software dependency. The metric specifications and the software implementing related measurements occupy different architectural roles. The Metrics Development Working Group describes a process for defining and debating metrics, while the software catalog points to several distinct implementations. [CH-MET] [CH-SOFT]

The strongest reuse is therefore a standards crosswalk: for each repo-health metric that corresponds to a CHAOSS definition, record the upstream definition, its version or reviewed content hash, the exact local operationalization, and every deliberate difference. A dashboard should be able to say that a concentration measurement implements a particular CHAOSS concept with a specified event type and observation window. It should not claim blanket compatibility because both systems use the word “health.”

### 5.2 Contributor Absence Factor

The reviewed Contributor Absence Factor specification identifies the smallest number of contributors responsible for 50 percent of contributions. It permits variation by contribution type, time period, and repository group. This is a particularly good foundation for repo-health because it makes concentration measurable without requiring a vague judgment about whether a contributor is important. [CH-CAF]

Let a selected population of contributors have nonnegative event counts sorted in descending order:

\[
c_1 \ge c_2 \ge \cdots \ge c_n, \qquad C = \sum_{i=1}^{n} c_i.
\]

For a threshold \(q\), define:

\[
K_q = \min \left\{ k : \sum_{i=1}^{k} c_i \ge qC \right\}.
\]

The CHAOSS-oriented 50 percent measure corresponds to \(q=0.5\), subject to the chosen implementation's exact boundary convention. repo-health can use the same family at 25, 50, 75, and 90 percent, but the additional thresholds should be named as extensions rather than silently substituted for the published metric.

The event population must remain visible. `K50` for authored commits, published releases, completed reviews, and security-response actions answers four different questions. Combining them into one count requires a weighting model and loses the ability to inspect a specific operational responsibility. The first implementation should calculate them separately.

The zero-activity case also needs an explicit definition. When \(C=0\), a result of zero could be misread as a project that needs no maintainers. A better representation is an undefined statistic with an observed empty population. That is not the same state as failing to retrieve events.

### 5.3 Why concentration is not a literal replacement estimate

The term “bus factor” historically encourages readers to imagine the number of departures that would disable a project. Event concentration alone cannot establish that counterfactual. A contributor with relatively few commits may control release credentials or possess unique knowledge of a critical subsystem. Conversely, a contributor responsible for many routine changes may have several capable substitutes.

repo-health should therefore distinguish at least three concepts: measured concentration of an event type; observed redundancy of a role or permission; and a modeled estimate of operational loss after a departure. The first two can be supported with concrete observations. The third requires assumptions and validation. The reviewed CHAOSS specification provides an operational concentration measure, not evidence that every inferred departure scenario would actually occur. [CH-CAF]

A useful report might show `commit_K50=2`, `release_publishers_12m=1`, and `documented_release_deputies=2`, each with separate evidence. This is more informative than combining them into one “bus factor” that readers cannot interpret.

### 5.4 Occasional contributors and the correction to a simplistic drive-by ratio

The Occasional Contributors specification is directly relevant to the user's distinction between transient participation and a committed maintenance core. It recognizes irregular contributions, repeat occasional participation, contribution-count thresholds, and time gaps. It also emphasizes that such participation can make meaningful contributions to a project. [CH-OCC]

This suggests a two-axis analysis. One axis measures whether the project has persistent stewardship. The other measures how it attracts, accommodates, and benefits from less frequent participants. A project can have both a stable core and a high proportion of one-time bug fixes. A high occasional-contributor ratio alone does not demonstrate weak continuity.

A practical repo-health implementation should retain several exact observations: the number of people with one observed contribution; the number with contributions in several distinct periods; the fraction of events performed by a defined persistent cohort; and the number of people entering or leaving explicitly observed maintenance roles. These should not be collapsed into a penalty for “drive-by maintainers,” because many occasional contributors were never maintainers at all.

The definition of an event should also be stable. Four commits in one afternoon do not demonstrate four months of engagement. A project that squashes pull requests may have fewer commits for the same underlying work than a project that retains every intermediate commit. Counts can still be useful, but their interpretation requires the workflow context.

### 5.5 Upstream Code Dependencies

The reviewed upstream-dependency specification distinguishes direct and transitive relationships, circular dependencies, dependency versions, and execution contexts such as build, test, and runtime. It explicitly connects dependency awareness to evaluating the sustainability of upstream projects. This is important prior art for repo-health's upstream-health view. [CH-UP]

The most useful contribution is the insistence on declaring what is counted. A count of package names is not a count of package versions. Multiple versions of the same package may need separate treatment. A cycle should not create infinite or repeated counts. A language runtime may be intentionally excluded from one profile and included in another.

The specification is broad enough that an implementation still needs an executable contract. For example, “runtime dependency” can mean a manifest scope, a resolver's selected edge, a binary linkage, or an observed deployment requirement. repo-health should record these as distinct evidence types rather than assume the general specification resolves all ecosystem-specific semantics.

### 5.6 Turning specifications into executable contracts

A proposed contract should contain more than a formula:

```yaml
metric_id: community.contribution_concentration.k50
metric_version: 1
concept_reference: chaoss.contributor_absence_factor
entity_type: project
value_type: nullable_integer
unit: contributors
population:
  event_type: authored_commit
  branch_scope: configured_project_default_branches
  actor_resolution: identity_snapshot_id
  bot_treatment: separate_population
window:
  start_inclusive: true
  end_exclusive: true
zero_population: undefined_statistic
coverage_required:
  - repository_history_scope
  - identity_resolution_coverage
extensions:
  - supports_parameterized_threshold_q
```

This is a repo-health proposal, not a CHAOSS-provided schema. Its purpose is to make the relationship between a published concept and a running calculation auditable. A metric can conform to the conceptual definition while still differing in branch scope or bot treatment; those differences need to be inspectable.

### 5.7 Documentation generated from the same contract

A useful lesson from Aveloxis's documented metric catalog and Scorecard's contributor workflow is to generate API descriptions, user-facing explanations, and test expectations from one versioned definition where feasible. This avoids a recurring failure mode in which a dashboard label, REST response, and SQL query drift apart. [AV-MET] [SC-WRITE]

For repo-health, the CHAOSS crosswalk should be part of that definition. The interface can expose the human question, operational formula, exclusions, required data, and warnings from a common registry. That does not make every metric automatically valid, but it makes disagreement about a definition easier to locate and correct.

### 5.8 Reuse decision

CHAOSS should be a **semantic dependency**, not a compulsory runtime service. Its definitions should inform the metric registry and interpretation text. The implementation should retain the freedom to add stricter temporal contracts and additional measurements while identifying them as extensions. The adoption gate is a reviewed crosswalk with examples that establish exactly which population is measured.

The principal research task is not to invent hundreds of synonyms for existing concepts. It is to operationalize useful concepts consistently, test them, and explain where the source data do not support them.

<a id="6-aveloxis-a-reference-for-integrated-collection-and-analysis"></a>

## 6. Aveloxis: a reference for integrated collection and analysis

### 6.1 Why Aveloxis deserves close attention

Aveloxis overlaps with repo-health more substantially than a simple repository dashboard would. Its documentation describes collection, relational processing, contributor information, dependency analysis, security enrichment, code analysis, and historical observations within an integrated Go application. The architecture describes JSONB staging and normalized data, with separate operational and analysis concerns. [AV-README] [AV-ARCH]

For repo-health, its greatest value is not a promise that the entire application can be adopted unchanged. It is a collection of concrete solutions to the operational work that sits between an API response and a reliable metric. Queueing, cursors, partial collection, contributor discovery, snapshot replacement, and catalog consistency are all areas where seemingly small implementation choices determine whether later analytics can be trusted.

### 6.2 Staging before relational processing

The documented staging approach separates source acquisition from transformation into normalized tables. That separation is useful because a collector can retrieve data independently of the order in which related entities become available. Processing can subsequently establish identities and relationships in a controlled order. [AV-ARCH]

repo-health should adopt the principle but make the evidence contract more explicit. A staged response should carry the source endpoint, source identity, collection run, requested scope, response or object digest, collector version, timestamps, and access restrictions. Normalization should produce a projection that refers back to that evidence rather than replacing it.

This gives two distinct forms of replay. Acquisition replay repeats a source request, potentially receiving changed data. Normalization replay reprocesses a retained evidence object using a different parser or identity snapshot. Only the latter can reproduce what was actually observed previously without relying on the upstream service to preserve the old state.

The storage design should also avoid treating JSONB as a universal answer. Small structured source objects may fit comfortably in PostgreSQL; large archives, build artifacts, or response bundles may belong in content-addressed object storage. The unifying feature is not one storage engine, but a stable evidence reference and transactional linkage to derived records.

### 6.3 PostgreSQL queueing and atomic claims

The inspected queue implementation uses an atomic update around a selected due job, with row locking that skips rows already locked by another worker. It records operational fields such as lock state, attempts, errors, timing, and collection flags. Enqueue behavior also protects running work from being casually reset by a duplicate request. [AV-QUEUE]

This is a strong reference for repo-health's initial deployment because the existing plan already favors a modest PostgreSQL-centered stack. A database-backed queue can keep job state and domain updates close together without immediately adding an independent message broker. The review does not establish a throughput ceiling or prove that PostgreSQL remains the right queue at every future scale; it establishes that a coherent first implementation exists in the inspected source.

repo-health should add or verify several invariants before copying the pattern. A lease must identify its owner or generation so that a worker whose lease expired cannot overwrite a newer worker's result. Completion must be idempotent. Retries must not duplicate logical events. Queue priority must not indefinitely starve low-volume hosts. A job claiming mechanism does not by itself provide exactly-once execution.

### 6.4 Collection-start watermarks

One especially useful detail is the queue's handling of incremental cursors. The inspected code advances a cursor only on successful collection and uses the collection's start time, with whole-second handling, rather than simply using the completion time. [AV-QUEUE]

The underlying problem is easy to miss. Suppose a collection begins at time 100 and finishes at time 200. An upstream object with update time 180 can appear after the collector has passed the page where it would have been encountered. Advancing the next cursor to 200 risks skipping it permanently. Advancing to 100 creates overlap that can recover it, provided event insertion is idempotent.

This does not solve all pagination and eventual-consistency problems. A source may backdate updates, omit events, reorder pages, or have a bounded history. Nevertheless, it is a materially better default than a completion-time watermark. repo-health should combine collection-start overlap with provider-specific safety windows, periodic reconciliation, source-native object IDs, and a distinct record of collection coverage.

The accompanying synthetic test demonstrates the timing distinction on an invented event. It does not reproduce a particular incident in Aveloxis or establish that every provider's consistency behavior is handled by the same overlap duration.

### 6.5 Contributor breadth beyond the tracked repository

Aveloxis's contributor-breadth collector is particularly relevant to repo-health's cross-project maintainer analysis. The inspected implementation requests public user events, discovers repositories in that activity, uses parallel acquisition with coordinated persistence, and preserves retry behavior around successful writes. [AV-BREADTH]

The useful abstraction is an **observed activity edge** from an account to a repository, with a source-native event identity, event type, and timestamp. Such edges can reveal that a contributor active in one tracked project also participates elsewhere. They can seed further discovery or enrich a profile of observed work.

The important limitation is that an account event feed is not a complete professional history. Its availability and temporal coverage are source-dependent. A missing event is not evidence that the person never contributed elsewhere. The existence of an event also does not prove that the person maintains the target project: a comment, issue opening, fork, or contribution can reflect very different responsibilities.

repo-health should therefore preserve the event category and the acquisition window. A derived field should be named something like `distinct_repositories_with_observed_events_90d`, not `projects_maintained_lifetime`, unless additional evidence supports the latter. This is an example of extracting the best piece of an implementation without carrying over an overly broad interpretation.

### 6.6 Persistence before marking work complete

The breadth collector's coordination and persistence ordering provide another valuable lesson. An acquisition should not be marked successfully consumed before the corresponding events are durably stored. Otherwise a transient database failure can create a permanent gap that is hidden by an advanced cursor or an “already scanned” marker. [AV-BREADTH]

repo-health should make this an explicit transactional rule: evidence persistence, projection state, and successful-watermark advancement must have a consistent commit boundary. Where they cannot share a transaction, use a durable outbox or another recoverable handoff rather than an implicit ordering assumption.

A narrow persistence interface, as seen in the inspected collector, is also useful for testing. It permits deterministic failure injection at the exact points where data loss would otherwise occur. Tests should simulate a failed write after successful network retrieval and verify that the next run can recover the same events without multiplying them.

### 6.7 Dependency analysis as a pluggable stage

The analysis documentation describes source checkouts, lockfile and manifest parsing, registry metadata, license information, code metrics, and security-related enrichment. It also describes transactional history replacement rather than treating every collection as a destructive overwrite. [AV-ANALYSIS]

The best reusable pattern is an analysis job over an identified source snapshot. Inputs should include the repository revision or archive digest, selected paths, parser or tool version, configuration, and execution environment. Outputs should be structured observations and a status, not a console log whose meaning must be guessed later.

For repo-health, expensive analysis should be decoupled from routine metadata collection. A release snapshot or a changed lockfile may justify reanalysis; an unrelated issue comment usually does not. Content-addressed caching can prevent repeated analysis of identical trees or manifests, but the cache key must include tool and configuration versions as well as source bytes.

### 6.8 Snapshot history and the empty-result distinction

Aveloxis's documentation describes preserving historical analysis and replacing the current snapshot transactionally. Failed analysis should not erase the previous successful result, while a successful empty result can legitimately remove obsolete current observations. [AV-ANALYSIS]

repo-health should make this distinction visible at the API level. A previous dependency list may remain available after a failed new scan, but it must be marked with its actual last-successful date and the subsequent failure. It should not look freshly verified merely because the repository was contacted recently.

A useful state record contains at least: last attempt, last successful acquisition, last successful normalization, last successful analysis, and the revision to which the current projection applies. These may differ. Collapsing them into one `updated_at` field makes operational activity indistinguishable from evidence freshness.

### 6.9 Metric labels need implementation-level scrutiny

The Aveloxis metric guide is useful precisely because it describes the calculations rather than presenting only dashboard names. One documented “drive-by versus repeat” metric uses a lifetime contribution threshold, with a default threshold of four contributions, and groups contributors by the month of their first contribution. [AV-MET]

That is a legitimate measure of eventual repeat participation in the collected data. It is not equivalent to sustained maintenance duration or retention after a fixed interval. Six events in one day can cross the threshold. An old cohort's classification can also change when future activity arrives. Those are not necessarily defects in the intended visualization; they are reasons not to map it directly onto a repo-health field named `persistent_maintainers_12m`.

An adapter should import the underlying event counts and cohort definitions where available. If it imports the derived metric, it should preserve the upstream definition and threshold. A local persistent-maintenance metric should be calculated separately using distinct active periods, role evidence, and an explicitly bounded historical window.

### 6.10 A mathematical caveat about bucketed burstiness

The metric guide also describes a burstiness expression of the form:

\[
B = \frac{\sigma-\mu}{\sigma+\mu}
\]

applied to bucketed activity counts, alongside an interpretation involving random or Poisson-like activity. That interpretation requires care. The formula has different behavior when applied to event counts than when applied to inter-arrival times. [AV-MET]

For Poisson **count** observations with population mean \(\lambda\) and population standard deviation \(\sqrt{\lambda}\), substitution gives:

\[
B = \frac{\sqrt{\lambda}-\lambda}{\sqrt{\lambda}+\lambda}.
\]

This equals zero when \(\lambda=1\), not for every Poisson count process. At \(\lambda=4\), it is \(-1/3\); at \(\lambda=16\), it is \(-0.6\). These are algebraic examples, not empirical findings about repositories. They show why repo-health should not inherit a qualitative label without checking the measurement domain.

A robust implementation can retain a specifically named count-variation statistic and, separately, define an inter-arrival burstiness statistic with its own population and assumptions. The meaningful improvement is not to ban the formula, but to stop one label from covering two different estimands.

### 6.11 Libyear and unresolved requirements

The analysis documentation describes dependency freshness using release-date differences, often called libyear-style measurement. That can be useful for showing how far a selected dependency version lags a relevant upstream version. It is not a vulnerability measure, and a supported older branch may be intentionally appropriate. [AV-ANALYSIS]

The same documentation discusses simplifying version strings for registry lookup. repo-health must preserve the distinction between a version constraint and a selected installed version. Removing operators from a constraint does not perform dependency resolution. For example, a lower bound in a range is not evidence that the lower-bound version is installed.

The recommended contract is strict: freshness from exact versions may be reported as an observation-derived metric; freshness from unresolved requirements must use a different, explicitly bounded or unknown representation. A metric that cannot establish the selected version should not fabricate precision by turning a range into a single version string.

### 6.12 What to adopt, adapt, and avoid copying wholesale

| Aveloxis component or pattern | repo-health disposition | Reason |
|---|---|---|
| Atomic due-job claim | Adapt early | Fits a compact initial PostgreSQL deployment |
| Successful collection-start cursor | Adopt as a default invariant, then specialize by source | Reduces gaps caused by collection overlap |
| Staged source objects followed by normalization | Adopt conceptually | Enables replay and separation of concerns |
| Contributor-breadth collection | Adapt behind a capability-aware interface | Valuable cross-project discovery, but bounded and event-type dependent |
| Transactional history replacement | Adopt with explicit attempt/success clocks | Prevents failed scans from erasing valid prior evidence |
| Synchronized metric catalog | Adopt | Reduces documentation/API/query drift |
| Lifetime repeat-participation metric | Import with its exact definition | Useful, but not a substitute for tenure or retention |
| Version-string simplification | Do not use as a resolver | Can erase the difference between requirements and selected versions |
| Entire deployment architecture | Optional, not mandatory | repo-health should own its canonical model and avoid redundant collectors |

### 6.13 Adoption experiment

A useful first experiment is a bounded adapter for one repository and one event family. Retain the fetched objects, normalize them into repo-health observations, and compare the resulting counts with the source system using the same window and identity treatment. Then inject interrupted collection, repeated pages, a database write failure, and an empty successful snapshot.

The experiment succeeds when the resulting evidence can be replayed and explained, not when the interface merely displays the same headline number. This is the appropriate way to turn Aveloxis's substantial overlap into saved engineering effort without importing hidden assumptions.

<a id="7-collectoss-relational-community-evidence-and-cross-project-participation"></a>

## 7. CollectOSS: relational community evidence and cross-project participation

### 7.1 Why it is a separate case study

CollectOSS should not be treated as another name for Aveloxis. Although the reviewed documentation places both in an Augur-related lineage, they are separate repositories with different implementations and deployment structures. CollectOSS presents a relational collection and analysis framework, and its inspected deployment configuration includes PostgreSQL, Redis, RabbitMQ, key management, application services, and optional monitoring. [CO-README] [CO-DEPLOY]

For repo-health, the main value is its accumulated representation of community activity and the concrete SQL and worker patterns that expose it. The existence of a broad relational schema is useful even when repo-health does not adopt that schema unchanged. It provides a reference for asking whether a supposedly simple contributor statistic actually requires comments, reviews, issue relationships, identity resolution, and source-specific identifiers.

### 7.2 A metric registration pattern

The inspected contributor metric module uses registered metric functions, SQLAlchemy queries, and tabular processing. This arrangement makes individual metric implementations discoverable and keeps their query logic close to the API-facing function. [CO-MET]

The reusable idea is a metric implementation registry. A registry can associate a name with a query, parameter validation, output schema, and documentation. repo-health should extend that association to include metric version, event grain, identity snapshot, coverage requirements, and a conformance fixture set. The point is to make a metric an explicit unit of software rather than an anonymous SQL fragment buried in a dashboard.

A registry is not sufficient by itself. The inspected module illustrates why descriptions and queries must be checked together: a function's prose can describe a time-oriented concept while the visible query returns an actor aggregate. The adapter must use the actual returned schema, not infer it from a friendly label. [CO-MET]

### 7.3 The event-grain problem

Relational repository data often contains several rows associated with one human action. A commit can touch many files. A review can contain several comments. An issue can have multiple labels and participants. A contributor can have several identities. Joining these tables naively can multiply rows before aggregation.

Consequently, every repo-health event metric needs an explicit grain. Examples include one source-native commit, one review submission, one review comment, one release publication, or one contributor-period membership. These grains are not interchangeable. Counting rows after a join is safe only when the join cardinality is understood and tested.

A useful implementation rule is to construct a canonical event relation first, deduplicated by the appropriate source and event key, and aggregate second. Identity resolution should change the grouping key without changing the number of underlying events. Optional dimensions such as labels or affiliations should not multiply contribution counts unless that multiplication is an explicitly defined allocation model.

### 7.4 A static query concern worth turning into a fixture

The inspected contributor query contains a join condition in which a commit-reference field is compared with itself rather than visibly joined to the corresponding commit field. Such a condition deserves a targeted regression test because a self-equality condition does not, by itself, constrain the relationship between two tables. [CO-MET]

This paper does **not** claim to have reproduced a deployed CollectOSS defect. Other predicates, data constraints, or uninspected execution context can affect the complete query. The observation is a static concern in the reviewed excerpt and a reason to verify cardinality before reusing the query.

The companion example uses a deliberately tiny SQLite dataset with three commits and two references. A self-equality condition admits six combinations, whereas a proper commit-to-reference join admits two. The example establishes the SQL distinction, not the behavior of an operational CollectOSS installation. Its value for repo-health is a general acceptance criterion: contributor metrics must have fixtures that detect multiplication caused by joins, aliases, labels, and identity mappings.

### 7.5 Contributor breadth is already implemented as a collection concept

The contributor-breadth worker scans platform users, requests their public GitHub events, and records activity in repositories that may not already be tracked by the local instance. The inspected code stores contributor identity, repository name and ID, event category, source event ID, event time, and tool/source provenance. It uses a newest-event cutoff to limit repeated acquisition and bulk insertion keyed around source events and tool version. [CO-BREADTH]

This is particularly relevant to the proposed maintainer-history graph. It demonstrates a concrete path from a known contributor to additional repository relationships. repo-health can reuse the pattern to discover activity across projects without requiring a manually maintained list of every project a person has touched.

The worker also shows why platform-specific support must be represented at the capability level. The inspected implementation is GitHub-oriented; a comment that another platform is coming is not evidence that the corresponding code path works. The adapter should state what was actually collected from which source, under which identity model and time bounds. [CO-BREADTH]

### 7.6 Provenance in the worker output

The breadth worker records tool source, tool version, and data source alongside activity. Those fields are valuable because they separate the origin of an observation from the business interpretation later assigned to it. [CO-BREADTH]

repo-health should add several dimensions. The repository identity should be qualified by host instance, not merely a forge brand or repository name. The event's account should remain distinct from any inferred person. The collector's requested and observed time intervals should be stored separately. A source-native event ID should identify the logical event, while collector or transformation versions should identify representations of that event.

The last distinction matters for deduplication. If tool version is included in the natural key of an analytical table, a software upgrade can create a new representation of an old event. That can be entirely appropriate for provenance, but a contributor count must not then count both representations as two actions. The canonical event identity and the transformation identity need separate roles.

### 7.7 Account-to-repository edges are not maintainership assertions

The breadth output includes an event category, which is exactly the information repo-health should retain. An account opening an issue in a project, commenting on a pull request, and publishing a release are not equivalent relationships. A general “contributes to” edge can be a useful discovery abstraction, but it should not replace the original category.

For maintainer analysis, repo-health should derive stronger role assertions only from suitable evidence: declared maintainership, observed release publication, review authority where exposed, documented responsibility, or permission information that the source legitimately makes available. Even then, distinguish an observed exercise of a role from a continuously held permission.

A contributor who published one release several years ago is not necessarily a current release maintainer. Conversely, a documented maintainer may be performing work that the selected public feeds do not capture. The graph should express these limits rather than forcing every person into an inferred current role.

### 7.8 Incremental collection and cutoff assumptions

The inspected worker stops when it encounters events older than the newest stored event for the contributor. That is a useful efficiency pattern, but it relies on ordering and completeness properties of the source feed. [CO-BREADTH]

repo-health should test each provider's actual pagination contract and preserve an overlap interval where appropriate. It should also support periodic reconciliation because a newest-event cursor cannot recover every kind of delayed or missing record. Sources that only expose a recent window cannot establish lifetime inactivity; they can establish only the absence of observed activity in a known interval.

The distinction between a repository disappearing and an account feed returning no events is also important. A not-found response can reflect renamed accounts, access changes, provider errors, or genuinely unavailable content. It should not automatically mark the person inactive or the project abandoned.

### 7.9 Deployment complexity as a reuse decision

The provided Compose configuration makes operational dependencies visible. That visibility is useful: adopting the full system means operating more than a Python package. PostgreSQL, queueing, caching, key management, and worker behavior must all be understood. [CO-DEPLOY]

repo-health should choose between three modes rather than drift into a partial, unsupported deployment. In **data-import mode**, it consumes an existing CollectOSS instance's exports or supported API responses. In **sidecar mode**, it operates a pinned CollectOSS deployment for selected collection duties. In **reference mode**, it implements compatible event semantics or selected patterns in its own stack without claiming to be a CollectOSS deployment.

The preferred mode depends on whether the user already operates the system, whether the desired data are available through stable interfaces, and whether the cost of maintaining an adapter is lower than maintaining a new collector. The paper recommends data import or a carefully bounded sidecar before adopting the whole stack as repo-health's mandatory foundation.

### 7.10 A practical schema crosswalk

| CollectOSS-oriented observation | Proposed repo-health entity or relation | Required additional qualification |
|---|---|---|
| Platform contributor record | `AccountIdentity` | Host instance, native account ID, collection visibility |
| Resolved contributor association | `IdentityAssertion` or `PersonProjection` | Resolution method, evidence, effective interval, correction history |
| Repository activity event | `ActivityEvent` | Native event identity, category, event time, observed time |
| Contributor repository activity | `Account → Repository` observation | Event family and acquisition interval, not automatic maintainership |
| Tool/source/version fields | `EvidenceTransform` | Input evidence IDs, tool build or revision, configuration digest |
| SQL metric output | `MetricObservation` | Population, formula version, event grain, denominator, completeness |
| Collection cutoff | `CollectionCheckpoint` | Cursor semantics, overlap rule, last successful coverage |

This is a proposed translation, not a claim that CollectOSS uses these exact entity names. It preserves the useful source information while fitting repo-health's temporal model.

### 7.11 Where CollectOSS should influence the metric inventory

The strongest influence is in participation and collaboration rather than only commit counts. The inspected module and worker reinforce the need to model heterogeneous events and cross-project activity. That supports metrics for review participation, distinct projects with observed activity, first and last observed contributions, and actor-specific contribution distributions. [CO-MET] [CO-BREADTH]

However, measures such as “regressions introduced by a person,” “security fixes authored,” or “successful projects after departure” need stronger attribution evidence than a general community event database provides. repo-health should not fill those metrics simply because it has rich contributor tables. A large catalog should include explicit feasibility classes: directly observable, derivable with defined assumptions, dependent on additional tooling, or experimental.

### 7.12 Reuse decision and acceptance gate

CollectOSS is a strong source of community event semantics and a useful acquisition option. Its contributor breadth is directly relevant to the proposed cross-project graph. Its metric module is also a valuable reminder that an executable query should be inspected as carefully as its prose definition.

The initial acceptance gate should require a small fixture dataset covering multiple identities, reviews with several comments, commits with several files, and contributor events in an untracked repository. The import must preserve event identity and source provenance; repeated import must not change counts; identity merging must change actor groupings without changing event totals; and every query must return the expected cardinality.

Passing those tests would justify a bounded integration. It would not establish that every metric in the upstream application can be imported under repo-health's local metric names.

<a id="8-grimoirelab-the-strongest-reusable-collection-and-enrichment-toolkit"></a>

## 8. GrimoireLab: the strongest reusable collection-and-enrichment toolkit

### 8.1 A toolkit, not a single repository

GrimoireLab's top-level repository is an integration point for a family of components. Its submodule inventory identifies Perceval, SortingHat, GrimoireELK, Cereslib, Graal, SirMordred, and additional tools. The architecture separates retrieval, enrichment, analysis, and presentation rather than presenting one inseparable algorithm. [GL-README] [GL-MODULES]

This modularity is highly relevant to repo-health. The project can learn from or use the component responsible for a particular capability without adopting every visualization or deployment choice. It also means that a top-level repository review is insufficient: identity semantics reside in SortingHat, collection behavior in Perceval, and particular studies in enrichment code.

The current review found several ingredients previously discussed as possible repo-health innovations already present here. The productive question is not whether to recreate them, but how to fit their evidence and behavior into repo-health's stricter temporal and dependency-aware model.

### 8.2 Perceval's backend contract

Perceval's inspected backend module provides a common abstraction around source-specific collection. The backend knows its origin, category, client, metadata extraction, and collection capabilities. It provides source-independent wrapping around the source-specific items. [GL-PERCEVAL]

This is close to the connector model repo-health needs. A connector should not force the analytics engine to understand every host API. It should provide a standard evidence envelope while preserving the raw payload and source-specific identifiers required for later interpretation.

The important architectural lesson is that normalization should be layered. A generic envelope can consistently report where and when an item was observed, which collector produced it, and what category it belongs to. A source-specific normalizer can then interpret a GitLab merge request or an emailed patch without pretending their workflows are identical in every detail.

### 8.3 Provenance in the collection envelope

The inspected code records backend identity and version, Perceval version, acquisition time, origin, a generated item identity, source update time, category, search fields, and the underlying data. It also exposes collection summaries and supported behavior. [GL-PERCEVAL]

This is one of the best direct models for repo-health's observation envelope. It shows that provenance is not merely a citation attached to a final chart; it can be emitted as part of every collected item. That makes later transformations easier to audit and allows the collector to remain useful independently of a particular dashboard.

repo-health should extend the envelope with a stable evidence digest, requested scope, observed scope, pagination or truncation status, access mode, retention policy, and source-rights information. It should also distinguish the time the source says an event occurred, the time the source says the object changed, and the time the collector observed it. Those times often answer different questions.

### 8.4 Stable item identity and changing origins

A generated identity based on origin and source-native item identity is useful for idempotent collection. However, origin strings can change when a repository moves, a host changes its URL, or a project adopts a canonical mirror. If the origin is part of an event key, a migration can make the same logical event appear new. [GL-PERCEVAL]

repo-health should preserve the original source key while adding a separately managed canonical relationship. A source event identity should never be rewritten silently just to match a new URL. Instead, store aliases or equivalence assertions with evidence and time. That allows both source-faithful replay and a deduplicated project view.

This is particularly important for the user's requirement to support many hosting sites. A Git commit hash can sometimes help identify shared history, but it does not by itself establish that two repositories are one project or that their issue trackers should be merged. Identity equivalence is a relation to justify, not a convenience operation to perform automatically on similar names.

### 8.5 Archives and replay

Perceval's backend code includes archival behavior and mechanisms for replaying collected material. That is a strong foundation for reproducible measurement, because source APIs can change and old objects may disappear. [GL-PERCEVAL]

The distinction between a raw archive and a metric database is essential. A metric database preserves what a particular algorithm calculated. An archive can preserve the input from which a corrected algorithm could calculate something else. repo-health needs both, subject to retention and privacy constraints.

Replay also needs an explicit transformation identity. A replay using a new collector or parser version is not necessarily an exact reproduction of an old result. It is a new interpretation of retained evidence. The old result should remain associated with its original tool and configuration, while the new result can supersede it in a current view.

### 8.6 The archival privacy tradeoff is visible in the code

The inspected Perceval module rejects combining certain archival behavior with filtering of classified fields, because the raw archive would retain information before filtering. [GL-PERCEVAL]

This is a valuable design warning. It is not enough for a public API to hide an email address if the same address remains in an unrestricted raw archive. repo-health must define the boundary between collection, redaction, retention, and publication before promising privacy protections.

The proposed approach is to separate evidence classes. Public, nonpersonal technical artifacts may be retained with long-lived digests and replay support. Personal identifiers and user-generated text may require stricter access, shorter retention, suppression mechanisms, or redaction before persistence. When redaction limits reproducibility, the system should disclose that limitation rather than secretly retaining everything.

### 8.7 SortingHat's identity model

SortingHat maintains a distinction between an individual and the identities associated with that individual. The inspected models include accounts or identity attributes, profiles, groups and organizations, time-bounded enrollments, merge recommendations, and audit records. [GL-SH-README] [GL-SH-MODEL]

This is far more useful than attempting to deduplicate contributors using only their displayed names. The same person can use several addresses or accounts, and the same name can belong to different people. A canonical individual view should therefore be a managed projection over source identities rather than a destructive replacement for them.

repo-health should adopt that conceptual separation. Source identities are observations from a provider or artifact. A person-level mapping is an assertion supported by evidence. A confidence score, when used, must be tied to a calibrated method or an explicitly nonprobabilistic ranking; it should not be invented as a decorative decimal.

### 8.8 Reversible merging and audit history

SortingHat already contains merge-related structures, an unmerge API entry point, and transaction and operation records that describe changes. Reversible identity management and auditing are therefore not novel repo-health ideas. [GL-SH-MODEL] [GL-SH-SPLIT]

The extension repo-health needs is analytical dependency tracking. When two identities are merged or split, contributor counts, concentration, tenure, affiliation summaries, and cross-project activity can all change. The system needs to know which metric observations depend on the affected mapping and which historical windows require recomputation.

Two views should remain possible. A **current corrected history** uses the best currently accepted identity mapping to reinterpret older events. An **as-known-at-the-time history** shows what a previous analysis knew when it was produced. Neither should silently overwrite the other. This requires versioned identity assertions and a clear distinction between event time and knowledge time.

### 8.9 Recommendations before application

The inspected identity model includes merge recommendations with an applied state, rather than requiring every potential match to become an immediate merge. It also includes safeguards against a self-pair and a canonical ordering of candidate pairs. [GL-SH-MODEL]

This is a useful pattern for high-impact identity decisions. Candidate generation can be automated without making the final merge irreversible or opaque. repo-health should expose the evidence for the candidate, the rule or model that produced it, and the effect on affected project metrics before applying it in sensitive cases.

The same pattern can apply to repository equivalence, project-family membership, package-to-source mapping, and organization affiliation. In all four cases, a mistaken merge can contaminate a large portion of the graph. A recommendation queue with explicit decisions is preferable to silently assigning every plausible match a common identity.

### 8.10 Affiliation intervals and unknown dates

SortingHat's enrollment model includes start and end times. That is a useful foundation for organizational concentration because a contributor's affiliation can change. Historical contributions should not automatically be assigned to the person's current employer. [GL-SH-MODEL]

The inspected model also uses broad sentinel dates as defaults for open intervals. repo-health should translate those defaults carefully. A sentinel used to mean “unknown beginning” is not evidence that an affiliation began in that calendar year. The canonical schema should support an unbounded or unknown endpoint directly, with a distinction between an open interval and a precisely observed date.

Affiliation itself must also be qualified. A public profile, an email domain, an explicit employer statement, and an organization membership are different types of evidence. None alone proves that the organization controls the project, funds the work, or has access to release credentials.

### 8.11 Do not import every profile field

The inspected SortingHat and Cereslib models contain demographic-related fields or enrichment functionality. Those fields are not needed for repo-health's maintenance-continuity mission. [GL-SH-MODEL] [GL-CERES]

The recommended integration deliberately excludes inferred gender and other unnecessary personal classifications. The existence of a field in an upstream schema does not establish a legitimate purpose for importing it. repo-health should collect only the information required to answer its software-maintenance questions, and it should provide a correction and suppression path for person-level data.

This is not in conflict with an extensive metric catalog. “As many metrics as possible” should mean many useful, well-defined technical and organizational observations, not unrestricted profiling of contributors.

### 8.12 GrimoireELK's enrichment studies

The inspected onion study groups activity by quarter, project, organization, and contributor, passes tabular data into an enrichment calculation, and writes results to an index. The code makes the lack of incremental support explicit in the reviewed path. [GL-ONION]

This is useful in two ways. First, it provides a concrete example of a reusable analytical projection rather than one ad hoc chart query. Second, it exposes the computational consequences of an implementation choice. Recomputing historical quarters can be reasonable for a bounded dataset, but it should not be mistaken for a low-cost incremental update over a global graph.

repo-health should adopt the concept of named, versioned studies with declared input populations and output schemas. Each study should state whether it can update incrementally, which corrections invalidate it, and what its cost depends on. A dashboard should not trigger an unbounded historical study merely because a user changed a filter.

### 8.13 Cereslib's composable enrichments

Cereslib contains small enrichment transformations for tabular data, including time differences, path decomposition, identity joins, and contribution-role classification. The inspected code demonstrates a compositional style: derive a field, retain the underlying data, and allow further enrichment. [GL-CERES]

This is a useful design reference for repo-health's metric engine. Small transformations can be tested independently and combined into larger analyses. However, the canonical observation layer should remain typed and provenance-aware; it should not become a dataframe in which column names and sentinel strings are the only schema.

Each transformation should declare whether it preserves row count, changes the event grain, or expands one input into multiple analytical records. That declaration matters because a technically valid enrichment can change the meaning of a later count.

### 8.14 Author and committer are different roles

One inspected Cereslib transformation can duplicate a commit-related row when author and committer differ, under a workflow-specific interpretation of paired participation. The surrounding documentation acknowledges that this relationship can mean different things in different development processes. [GL-CERES]

repo-health should preserve author and committer as distinct attributed roles on one commit event. A metric may intentionally count participation roles, but it should not accidentally turn one commit into two commits. If a workflow-specific model allocates credit to both people, the metric definition must say that it measures attributed participation, not distinct source changes.

This principle generalizes to co-authored commits, bot-mediated merges, delegated releases, and imported patch histories. Event identity, attribution, and role participation need separate entities or carefully specified relations.

### 8.15 Onion classification and threshold crossing

The inspected Cereslib `Onion` implementation sorts contribution counts, calculates each contributor's ending cumulative percentage, and assigns labels using intervals ending at 80, 95, and 100 percent. [GL-CERES]

That implementation is instructive because an ending-percentile interval is not the same operation as selecting the smallest group responsible for a target share. For a single contributor responsible for all activity, the ending cumulative percentage is 100. Under the inspected interval rule, that position falls in the “casual” interval. For a dominant contributor crossing 80 percent immediately, the result can likewise differ from the intuitive meaning of a core group.

This is an analytical consequence of the inspected rule, not a claim that every GrimoireLab dashboard misclassifies every project or that an upstream production incident has been reproduced. The supplementary example models the interval rule on a one-contributor fixture and contrasts it with a threshold-crossing concentration count.

repo-health should distinguish two legitimate operations: locating contributors in the tail of a cumulative distribution, and identifying a minimal set that covers a target share. If the intended concept is a core group covering 80 percent, the crossing contributor must be handled explicitly. Tie behavior and a single dominant contributor should be part of the specification, not accidental consequences of a plotting function.

### 8.16 Ties, empty populations, and stable identity ordering

Contribution-role algorithms need defined behavior for equal counts, zero totals, missing identities, and changing identity mappings. If equal-count contributors straddle a cutoff, arbitrary row order can assign different roles to otherwise identical observations. A corrected identity merge can also move the threshold dramatically.

A proposed repo-health implementation should report concentration statistics separately from any discrete role labels. For role labels, it should choose and document a tie policy: include the full tied group, allocate by a stable rule, or report an ambiguous boundary. It should never imply that a cutoff inferred from contribution counts grants or proves maintainership authority.

These are small mathematical choices with large interpretive consequences. The reviewed source provides a concrete reason to put them in the test suite before using the resulting labels in dependency policy.

### 8.17 Graal's historical source-analysis hooks

Graal's documentation describes a workflow that uses Git history, selects commits, checks out a working tree, invokes source-analysis tools, and attaches results to the corresponding document. It offers filter, analysis, and post-processing hooks and describes integrations for complexity, language, licensing, code quality, and potential vulnerability analysis. [GL-GRAAL]

The strongest reusable idea is not any particular scanner. It is the association between an immutable source snapshot and a tool-specific observation. That allows repo-health to ask how engineering measurements changed between releases without pretending that today's source tree describes every historical version.

A practical adaptation should analyze a bounded set of release or sampled snapshots rather than every commit by default. It should cache by source tree, tool version, configuration, and relevant environment. The output should record scope and exclusions, such as generated or vendored files, because those choices materially affect code counts and complexity distributions.

The reviewed Graal README also contains dated installation examples. The architectural pattern remains useful, but those commands should not be copied as a current deployment recipe without revalidation. Documentation age and implementation suitability are separate observations. [GL-GRAAL]

### 8.18 Running analyzers safely

Historical checkout analysis creates a powerful boundary: repo-health is handling untrusted source content and invoking tools over it. Even a nominally static analyzer can read configuration, load plugins, resolve paths, or invoke external programs. The proposed integration should therefore disable repository-controlled execution paths unless a dedicated sandbox explicitly permits them.

The safe default is a read-only source mount, no user secrets, tightly bounded CPU and memory, restricted or absent network access, controlled tool configuration, and a pinned tool image. Archive extraction and Git operations require similar care. A tool's usefulness for metrics does not make it safe to run with the observatory's database credentials or cloud permissions.

These are proposed safeguards for repo-health, not a claim that the current Graal deployment has been audited for every such condition.

### 8.19 SirMordred's configuration and project grouping

SirMordred's documentation separates operational configuration in `setup.cfg` from source-to-project grouping in `projects.json`. It supports distinct phases for collection, enrichment, identities, and presentation, and it can group multiple source systems under nested projects. [GL-MORDRED]

This is especially relevant to repo-health's requirement that a project is not synonymous with one repository. A project can include a Git repository, a mailing list, a review system, and an issue tracker. The same source can also contribute to several analytical groupings through filtering.

repo-health should adopt the distinction between physical sources and analytical membership. It should not, however, assume that summing nested groups gives an unduplicated portfolio total. When sources or events belong to overlapping groups, aggregate metrics need union semantics or an explicit allocation rule. Grouping is not identity equivalence.

### 8.20 Retaining history after a source disappears

SirMordred's documented no-collection filtering can preserve the display of previously enriched information from sources that no longer exist upstream. [GL-MORDRED]

This is a useful model for repo-health. A project migration, deletion, or access change should not automatically erase the fact that an observation was previously made. At the same time, retained data must not be presented as current. The graph should mark the source's latest availability state and preserve the time interval to which the retained evidence applies.

Retention also remains subject to privacy and source-rights constraints. Historical usefulness does not justify ignoring a valid suppression requirement. The architecture needs a way to preserve the fact that evidence was removed or restricted without exposing the removed content.

### 8.21 Deployment and license implications

The inspected Perceval, SortingHat, GrimoireELK, and Cereslib files contain GPL-3.0-or-later notices. That is relevant when deciding whether to copy code, modify and distribute a component, link libraries, or operate a service around them. The exact implications depend on the integration and the relevant license texts; this review is not a legal clearance. [GL-PERCEVAL] [GL-SH-MODEL] [GL-ONION] [GL-CERES]

A sidecar or export interface can be architecturally useful because it creates a clear contract and avoids unnecessary language coupling. It should not be described as an automatic exemption from license obligations. License review and technical interface design are related but distinct tasks.

The top-level toolkit and individual component documentation can also reference different generations of search and dashboard infrastructure. repo-health should pin a tested component set rather than combine current branch heads and assume compatibility. [GL-README] [GL-MORDRED]

### 8.22 Recommended component dispositions

| Component | Best use in repo-health | What remains locally owned |
|---|---|---|
| Perceval | Long-tail source collection and standard evidence-envelope reference | Canonical identity, evidence retention, coverage contracts |
| SortingHat | Identity administration concepts or an optional identity service | Bitemporal assertions, metric invalidation, policy-specific privacy limits |
| GrimoireELK | Reference studies and enrichment patterns | Canonical metric definitions and graph-aware projections |
| Cereslib | Small analytical transformation references and boundary fixtures | Typed contracts, event-grain control, corrected local classifications |
| Graal | Optional historical source-analysis worker pattern | Sandbox policy, snapshot selection, tool-version provenance |
| SirMordred | Source/project configuration and phase separation | repo-health scheduling, canonical graph membership and evidence state |
| Other listed toolkit components | Future targeted evaluation | No capability claim until their relevant code or interfaces are examined |

### 8.23 Adoption experiment

The best initial GrimoireLab experiment is to collect one non-GitHub source through Perceval, retain its envelope, normalize one event category, and calculate a small metric alongside a native Git history view. Then merge and split two synthetic identities through the selected identity workflow and verify that event totals remain constant while contributor groupings change.

A second experiment can run a pinned analyzer on two release snapshots through a Graal-like isolated worker. The acceptance criteria are stable source identity, reproducible transformation metadata, and explicit coverage—not an impressive dashboard. These experiments target the places where GrimoireLab can save substantial work while leaving repo-health's distinguishing semantics under its own control.

<a id="9-ecosyste-ms-shared-discovery-infrastructure-and-the-package-repository-bridge"></a>

## 9. ecosyste.ms: shared discovery infrastructure and the package–repository bridge

### 9.1 Why this family can change the project's economics

ecosyste.ms is especially valuable because repo-health's desired universe is much larger than a manually curated list of GitHub repositories. The official services expose repository and package information across multiple hosts and registries, while the inspected code models hosts, repositories, manifests, package versions, and dependency relationships. [EC-REPOS-WEB] [EC-PACKAGES-WEB] [EC-HOST] [EC-REPO] [EC-DEP]

The practical opportunity is to use this infrastructure for discovery and enrichment rather than immediately recreate its entire collection footprint. repo-health can start from known package and repository identities, then perform deeper analysis only where its distinctive questions require it.

That recommendation is not a claim that every indexed repository has complete history, a verified open-source license, or a fully resolved dependency graph. Discovery coverage and analytical completeness must remain separate. A large index is useful precisely because it can help locate candidates; it does not remove the need to validate the evidence used for a particular decision.

### 9.2 A service constellation rather than one import

The inspected services divide responsibilities. Repos models source hosts and repository metadata. Packages models package and version information and exposes dependent-package queries. Parser wraps dependency-manifest analysis. Bibliothecary is the parsing library described by Parser. Commits and Issues describe metadata services for their respective event families, while Dashboards provides a presentation application. [EC-REPO] [EC-PKG-API] [EC-PARSER-DOC] [EC-BIB] [EC-COMMITS] [EC-ISSUES] [EC-DASH]

This division suggests several independent adapters rather than a single `ecosystems=true` flag. Each adapter needs its own capability declaration, response schema, freshness semantics, rate behavior, evidence provenance, and failure state. A package lookup succeeding does not mean that commit history or reverse dependents are available for the same project.

The shallowly reviewed service READMEs establish their intended scope, not the completeness or correctness of every endpoint. Implementation work should inspect and contract-test the specific endpoint selected for each metric.

### 9.3 First-class host identity

The inspected host model stores host name, URL, and kind separately and delegates source-specific behavior through a host implementation. Repository synchronization uses source identity where available and reconciles changed names. [EC-HOST]

This is a strong foundation for the user's “all different repositories and sites” requirement. A self-hosted GitLab instance is not the same source namespace as GitLab.com. Two unrelated Gitea instances can contain identical owner/repository paths. A canonical repository identity must therefore include the host instance and a source-native stable identifier when available.

repo-health should preserve three related but distinct values: a stable local repository entity ID; one or more source-native repository keys qualified by host; and historical locators such as clone URLs and web paths. A URL is an address, not necessarily a permanent identity.

### 9.4 Repository renames, moves, and alias performance

The host code records prior names and attempts to reconcile repositories using source identifiers. The inspected file also contains a note that a previous-name lookup path had been disabled because of expensive queries at large scale. [EC-HOST]

The useful lesson is not that alias support is optional. It is that aliases need a deliberately indexed representation. repo-health should not rely on searching a large unstructured list attached to every repository each time a package advertises an old source URL.

A proposed alias table should index `(host_instance, normalized_locator, valid_interval)` and point to the canonical entity through an evidence-backed assertion. It should support conflicting or uncertain matches rather than force a unique assignment where the source history is ambiguous. A migration can then preserve old package references without requiring every consumer to update immediately.

### 9.5 Numerical counters can be estimates

The inspected host model can estimate large repository counts from PostgreSQL catalog statistics. It also includes logic that can suppress small downward changes in the displayed count. These are operational choices intended to avoid expensive exact counting and unstable counter behavior. [EC-HOST]

For repo-health, the conclusion is precise: a numeric result needs a measurement method. `repository_count=...` without a method, scope, or freshness field is not enough. An estimate from database statistics, an exact count of retained rows, and a provider-reported total are different observations.

This also cautions against reproducing huge headline ecosystem counts as if they were a census of open-source projects. Repositories, manifests, package versions, dependency records, and independently maintained projects have different units. Mirrors, forks, generated repositories, historical versions, and incomplete license classification can further change the interpretation.

A good user interface should identify the unit before displaying the magnitude. “Observed dependency records” is a defensible label when supported by the source. “Applications protected” would require an entirely different chain of evidence.

### 9.6 Selective enrichment and fair coverage

The repository model schedules different kinds of work under different filters and queue limits. Some enrichment paths focus on non-fork repositories or records with particular state and freshness conditions. It also uses cursored sweeps and batch enqueueing to bound background work. [EC-REPO]

These are useful operational patterns, but they imply that one indexed record can be much richer than another. repo-health must not use the absence of enrichment as evidence that a project lacks tests, dependencies, security practices, or contributors.

A canonical coverage record should state what was requested, what was returned, which filters were applied, and whether the source itself selected the population. When repo-health deliberately deep-scans only a subset, the selection policy should be observable too. Otherwise its own collection priorities can create a self-reinforcing picture in which popular projects appear healthier simply because they receive more analysis.

### 9.7 Cursored sweeps and queue backpressure

The inspected code uses a bounded cursor and an end-of-sweep marker for inactive-repository synchronization, and it checks queue sizes before scheduling some expensive work. [EC-REPO]

This is a practical model for avoiding an uncontrolled global rescan. repo-health should adopt bounded sweeps, per-source budgets, and explicit backpressure before its dataset becomes large. A scan should be resumable, and restarting a worker should not reset progress to the beginning of a global table.

The extension needed for repo-health is fairness and observability. A scheduler should report which populations remain unscanned, the age distribution of evidence, and whether a source is being deferred because of budget, errors, or low priority. A small project should not acquire a negative health label because the observatory itself has not reached it in a sweep.

### 9.8 Package-to-repository association is the bridge to downstream health

The Packages API supports lookup through package identifiers and repository URLs. The inspected controller also handles bulk lookup and ecosystem qualification. [EC-PKG-API]

This is a crucial bridge. A package dependency graph becomes a project-health graph only after package versions are associated with source projects. That association can be uncertain: package metadata may name a homepage, a monorepo, a fork, an issue tracker, or an obsolete repository. repo-health should therefore retain the source of the association and the relation type.

The bridge should not be a single mutable `repository_url` string on a package row. It should be a set of assertions connecting package or artifact versions to repositories or project components, with evidence, time, and confidence class. Stronger evidence such as verified provenance can coexist with weaker metadata links without pretending they are equivalent.

### 9.9 Package and version identity

The inspected dependency model associates a declaration with a source package version and allows the target package association to remain unresolved. It retains the package name, ecosystem, requirement, and dependency kind. [EC-DEP]

This is a particularly good pattern: unresolved relationships still contain useful evidence. A parser may know that a manifest declares a dependency before the system can confidently associate the name with a registry entity. Discarding such edges would hide coverage gaps and bias counts toward well-indexed ecosystems.

repo-health should keep the raw declaration and a separate resolution assertion. The namespace must include the relevant registry or source, not just a normalized package name. The inspected resolution logic illustrates why this deserves care: selecting a registry from an ecosystem can be an approximation when multiple registries, mirrors, or package sources are relevant. [EC-DEP]

### 9.10 Latest dependents and historical dependents

The inspected Packages API distinguishes latest-version dependent queries from a historical mode selected explicitly by a parameter. The historical relation is based on package versions that have declared the dependency, whereas the default path uses a latest-dependent interpretation. [EC-PKG-API] [EC-PKG-REL]

This is one of the most directly useful features for repo-health's downstream requirement. It provides a starting point for separating current published adoption from past adoption. The adapter should preserve the query mode in the population definition rather than return both under an undifferentiated `dependents` field.

However, “latest published version depends on this package” still does not mean “all deployments currently use this package.” Applications may remain on older supported releases, use private builds, enable optional features, or resolve different versions. repo-health should label the observation as published-source or package-metadata adoption unless deployment evidence is available.

### 9.11 Cached top-dependent lists and population completeness

The inspected dependent-package endpoint can serve certain requests from a cached list of top dependent package IDs and marks that response with a source header. It also supports filtering and pagination. [EC-PKG-API]

This is useful for an interactive interface, but it is a warning for analytical consumers. A list optimized for prominent dependents may not be a complete sample of all dependents. Sorting or filtering by downloads or stars further changes the population.

repo-health should retain provider response metadata and distinguish a complete enumeration, a bounded top list, a sample, and an incomplete page sequence. Downstream-health distributions computed from a top list should not be presented as distributions over the entire ecosystem. A provider-specific response header can be analytically important, not merely an HTTP implementation detail.

### 9.12 Critical projects with few maintainers

The inspected Packages controller includes an endpoint for critical packages with a sole-maintainer condition and related metadata filters. This already overlaps with repo-health's proposed question of identifying important but fragile infrastructure. [EC-PKG-API]

The appropriate response is to reuse or compare this evidence rather than claim the question is unique. repo-health can extend the analysis with verified role continuity, project-family deduplication, dependency context, and explicit missingness. It should also inspect what the upstream maintainer count means: registry publication accounts, source-project maintainers, and people doing recent maintenance are different populations.

A package registry may list one owner while a source project has many capable maintainers. The reverse can also occur. A sole-owner observation is valuable, but it should not silently become a complete estimate of operational resilience.

### 9.13 Parser as an asynchronous service

The inspected Parser job model supports asynchronous work, temporary working directories, source download hashing, result reuse, status transitions, and a timeout around parsing. It wraps Bibliothecary and normalizes its output into a service response. [EC-PARSER]

This is a useful service boundary for repo-health. Manifest parsing can be delegated to a pinned worker or service without forcing the core application to implement every ecosystem format immediately. The core can accept a structured result and preserve the original manifest, parser identity, and scope.

The service's reusable architecture should be distinguished from its exact execution choices. repo-health needs its own rules for source fetching, archive extraction, resource limits, allowed network destinations, and tool configuration. A parser that accepts arbitrary URLs belongs behind an acquisition security boundary, not in the same trust domain as the canonical database.

### 9.14 Content-hash caching needs transformation identity

The inspected job model can reuse an earlier completed result with the same downloaded SHA-256 digest. That is a useful way to avoid parsing identical source bytes repeatedly. [EC-PARSER]

For repo-health, the cache key should include more than source content. A new parser version can recognize a previously unsupported format, fix an alias rule, or add integrity fields. A configuration change can alter path inclusion or ecosystem interpretation. Reusing a result solely because the input bytes are unchanged can preserve an old error indefinitely.

The proposed key is a tuple containing input digest, parser identity and version, normalization version, configuration digest, and any relevant environment profile. The cached output remains evidence of that transformation, not a timeless truth about the source.

### 9.15 Information loss between Bibliothecary and Parser

The Bibliothecary README documents dependency fields including directness, optionality, local dependency status, original names and requirements, source path, and integrity information. The inspected Parser normalizer emits a narrower set for each dependency: name, requirement, type, and an optional local flag. [EC-BIB] [EC-PARSER]

This is one of the review's most important integration findings. A service built on a rich library does not necessarily expose all the information the library can provide. Choosing the service can therefore be simpler operationally while losing fields that repo-health needs for scope, provenance, or artifact association.

The recommendation is not automatically to bypass the service. It is to define the required interchange contract and test whether the selected service version satisfies it. An upstream enhancement to preserve additional fields may be more maintainable than a private fork. Alternatively, a local library adapter may be appropriate if its license, dependencies, and execution model are acceptable.

A normalizer should publish a loss report for fields it drops or cannot interpret. Silent loss is especially dangerous when a missing boolean is later treated as false.

### 9.16 Manifest kind is not dependency directness

In the inspected repository model, imported dependency directness is inferred in one path from whether the enclosing item is a manifest. [EC-REPO]

That is a coarse classification, not a universal semantic rule. A lockfile can contain both direct and transitive dependencies. A manifest can describe optional or conditional dependencies. A generated resolver export can contain a complete graph whose edges cannot be reconstructed from a single manifest/lockfile label.

repo-health should preserve `document_kind` and `dependency_directness` as separate fields. If the parser cannot establish directness, the value should remain unknown or provider-inferred. This is a small schema choice that prevents later downstream counts from acquiring unjustified precision.

### 9.17 Unsupported input versus a successful empty result

The Parser code returns an empty result for some unsupported MIME-type paths, while other paths can successfully parse a recognized input that genuinely has no dependencies. [EC-PARSER]

These outcomes must not collapse in repo-health. “No dependencies observed because this input was unsupported” is not equivalent to “recognized manifest parsed successfully and contained no dependencies.” The distinction determines whether an older successful snapshot should be cleared, retained as stale, or superseded.

The proposed analysis result should contain recognition status, parsing status, scope completeness, diagnostics, and an observation list. An empty list is a payload, not a sufficient status. This principle also applies to vulnerability scans, code analysis, repository searches, and contributor feeds.

### 9.18 Attempt time versus successful parse time

The repository integration updates a parsing timestamp when a job reaches either a complete or error state in the inspected path. [EC-REPO]

That can be a useful operational marker, but an adapter must not interpret it automatically as the time of the most recent successful dependency snapshot. repo-health should retain the upstream field under its original meaning and derive a separate successful-analysis timestamp only when the status supports it.

The general rule is that source field names are not enough. An `updated_at`, `checked_at`, or `parsed_at` field needs a semantic description. This is why source-specific adapters are still necessary even when every provider returns JSON.

### 9.19 Repository metadata files as observations

The repository model detects files associated with documentation, security, governance, maintainers, funding, and related project information. [EC-REPO]

This is useful, inexpensive evidence. It can support metrics such as the presence of a security contact document or a maintainer file at a particular revision. It cannot, on its own, establish that the process is followed, that the contact is responsive, or that governance is effective.

repo-health should distinguish filename detection, parsed content assertions, independently observed behavior, and human review. A file's presence can trigger a deeper check, but it should not be inflated into a broad quality guarantee. This also avoids rewarding projects for adding boilerplate documents that do not correspond to actual practice.

### 9.20 Commits, Issues, and Dashboards as optional enrichment

The Commits and Issues service READMEs describe APIs for commit metadata and issue or pull-request metadata respectively. Dashboards describes an application for visualizing and managing data from the ecosystem services. [EC-COMMITS] [EC-ISSUES] [EC-DASH]

These are useful integration candidates, but their detailed schemas and coverage were not audited in this review. repo-health should first verify whether they can supply the event identity, timestamps, pagination, and source provenance required by a selected metric. A service-level description is not enough to establish complete lifetime history or equivalent coverage across hosts.

Dashboards is most useful here as a presentation reference. It should not become the canonical evidence store merely because it already joins several service responses for display.

### 9.21 Code licenses, data licenses, and upstream rights

The reviewed Parser, Commits, Issues, and Dashboards documentation distinguishes an Affero-style source-code license from CC BY-SA 4.0 licensing for API data. The repository and package service pages also expose their own licensing information. [EC-PARSER-DOC] [EC-COMMITS] [EC-ISSUES] [EC-DASH] [EC-REPOS-WEB] [EC-PACKAGES-WEB]

repo-health must treat code reuse, API access, redistribution of provider data, and republication of upstream content as separate questions. A permissive implementation language dependency does not determine the license of a dataset. A provider's aggregation license does not automatically make every embedded source document interchangeable.

The implementation should preserve attribution and source-rights metadata and obtain a qualified review of the intended redistribution model. This paper identifies the declarations that were observed; it does not provide a definitive legal interpretation of every derived dataset or service boundary.

### 9.22 Recommended integration order

The highest-value first integrations are repository identity lookup, package-to-repository association, and explicitly scoped dependent-package enumeration. These directly support repo-health's distinctive graph questions without requiring global source cloning.

Manifest parsing should follow once the required fields and statuses are contract-tested. Commit and issue enrichment can be added for selected metrics where it reduces collection work without hiding coverage. Deep code analysis should remain a separate, opt-in stage.

The canonical graph must remain operable when an ecosyste.ms endpoint is unavailable. Cached, attributed evidence can continue to support an as-of view, while native Git and direct registry adapters provide an independent path for important sources. Shared infrastructure is a major advantage, but it should not become an invisible single point of truth.

### 9.23 Adoption experiment

Choose a small, heterogeneous set of packages across two registries and repositories across several host types. For each package, import the provider's source association and latest-dependent query, retain the query parameters and response metadata, and independently verify a sample of manifests. Record unresolved mappings rather than forcing them.

Then compare the provider's parser output with the documented library fields on fixtures containing optional, local, aliased, direct, transitive, and integrity-bearing dependencies. The experiment should quantify field preservation and disagreement, not merely count successfully parsed files.

Finally, simulate a provider outage and a stale cached result. A successful integration continues to show what was previously observed while clearly declining to claim current completeness. That behavior is essential before the data can responsibly influence dependency admission.

<a id="10-deps-dev-resolution-semantics-package-identity-and-provenance"></a>

## 10. deps.dev: resolution semantics, package identity, and provenance

### 10.1 The public repository is not the hosted service

The deps.dev README explicitly describes the public repository as containing API definitions, example applications, and supporting utilities. It is not a publication of the complete hosted data-ingestion and serving system. [DD-README]

This distinction materially affects reuse. repo-health can call the service, generate clients from its interface definitions, use suitable public utilities, and study its examples. It cannot assume that cloning `google/deps.dev` provides a self-hostable equivalent of the entire production service.

The recommended architecture therefore treats the hosted API as an external evidence provider with caching, provenance, freshness, and outage behavior. Public resolver and version utilities are evaluated separately as code dependencies or test references. These are different integration decisions with different maintenance and availability risks.

### 10.2 Stable and experimental interfaces

The documentation distinguishes a stable v3 interface from an experimental v3alpha interface. The reviewed v3 service definition includes package, version, requirement, resolved-dependency, project, project-package mapping, advisory, and content-hash query operations. [DD-README] [DD-PROTO]

repo-health should begin with the stable interface wherever it supplies the necessary evidence. Experimental fields can be useful, but their adapter should be independently versioned and should not silently alter the canonical schema when the provider changes them.

The interface contract should be pinned in the client build, and representative responses should be retained as fixtures. Unknown response fields should generally be preserved or safely ignored rather than causing broad ingestion failure. Known fields whose semantics change require a normalizer version change and, where necessary, reprocessing.

### 10.3 Coverage differs across layers

One of the most important findings is that “deps.dev supports an ecosystem” has several meanings. The inspected v3 interface documents requirement data for seven ecosystems but resolved dependency graphs for a smaller set. The public resolver utility's `System` definitions cover a different subset, while the semver utility documents additional version schemes. [DD-PROTO] [DD-RESOLVE] [DD-SEMVER]

| Layer inspected | Documented or visible coverage in the reviewed material | Consequence |
|---|---|---|
| v3 requirement interface | Cargo, Go, Maven, npm, NuGet, PyPI, RubyGems | Dependency constraints can be available without a resolved graph |
| v3 resolved-dependency interface | npm, Cargo, Maven, PyPI | Do not infer equivalent graph support for every package ecosystem |
| Public resolver utility system definitions | npm, Maven, PyPI | Public library availability is not identical to hosted-service coverage |
| Semver utility documentation | Several ecosystem-specific schemes, including additional systems | Version comparison support is not full dependency resolution |

The table describes the inspected revision and documentation, not a permanent product guarantee. A production adapter should query or test capabilities for its selected version and record unsupported operations explicitly.

### 10.4 Requirements versus resolution

The service and utility code distinguish a requirement from a concrete version. That distinction should become a first-class invariant in repo-health. [DD-PROTO] [DD-RESOLVE]

A requirement is a constraint declared by a package or build configuration. A resolution is a selected set of versions under particular rules, available registry state, environment conditions, and options. An installation or deployment is a further observation about what actually ended up in an environment.

The canonical dependency model should therefore support at least three layers:

```text
Declaration evidence
    source version + manifest + requirement + scope + conditions
          ↓ interpreted under a named resolution context
Resolution evidence
    root + resolver/version + environment + selected instances + edges
          ↓ compared with a build, artifact, SBOM, or deployment
Realized composition evidence
    identified artifact or environment + observed included components
```

This is a proposed repo-health model. It prevents a manifest lower bound from becoming an invented installed version and prevents a provider's generic resolution from being described as every user's deployment.

### 10.5 The environment assumption in hosted graphs

The reviewed API describes its dependency graph as similar to installing the requested package on a generic 64-bit Linux system with no other dependencies present, with ecosystem-specific interpretation. [DD-PROTO]

That assumption is useful because it gives the graph a defined reference context. It is also a limit. Optional features, platform markers, runtime versions, peer dependencies, build profiles, and pre-existing constraints can produce different selections elsewhere.

repo-health should retain the provider's context with the graph. A policy checking an application's actual dependency closure should prefer the application's lockfile, resolver output, SBOM, or build evidence when available, and use the hosted graph as complementary evidence. A provider graph should not overwrite a more specific local composition merely because it is easier to fetch.

### 10.6 Resolver and client separation

The public resolver utility separates access to package versions and requirements from the algorithm that finds a satisfactory graph. The resolver operates through a client interface rather than hard-coding all data acquisition into the resolution logic. [DD-RESOLVE]

This is an excellent design for repo-health's testability. A fixture client can provide a miniature package universe with known versions and constraints. The resolver can then be tested deterministically without a live registry. The same separation permits cached or historical registry snapshots to be used for reproducible analysis.

repo-health should not immediately write its own resolver for every ecosystem. Existing native package managers, trusted resolver libraries, and provider graphs can act as evidence sources or differential oracles. The core responsibility is to retain which resolver and package universe produced each graph and to avoid pretending that different resolution methods are identical.

### 10.7 Graph-local node identity

The inspected graph utility identifies nodes by indices scoped to a particular graph. A node contains a concrete version and can carry requirement-specific errors. Edges preserve source and target node IDs, the originating requirement, and dependency type. [DD-GRAPH]

This is more precise than a graph containing one global node for every package version. A resolution can contain several instances of the same package version in different structural positions. Collapsing them prematurely can lose information about how dependencies were resolved, bundled, or nested.

repo-health should therefore distinguish a global `PackageVersion` entity from a `ResolutionNode` instance. The latter belongs to a particular resolution observation and can refer to the former. Analytics can then deliberately project the instance graph into unique package versions or unique projects when that is the desired unit.

The supplementary example includes three graph instances but only two unique package-version labels. It illustrates why node count and unique package-version count are not interchangeable, even in a very small graph.

### 10.8 Graph errors are data, not just exceptions

The graph utility separates a graph-wide resolution error from node-level errors and from operational failures such as a network problem. [DD-GRAPH]

This is a valuable model for repo-health. A partially resolved graph can still contain useful, explainable evidence. The system should preserve that graph with an incomplete status rather than either discarding everything or presenting it as complete.

Errors should also remain typed where possible. A network timeout, an unsupported ecosystem, an unsatisfied requirement, and an unknown package are different conditions. If a provider returns free-form error text, repo-health should retain the text but avoid depending on unstable message wording as a permanent machine-readable classification.

### 10.9 Canonicalization and reproducible comparison

The inspected graph utility includes canonicalization that preserves the root and orders nodes and edges, with additional handling when duplicate version nodes require more than simple sorting. [DD-GRAPH]

The best reuse is the principle of deterministic graph comparison. A regression test should not fail merely because a provider returns the same graph in a different order. Conversely, canonicalization should not erase meaningful distinctions such as node multiplicity, requirement text, or edge type.

repo-health should define a canonical serialization for each graph evidence format and test it against permutations of the same input. It should not claim that one utility function solves general graph isomorphism or every ecosystem's nested-resolution semantics. The inspected implementation is a concrete utility with a defined scope, not a universal mathematical guarantee.

### 10.10 Key ordering is not semantic version ordering

The public resolver's key comparison sorts version strings lexicographically as part of deterministic key ordering. That is appropriate for a canonical identifier order; it is not a substitute for ecosystem-specific version precedence. The semver utility separately provides parsing and constraint matching appropriate to supported schemes. [DD-RESOLVE] [DD-SEMVER]

repo-health should make the distinction visible in its types and function names. A function that orders keys for storage should not be reused to choose the newest release. A metric that measures version lag must use the ecosystem's actual version semantics and relevant release channel.

This is a good example of a source observation that is not a bug. The danger lies in reusing a correct function for the wrong purpose. A detailed code review can prevent that category of integration error before it becomes a misleading metric.

### 10.11 Package-to-project mappings with provenance

The v3 interface includes project-to-package-version mappings and prioritizes mappings derived from attestations, with a documented maximum number of returned versions. It also models provenance and attestation fields that can include source repository, source commit, statement type, and verification status. [DD-PROTO]

This is a particularly strong contribution to repo-health's package–repository bridge. A verified association between a package artifact and a source revision is different from an unverified URL in package metadata. The graph should preserve that difference rather than store only the final repository string.

Verification of an attestation must also be interpreted narrowly. It can establish that a statement or bundle passed a particular verification procedure. It does not prove that the source code is correct, that the builder is free of compromise, or that the package's maintainers are trustworthy in a general sense.

### 10.12 Bounded mapping responses

The reviewed project-package mapping operation returns at most 1,500 package versions. [DD-PROTO]

That limit is analytically important for monorepos and prolific package publishers. repo-health should not infer a complete absence of further mappings from a bounded response. It should record a cap or truncation possibility and, where necessary, use additional sources or a differently scoped query.

The general lesson extends to every provider: endpoint limits belong in the evidence contract. A response that contains valid records can still represent an incomplete population. Completeness cannot be inferred merely from HTTP success.

### 10.13 Content-hash queries and artifact identity

The API supports querying package versions by content hash, and the README describes examples for artifact and container-related identification. [DD-PROTO] [DD-README]

This is useful for connecting observed artifacts to package metadata when names are missing or ambiguous. It is not necessarily a one-to-one mapping: one artifact may be associated with several package versions, and an artifact collection can contain several relevant files.

repo-health should represent the result as candidate or evidence-backed associations. It should retain the hash algorithm and the exact bytes or artifact identity being hashed. A hash match supports content identity under the algorithm's assumptions; it does not automatically establish project identity, current maintenance, or safe behavior.

### 10.14 Reverse dependencies are still a local responsibility

The inspected stable v3 service definition does not contain a general reverse-dependent enumeration operation analogous to the Packages endpoint discussed earlier. [DD-PROTO]

repo-health can construct a reverse index from dependency observations it has acquired, but that reverse index describes its observed population. It must not be presented as an exhaustive list of all users of a package. Combining it with ecosyste.ms dependent queries can improve coverage, provided overlapping observations are deduplicated and their different semantics remain visible.

This is a key architectural reason to own the canonical graph. No single provider should dictate what a dependent means, and the absence of one API operation should not prevent repo-health from calculating a well-scoped local reverse view.

### 10.15 License and caching considerations

The README states that generated deps.dev data is available under CC BY 4.0, distinguishes upstream source data, and explicitly permits clients to cache API responses subject to the applicable API terms. The inspected source files use Apache-2.0 notices. [DD-README] [DD-PROTO] [DD-RESOLVE]

The recommended integration keeps source attribution and separates provider-generated relations from embedded upstream data. It should also cache responsibly and expose staleness rather than querying the service repeatedly for identical immutable package versions.

A local cache is an availability and reproducibility tool, not permission to ignore changes in advisories, metadata corrections, or source terms. Immutable version identifiers do not imply that every associated observation is immutable.

### 10.16 Reuse decision and adoption experiment

The stable API is a high-value provider for package-version requirements, resolution evidence, advisories, and provenance associations. The public graph and version utilities are useful as libraries or reference implementations where their language, license, and ecosystem scope fit. The complete hosted service should remain an external dependency, not an assumed self-hostable component.

The first experiment should compare a provider graph, a local lockfile-derived graph, and a native resolver result for a small set of packages with optional and platform-sensitive dependencies. Differences should be classified by context rather than automatically labeled errors. A successful adapter preserves the distinct roots, environments, node instances, requirements, and incomplete states, and can explain why two valid graphs differ.

<a id="11-openssf-scorecard-structured-security-evidence-rather-than-an-imported-badge"></a>

## 11. OpenSSF Scorecard: structured security evidence rather than an imported badge

### 11.1 The most useful integration point is below the aggregate score

Scorecard's documentation describes automated security heuristics and explicitly warns that aggregate scores are opinionated, context-dependent, and subject to false positives and false negatives. It also describes structured results as a way for consumers to evaluate particular behaviors rather than depend on one overall score. [SC-README]

This aligns closely with repo-health's evidence-first approach. The best integration is not `security_score=8.7`. It is a set of versioned findings tied to a repository revision, tool execution, and evidence location, with appropriate statuses and remediation.

The presence of such an architecture is also important prior art. repo-health need not invent a new philosophical justification for separating evidence and judgment; it can adopt and extend a pattern already visible in Scorecard's code.

### 11.2 The raw–probe–evaluation pipeline

The inspected maintenance check first collects raw data, stores it in a raw-results structure, runs probes, evaluates the findings, and attaches the findings to the returned check result. The raw collection includes archived state, recent commits, issues, and creation information. [SC-MAINT] [SC-RAW]

This separation is one of the strongest reusable patterns in the entire review:

```text
Source observations
       ↓
Raw typed data
       ↓
Narrow probes answering defined questions
       ↓
Structured findings with locations and statuses
       ↓
Context-dependent evaluation or policy
```

repo-health should implement the same logical separation for community and graph metrics. A contributor count, a persistence calculation, and a policy requiring release redundancy should be independently inspectable stages. The policy should not reach back into an opaque collector and manufacture an untraceable verdict.

### 11.3 Typed outcomes and missingness

The inspected finding model distinguishes true, false, unavailable, error, unsupported, and not-applicable outcomes. [SC-FINDING]

This is a useful starting point for repo-health's broader state model. It prevents a failed API call from being represented as a negative answer. It also acknowledges that some questions do not apply to a given repository or cannot be supported by the current tool.

repo-health's architecture already proposes additional distinctions such as partial, stale, conflicted, unauthorized, and suppressed evidence. The integration should map Scorecard outcomes into that model without losing the original status. A provider-specific outcome should remain recoverable from the imported record. [RH-ARCH]

### 11.4 A true finding can describe an undesirable condition

The finding model records the probe and its outcome, and separately supports the notion of an expected bad outcome for remediation. [SC-FINDING]

This matters because “true” is an answer to a question, not automatically a pass. A probe asking whether a repository is archived can truthfully return true. A probe asking whether a protection is enabled can also return true. Their implications differ.

repo-health should therefore preserve question polarity in the metric or finding contract. A generic ingestion pipeline that converts `True` into “healthy” and `False` into “unhealthy” would corrupt the source semantics. This is a small but essential interface test.

### 11.5 Locations and remediation

The inspected findings can include file paths, line ranges, snippets, values, messages, and remediation information. [SC-FINDING]

These fields make a result actionable. A maintainer can inspect the underlying configuration rather than debate an unexplained grade. repo-health should preserve locations where the source license and privacy policy permit it, and should always retain enough revision information to identify the file state to which the finding applies.

A line number without a source revision is fragile. The file may change before the user opens it. A remediation suggestion should also be associated with the check version because the tool's interpretation may evolve.

### 11.6 Check version, score, and inconclusive state

The inspected check-result model contains a name, version, error, score, reason, details, and findings. It uses an inconclusive score sentinel distinct from the ordinary zero-to-ten range. [SC-RESULT]

repo-health should not average that sentinel into an ordinary score, and it should not convert it to zero. When importing historical assessments, it should preserve both the check version and tool revision because a changed score can reflect a changed rule rather than a changed project.

A useful trend interface can distinguish three explanations: source behavior changed; the tool or rule changed; or coverage changed. Without that decomposition, a project may appear to deteriorate merely because a scanner learned to detect something new.

### 11.7 Public scan coverage differs from tool capability

The reviewed README states that the public weekly scan is selected from GitHub-hosted projects and that API results omit certain checks for cost reasons, including CI-Tests, Contributors, and Dependency-Update-Tool. The tool's broader capabilities and locally executed checks should not be inferred from that public dataset alone. [SC-README]

This is an unusually clear example of why repo-health needs both a **tool capability matrix** and an **observation coverage matrix**. A tool may support a check in principle, while the specific result being imported did not run it. A host may support a field while the available credentials cannot retrieve it.

The import should record which checks were executed, skipped, unsupported, or absent from the provider's delivery. It should not fill missing findings with assumptions based on the tool's advertised feature list.

### 11.8 Maintenance heuristics complement, rather than replace, continuity analysis

The inspected raw maintenance collection focuses on recent source observations and repository status. [SC-RAW]

That can provide a useful maintenance-related signal, but it is not the same as repo-health's intended analysis of persistent stewardship, contributor cohorts, handover overlap, release-role redundancy, or long-term concentration. Those require additional event history and role definitions.

repo-health should keep the imported maintenance check under its own namespace and calculate longitudinal metrics separately. This allows a user to see that a repository has recent activity while also seeing that all releases have depended on one account for several years. The two observations are compatible and should not compete for one field named `maintained`.

### 11.9 Source-data reuse without double counting

Scorecard findings can reach repo-health directly or through services that aggregate Scorecard data, including deps.dev and other reviewed systems. The README and provider documentation make these relationships visible. [SC-README] [DD-README] [AV-ANALYSIS]

Three deliveries of the same run are not three independent assessments. repo-health should retain delivery provenance but deduplicate the origin assessment using tool, repository revision, run date or identifier, and content digest where available. If exact origin identity is unavailable, the system should report possible duplication rather than inflate confidence.

This lineage problem is broader than Scorecard. It applies to vulnerability records, package metadata, repository counters, and license findings replicated through several aggregators.

### 11.10 The contributor workflow as a metric-engine model

Scorecard's check-writing documentation requires actionable results, useful details, correction mechanisms, low/high/inconclusive tests, end-to-end fixtures, and updates to generated check documentation. [SC-WRITE]

This is a strong model for accepting new repo-health metrics. A new metric should not be admitted merely because someone can write a query that returns a number. It needs a question, data requirements, a status model, examples, failure cases, and a path for affected maintainers to contest an incorrect result.

For automated dependency policy, actionability is particularly important. A finding should explain whether the remedy is to collect missing evidence, correct a mapping, change a project practice, select a supported version, or accept a documented exception. “Your project is unhealthy” is not an adequate diagnostic.

### 11.11 Integration modes

A useful first mode is to import precomputed structured results and retain their source metadata. A second mode is bounded on-demand execution for a user-selected repository and revision. A third is an optional organization-specific policy layer that evaluates selected findings alongside local evidence.

On-demand execution should be isolated and rate-budgeted. It should not inherit broad credentials merely to obtain a more complete score. The system should clearly state when the result differs because a local scan had different permissions or enabled checks.

The inspected source uses Apache-2.0 notices, while the README identifies a separate license for REST API data. Those distinctions belong in the source register and reuse review. [SC-FINDING] [SC-README]

### 11.12 Reuse decision and adoption experiment

Scorecard should be a primary source of structured security-practice evidence, not a replacement for repo-health's engineering, community, or dependency graph models. Its raw–probe–evaluation architecture and check-contribution workflow should also influence repo-health's own metric engine.

The first experiment should import a result containing positive, negative, unavailable, unsupported, and not-applicable findings, then apply two different policies to the same evidence. The evidence must remain unchanged. A second fixture should deliver the same run through two providers and verify that the UI shows two delivery paths but one origin assessment. These tests exercise the exact integration risks that a badge-only approach would hide.

<a id="12-openssf-criticality-score-reusable-signal-separation-and-an-operational-warning"></a>

## 12. OpenSSF Criticality Score: reusable signal separation and an operational warning

### 12.1 Importance is not health

Criticality Score's stated purpose is to characterize a project's influence and importance. Its source and configuration combine signals related to age, recent activity, contributors, organizations, releases, issue activity, and repository mentions. [CR-README] [CR-CONFIG]

That purpose is relevant to repo-health's criticality view, but it is not equivalent to maintenance quality or security. A highly relied-upon project can be inactive, vulnerable, or difficult to replace. A small project can be carefully maintained without being central to a large observed ecosystem.

repo-health should preserve separate dimensions for observed dependency centrality, maintenance continuity, technical findings, and replacement evidence. A criticality score can be imported as a versioned external interpretation, but it should not become the canonical project-health field.

### 12.2 An important current availability correction

The reviewed README reports that Google Cloud infrastructure and data hosted there would no longer be available after **August 29, 2026**, and directs users to data retained in the repository. It also reports that the last successful public run completed in **July 2025**. The linked operational issue explains the retirement from the maintainers' perspective. [CR-README] [CR-OPS]

As of this review, the project should therefore not be recommended as a continuously updated hosted feed on the basis of older descriptions. The source code, configuration, and retained snapshots can still be useful. Infrastructure retirement does not mean that every part of the project has become unusable or that its maintainers have abandoned all future work.

This correction is practically important for repo-health. Its own architecture must distinguish software availability, API availability, collection success, dataset freshness, and repository activity. A repository can receive commits while its public data pipeline remains stale. Conversely, a stable tool can remain useful without frequent code changes.

### 12.3 Raw signal collection separated from scoring

The repository exposes separate commands for collecting signals, enumerating repositories, and calculating scores from inputs. The scorer can be configured independently of acquisition. [CR-README] [CR-SCORER]

This is the strongest reusable design idea in Criticality Score. A new formula need not require recrawling the world if the underlying observations were retained. Different users can evaluate the same inputs under different weight configurations, and researchers can study sensitivity to those choices.

repo-health should go further by preserving the original observation types and statuses, not only a flattened row of numeric strings. The scorer should consume a well-defined measurement view, and its output should identify the formula, transformation versions, input observation IDs, and missing-input treatment.

### 12.4 Configuration is part of the measurement

The inspected `original_pike.yml` specifies the algorithm, field names, weights, bounds, distribution transformations, and whether smaller values are preferable. [CR-CONFIG]

This is a valuable model for explainable derived indicators. The configuration is not an incidental implementation detail; it determines the meaning of the result. A changed upper bound or missing-field rule can alter project ordering without any change in the projects themselves.

repo-health should therefore hash and version configurations and distinguish a **source trend** from a **model revision effect**. Historical comparisons should either use one fixed definition or explicitly show the transition between definitions. The default configuration can be useful as a reference, but its numerical choices should not be imported as universal truths about software value.

### 12.5 Legacy labels can conceal proxy measurements

The README's legacy table describes a dependents-related signal based on mentions of a project in commit messages. The inspected configuration uses a more specific repository-mention field name. [CR-README] [CR-CONFIG]

A commit-message mention can be useful evidence of attention or version-roll activity. It is not the same as a verified dependency declaration, a resolved dependency edge, a distinct downstream project, or an installed application. repo-health should retain it under a name that expresses the observed event.

This is a general migration rule: when importing legacy metrics, prefer the operational definition over the most ambitious historical label. A semantic crosswalk should document renamed fields, approximations, and differences between documentation generations. Otherwise a proxy can silently acquire the authority of a direct measurement as it passes through several systems.

### 12.6 Available-input weighted means

The inspected weighted-mean implementation accumulates values only when an input can provide one, then divides by the sum of included weights. The scorer's raw-input path also skips values that fail numeric parsing. [CR-WAM] [CR-SCORER]

This is a reasonable design choice for some uses, but it changes the denominator when evidence is missing. A project with one high observed input and several missing inputs can have a high available-input mean. That does not establish that the missing dimensions are favorable.

repo-health should always publish input coverage alongside such an indicator. It should also distinguish missing, unsupported, invalid, and deliberately excluded inputs. The accompanying example shows an available-input mean of one with only half the selected inputs observed. The example does not demonstrate a defect in an upstream deployment; it demonstrates why a scalar needs an accompanying completeness contract.

The inspected mean function also has no visible local guard for a zero total included weight. A complete adoption review should test whether callers or configuration validation prevent that case. This paper does not assert that the case is reachable in production.

### 12.7 Do not use a criticality prior as a health verdict

Some criticality inputs use plausible correlations: older projects may have accumulated users, and activity or organizational breadth may accompany importance. Such relationships can be useful heuristics, but they are not identities. Mature low-churn software can remain critical, and rapidly changing software can still have limited adoption. [CR-README]

repo-health's graph should provide more direct observations where available: distinct observed dependent projects, their contexts, package-version exposure, independently observed activity, and project-family concentration. Heuristic priors can remain optional features rather than substitutes for those observations.

The same caution applies to intervention selection. A large centrality value alone does not establish that funding a particular project will prevent the most harm. A responsible intervention view should show observed reliance, maintenance constraints, plausible interventions, cost uncertainty, and evidence of effect.

### 12.8 Operational sustainability as a first-class metric family

The infrastructure retirement provides a concrete case for measuring the health of the **data sources on which repo-health depends**. [CR-README] [CR-OPS]

The observatory should monitor provider success rates, last successful refresh, schema changes, quota consumption, retained export availability, and fallback coverage. It should not present a stale external metric as current simply because the source repository still exists.

The desired fallback is a clearly labeled as-of view, not a fabricated live estimate. Historical snapshots remain useful for research, but they should carry their acquisition dates and known limitations. A provider's own operational incident should not be misattributed as deterioration of every project whose data it supplies.

### 12.9 Reuse decision

Criticality Score should be used primarily as a reference for separating signal collection from configurable scoring, for studying explicit transformations and sensitivity, and for importing clearly dated historical observations when appropriate. Its retired hosted infrastructure should not be a required live dependency.

The adoption experiment is straightforward: take a small retained signal table, calculate an indicator under two versioned configurations, and show exactly which changes come from weights, missingness, and bounds. Then replace a repository-mention proxy with a verified dependency observation and keep the two metrics distinct. The goal is interpretability, not a new universal project ranking.

<a id="part-iii-architectural-synthesis-for-repo-health"></a>

# Part III — Architectural synthesis for repo-health

<a id="13-the-proposed-composition-reuse-the-components-own-the-semantics"></a>

## 13. The proposed composition: reuse the components, own the semantics

### 13.1 A canonical core with replaceable providers

The reviewed systems collectively supply much of the difficult groundwork. The recommended repo-health architecture is therefore not a clean-room rewrite of every subsystem. It is a canonical evidence and analytical core with adapters around existing services, collectors, and tools.

```text
                      ACQUISITION AND ANALYSIS PROVIDERS

Native Git ───────────────────────────────────────────────┐
Forge APIs / Perceval / optional CollectOSS or Aveloxis ────┤
ecosyste.ms repository, package and dependent APIs ────────┤
Manifest parser workers / selected resolver utilities ────┤
deps.dev requirements, graphs and provenance ─────────────┤
Scorecard structured findings / other scoped analyzers ──┤
                                                        ▼
                          EVIDENCE INGESTION BOUNDARY
              source identity • scope • status • timestamps
              content digest • transformation • rights • lineage
                                                        ▼
                         REPO-HEALTH CANONICAL MODEL
        projects • repositories • packages • versions • artifacts
        accounts • identity assertions • roles • events • relationships
                                                        ▼
                        VERSIONED ANALYTICAL PROJECTIONS
        intrinsic metrics • continuity • upstream exposure
        downstream distributions • criticality • coverage
                                                        ▼
                         EXPLANATION AND POLICY LAYER
              human reports • APIs • coding-agent decisions
```

This is a proposed design. It places the integration boundary before evaluation, where evidence can still be inspected and corrected. It also makes it possible to replace a provider without redefining every metric.

### 13.2 Four different kinds of reuse

A useful decision vocabulary has four categories.

**Data reuse** means consuming an API, export, or retained dataset while preserving its provenance and rights. ecosyste.ms and the hosted deps.dev service are strong candidates for this mode.

**Process reuse** means running a pinned tool or service behind an interface, often in an isolated worker. Perceval, a selected community collector, a manifest parser, or Scorecard can fit this mode.

**Library reuse** means incorporating code into the implementation after checking its API stability, license, dependencies, and security boundary. Public resolver and version utilities may fit, depending on the chosen language and scope.

**Conceptual reuse** means adopting a definition, architecture pattern, or test idea without copying the implementation. CHAOSS metrics, the queue watermark invariant, and Criticality Score's acquisition/scoring separation are examples.

The categories should be recorded per component. “We use GrimoireLab” is too vague to explain operational, licensing, or maintenance responsibilities.

### 13.3 The smallest useful deployment

The existing implementation plan proposes a compact initial system with a native core, PostgreSQL, retained evidence, and a CLI or API. This review supports retaining that discipline. [RH-PLAN]

A first deployment does not need every reviewed database and message broker. It can use PostgreSQL for canonical entities, jobs, and metric observations, with filesystem or object storage for content-addressed evidence. Optional workers can emit a common interchange format. A search engine or specialized graph store should be added only when measured query patterns justify it.

This avoids a common integration failure: spending the first development cycle operating a large analytics stack before the project can answer one downstream-health question correctly. The initial proof of value should be a narrow, inspectable report, not the number of services running in Compose.

### 13.4 Language boundaries should follow contracts

The original plan presents Rust as a proposed baseline while leaving room for a deliberate language decision. The reviewed ecosystem contains useful Go, Python, and Ruby components. [RH-PLAN] [AV-README] [CO-README] [EC-PARSER] [DD-RESOLVE]

There is no need to translate all useful code into one language immediately. A stable process boundary can preserve reuse while keeping the core's types and invariants coherent. Conversely, invoking a subprocess for a trivial transformation can create unnecessary complexity. The decision should depend on interface stability, execution cost, licensing, and the importance of controlling the semantics.

The recommended first choice is to own the canonical schemas and metric contracts in the core, while allowing language-specific workers for mature parsing and collection tasks. Porting becomes justified when a measured bottleneck, security requirement, or maintenance burden outweighs the cost of preserving upstream compatibility.

### 13.5 A provider observation is not yet a canonical fact

An incoming record should enter an evidence layer before it becomes a canonical relationship. For example, a package metadata URL can be stored as a source assertion. A resolver graph can be stored as a context-bound observation. A contributor account match can be stored as a proposed identity relation. A Scorecard finding can be stored under its original probe and tool version.

Canonical projections then apply explicit rules. They may accept, qualify, conflict, or defer an assertion. This prevents the first provider to return a plausible value from becoming the unquestioned authority for the entire graph.

The model also supports correction. A later verified attestation can strengthen a package-to-source association without deleting the earlier metadata evidence. A mistaken person merge can be reversed without rewriting the original account events.

### 13.6 Proposed evidence envelope

```json
{
  "observation_id": "local-content-or-record-identity",
  "subject": {"type": "repository", "id": "repo:example"},
  "source": {
    "provider": "provider-name",
    "host_instance": "source-instance-id",
    "native_object_id": "provider-object-id",
    "locator": "retained-source-locator"
  },
  "time": {
    "event_time": null,
    "source_updated_at": null,
    "observed_at": "2026-09-19T00:00:00Z",
    "valid_from": null,
    "valid_until": null
  },
  "acquisition": {
    "run_id": "run:example",
    "collector_version": "pinned-version",
    "requested_scope": "scope:example",
    "coverage_status": "partial"
  },
  "payload": {
    "schema": "provider-schema-version",
    "digest": "sha256:example",
    "retained_object": "evidence:example"
  },
  "lineage": {"origin_assessment_id": null, "derived_from": []},
  "rights": {"license_reference": null, "retention_class": "technical-metadata"}
}
```

This is illustrative schema design, not a live repo-health endpoint. The example timestamp is synthetic. The important properties are separation of clocks, explicit scope, lineage, and a retained source representation.

### 13.7 A capability manifest for every adapter

An adapter should advertise capabilities at a finer level than its provider's name. A useful manifest states which entity types, event categories, time ranges, pagination modes, authentication levels, and completeness guarantees it supports.

For example, a generic Git adapter may support commit history and tags but not issue responses. A public Scorecard feed may supply selected checks but omit others. A package provider may enumerate latest dependents but only return a bounded project-package mapping. These are source-specific facts that must survive normalization. [GL-PERCEVAL] [SC-README] [EC-PKG-API] [DD-PROTO]

Capabilities also need versioning. An adapter that gains Forgejo support or a parser that begins preserving optional dependencies has changed the set of statements it can support. Historical measurements should not be retroactively treated as if the new capability had always existed.

### 13.8 The evidence lineage graph

repo-health needs two related graphs: the software ecosystem graph and the evidence derivation graph. The latter connects source observations, transformations, imported assessments, and final metrics.

Suppose the same Scorecard run is obtained directly, through deps.dev, and through another aggregator. The ecosystem graph contains one assessed repository revision. The evidence graph contains three delivery paths pointing toward one origin assessment. Treating the deliveries as independent votes would overstate corroboration.

The lineage key should include as much origin identity as available: tool and version, subject revision, original assessment time or run ID, and a digest of the structured result. When these fields are incomplete, the system can mark possible duplication instead of inventing certainty. The synthetic companion test demonstrates the simplest case: three deliveries, one origin.

### 13.9 A normalization loss report

Every adapter should report whether it preserved, transformed, inferred, or discarded each field relevant to downstream analysis. The Parser/Bibliothecary comparison provides a concrete reason for this requirement. [EC-PARSER] [EC-BIB]

A loss report can be machine-readable. For example, it might state that the input included integrity and optionality fields, the selected service omitted them, and the resulting dependency edges therefore have unknown optionality and no artifact-integrity assertion. This prevents an absent field from silently becoming a false value.

The same mechanism can cover time precision, actor identity, dependency directness, and error categories. The goal is not to reject every lossy source. It is to let later calculations know what the source can and cannot support.

### 13.10 Derived views, not destructive enrichment

An enrichment should produce a new projection linked to its inputs. It should not overwrite the raw observation with a more confident-looking field. A canonical person assignment, a current package mapping, or a health classification may change as evidence improves.

A useful storage pattern has immutable or append-oriented evidence objects, versioned assertions, and replaceable materialized views. The view can be rebuilt after a correction while the previous interpretation remains identifiable. Deletion and suppression policies can restrict retained content, but the system should still distinguish a corrected conclusion from a silently changed database row.

This is the architectural feature that makes the reviewed components composable. Their differing representations become inputs to one explicit interpretation layer rather than competing definitions of reality.

<a id="14-temporal-correctness-what-happened-what-was-observed-and-what-was-known"></a>

## 14. Temporal correctness: what happened, what was observed, and what was known

### 14.1 Why timestamps alone are insufficient

Many reviewed components store timestamps, but a temporal observatory needs to know what each timestamp means. A source event time, provider update time, local collection time, successful analysis time, and publication time are not interchangeable. Aveloxis's collection-start cursor and ecosyste.ms's parse-attempt behavior illustrate two concrete places where this distinction affects correctness. [AV-QUEUE] [EC-REPO]

repo-health should define a time vocabulary before implementing hundreds of metrics. Each adapter maps its fields into that vocabulary with explicit uncertainty. A source that provides only a date should not acquire invented second-level precision during normalization. A missing timezone or an untrusted author timestamp should remain qualified.

### 14.2 Event time and knowledge time

Let \(t_e\) denote when an event is asserted to have occurred and \(t_k\) denote when repo-health learned the assertion. A late-arriving event can have \(t_e < t_k\). An identity correction can change the interpretation of an old event without changing its event time.

A bitemporal representation records both the interval in which an assertion is considered valid and the interval in which that assertion was accepted by the system. This supports two different queries:

> What is our current best reconstruction of project activity during 2024?

and:

> What would repo-health have reported on December 31, 2024, using only information available then?

The second query is essential for honest evaluation of prediction or policy. Using later identity corrections, later vulnerability disclosures, or future contributor activity to improve a historical assessment introduces look-ahead information unless the evaluation explicitly permits it.

### 14.3 Late events and correction windows

A collection-start watermark reduces some missed-event risks, but it is not a complete temporal model. Sources can publish delayed objects or modify old records. A contributor can edit profile information. A repository can rewrite history. A provider can correct a package mapping.

The proposed ingestion policy combines incremental acquisition with bounded overlap and periodic reconciliation. Each source declares which historical regions can change and how reliably the collector can detect those changes. Derived metrics then have an invalidation rule: which input changes require recomputing which windows.

For an event-count metric, a late event affects the windows containing its event time. For a cohort-retention metric, it can affect both first-observation cohort assignment and later return status. For an identity merge, the affected windows may span the full retained history of the identities. These are different computational costs and should be planned explicitly.

### 14.4 Snapshot semantics

Some observations are events; others are snapshots. A list of current package owners, a branch-protection configuration, or a repository's archived flag describes state at an observation time. It does not automatically reveal the state at all earlier times.

repo-health should not backfill a current snapshot across the entire project lifetime. Instead, it can record that the state was observed at a particular time and, under a declared persistence assumption, treat it as valid until contradicted. Such an assumption should remain distinguishable from direct historical evidence.

This matters for maintainer authority. A person currently listed as a package publisher should not automatically be credited with every historical release. Historical publication events and current permission snapshots support different statements.

### 14.5 Successful empty snapshots and failed acquisition

The reviewed Aveloxis and ecosyste.ms analysis paths make it clear that empty results and errors require different handling. [AV-ANALYSIS] [EC-REPO] [EC-PARSER]

A proposed snapshot state machine should distinguish: recognized input with a complete empty result; recognized input with observations; partial analysis; unsupported input; operational error; and evidence restricted or unavailable. Only a complete successful snapshot should replace the current projection for the declared scope.

A failed scan can update the last-attempt record while leaving the old successful projection intact and visibly stale. A partial scan can produce a new partial observation without pretending to replace unobserved parts of the previous scope. These rules prevent operational failures from looking like sudden improvements, such as a dependency list disappearing after a parser error.

### 14.6 Current releases versus historically available releases

A dependency freshness metric must use the release universe relevant to the query. A package that lagged the newest available version in 2023 should be compared against versions available in 2023, not a release published in 2026. The same applies to supported branches and security fixes.

The provider's current package-version list can help reconstruct availability if reliable publication timestamps exist, but it may not contain yanked or deleted artifacts. The result should therefore state its historical coverage. A current response is not automatically a complete historical registry snapshot.

A useful metric contract can include `comparison_as_of`, `release_channel`, `support_policy_source`, and `version_resolution_status`. These fields make a freshness value interpretable without pretending every ecosystem follows one release convention.

### 14.7 Two kinds of historical recomputation

repo-health should support **definition-preserving recomputation**, which reruns the same metric version on corrected or more complete inputs, and **definition-changing recomputation**, which applies a new metric version to retained evidence. These operations should produce different provenance records.

The distinction allows a trend to be explained. A contributor count may rise because additional identities were discovered, because a split corrected a mistaken merge, or because the metric changed from commit authors to all participants. The same numerical change can have very different meanings.

A report should make it possible to compare the old and new results and identify the causal chain in the evidence graph. This is a stronger standard than merely storing each value with a timestamp.

### 14.8 A minimum temporal acceptance suite

Before implementing large-scale analytics, repo-health should pass fixtures for a late event, an edited event, a deleted source object, a repository rename, a package source migration, an identity merge and split, a provider outage, a failed scan followed by a successful empty scan, and a metric-definition change.

Each fixture should test both current-corrected and as-known-at-the-time queries. The requirement is not that every source provides perfect history; it is that the system accurately represents the history and uncertainty it actually has.

<a id="15-contributor-and-maintainer-continuity-an-exact-operational-model"></a>

## 15. Contributor and maintainer continuity: an exact operational model

### 15.1 Separate participation, persistence, authority, and concentration

The reviewed systems supply useful pieces, but repo-health should avoid one field that attempts to summarize a person's relationship to a project. CollectOSS and Aveloxis provide observed cross-project activity. SortingHat provides identity and affiliation structures. CHAOSS and Cereslib provide concentration and participation concepts. Scorecard provides maintenance-related observations. [CO-BREADTH] [AV-BREADTH] [GL-SH-MODEL] [CH-CAF] [GL-CERES] [SC-RAW]

The proposed model has four separate dimensions:

| Dimension | What it measures | What it does not establish |
|---|---|---|
| Participation | Observed actions of specified types | Current maintainership or permission |
| Persistence | Activity across defined time periods | Full-time commitment or personal reliability |
| Authority | Documented or observed operational roles | Competence, honesty, or future availability |
| Concentration | Distribution of events or roles among actors | A complete counterfactual estimate of project failure |

These dimensions can be joined in a report, but they should not be conflated in storage.

### 15.2 Actor and role entities

A source account is an identity within a host or registry. A person projection groups identities under accepted assertions. A role assertion describes a relationship such as release publisher, reviewer, triager, or documented maintainer. An activity event records an action.

A release event can identify the account that published it. A permissions snapshot can identify accounts allowed to publish at a particular time. A maintainer document can identify declared responsibilities. These observations overlap, but none should overwrite the others.

A role assertion should contain its source, scope, observation time, effective interval if known, and strength class. A self-declared role, a repository document, and an authenticated permission response can be presented as different evidence classes without pretending to rank a person's character.

### 15.3 Active-period persistence

For contributor \(u\), project \(p\), event family \(a\), and period \(j\), let:

\[
I_{u,p,a,j}=1
\]

when at least one qualifying event is observed in that period, and zero when a complete observation of that period contains none. When period coverage is incomplete, the indicator should be unknown rather than zero.

A simple persistence statistic is the number of known active periods in a specified window. A corresponding active-period fraction uses only a clearly declared denominator. If some periods are unobserved, report the observed fraction and coverage separately rather than silently treating missing periods as inactivity.

This measure is more directly related to temporal continuity than a lifetime event threshold. It still does not establish that the contributor was continuously responsible for maintenance. A person can make regular small contributions without holding an operational role.

### 15.4 Persistence thresholds are policy parameters

A project may define a persistent participation cohort as activity in at least six of the last twelve months, or in several quarters across multiple years. Those thresholds can be useful, but they are not universal facts about healthy maintenance.

repo-health should expose the threshold, event type, period length, observation window, and coverage requirement. Different project types may need different profiles. A mature library with infrequent releases should not be judged by the same activity cadence as a fast-changing application framework.

The default interface should emphasize continuous measurements such as active-month count and tenure distribution before introducing categorical labels. Labels can summarize a policy, but the underlying values should remain visible.

### 15.5 Cohort retention and right censoring

Retention requires an eligible cohort. Let \(f_u\) be a contributor's first qualifying observed event time. For a retention horizon \(h\), a contributor cannot yet be evaluated if the required follow-up period has not elapsed or was not observed.

Define an eligible set \(E_h\) using both elapsed time and coverage. Define a return condition in a declared follow-up window, such as any qualifying event in months 10 through 12 after first contribution. Then:

\[
R_h = \frac{|\{u \in E_h : u\text{ meets the return condition}\}|}{|E_h|}.
\]

The follow-up window must be part of the definition. “Ever made a second contribution,” “returned within three months,” and “active around the twelve-month anniversary” are different statistics.

The companion fixture has four eligible contributors, two of whom returned, plus four recent contributors who cannot yet be evaluated. The eligible retention rate is 50 percent, not the 25 percent obtained by placing all eight people in the denominator. This is a synthetic illustration of censoring, not an empirical result about an open-source community.

### 15.6 First observed contribution is not necessarily first contribution

A collector may begin after a project has existed for years, or a source may expose only a recent event window. The earliest retained event is then the first **observed** contribution, not necessarily the person's true first contribution.

repo-health should distinguish left-truncated histories from complete histories. A cohort analysis built from incomplete history should be labeled accordingly. Otherwise experienced contributors can be misclassified as newcomers simply because the observatory began watching them recently.

This limitation is particularly relevant to account-event breadth collectors. They can support current cross-project discovery while providing insufficient evidence for lifetime tenure. [CO-BREADTH] [AV-BREADTH]

### 15.7 Contribution concentration by responsibility

The concentration family should be calculated separately for authored commits, reviews, releases, triage, and other well-defined event types. For each family, useful observations include top-one share, top-three share, \(K_{50}\), \(K_{80}\), and a distribution concentration statistic.

For shares \(s_i\) summing to one, the Herfindahl-style concentration quantity \(H=\sum_i s_i^2\) and its reciprocal \(1/H\) can summarize effective participation breadth. These are mathematical descriptors of the selected event distribution, not proofs of organizational resilience. The metric contract must state its event population and zero-total behavior.

A project can have distributed commits but concentrated releases. That difference is precisely why responsibility-specific measures are valuable. The system should not let a large number of code contributors conceal a single observed release publisher.

### 15.8 Succession should be defined through observable transitions

A succession analysis should begin with role and activity transitions, not a claim that a person “disappeared.” Useful observations include the last observed action by a previous role holder, the first observed action by a successor, overlap in relevant activity, and continuity of releases or reviews after the transition.

A proposed handover measure can record the overlap interval between two observed role-active periods. It can also record whether releases continued during a defined follow-up window. These are measurable conditions, but they do not prove a deliberate handover occurred unless documentation or other evidence supports that interpretation.

An interval with no public activity can reflect many unobserved circumstances. The report should use language such as “no qualifying public release activity observed in the covered interval,” rather than a personal explanation for the absence.

### 15.9 A continuity profile instead of a trust score

A useful contributor or project profile could expose:

```text
Observed release publishers, last 12 months:              3
Publishers active in at least 3 distinct quarters:        2
Largest publisher share of observed releases:            61%
Distinct reviewers of release changes:                    4
Documented release procedure observed:                    yes
Documented deputy role observed:                          unknown
Prior publisher/successor activity overlap:               7 months
Release observation coverage:                            12 / 12 months
Identity mapping status:                                 1 unresolved alias
```

All quantities are illustrative. The profile provides evidence for continuity without asserting that any person is inherently trustworthy. It also distinguishes a positive observation from an unknown field.

### 15.10 Cross-project histories without prestige laundering

The user specifically wants a project's condition to reflect sustained work by contributors with relevant histories elsewhere. The reviewed breadth collectors make such histories more observable, but interpretation requires care. [CO-BREADTH] [AV-BREADTH]

A contributor's participation in a prominent project should not automatically increase every other project's health. Instead, repo-health can report exact cross-project observations: number of projects with qualifying review events, number of years with observed release activity, number of distinct ecosystems with verified contributions, and the coverage of those histories.

These observations can support a user's assessment of experience, but they are not proof of expertise in every domain. They also should not disadvantage capable maintainers whose work is private, self-hosted outside the observed sources, or concentrated in one long-lived project.

### 15.11 Do not attribute every defect to an individual

Metrics such as a person's regression rate or vulnerabilities introduced are much harder than counting commits. A defect can involve several changes, a misunderstood specification, a review process, a dependency update, or a previously latent issue. Automated blame attribution is a model, not a raw fact.

repo-health should initially record links between fixes, issues, advisories, and changes where sources explicitly provide them. It should avoid turning those links into a personal quality score. More advanced attribution belongs in an experimental namespace with validation, uncertainty, and correction mechanisms.

The same applies to “projects still healthy after a maintainer left.” Observed project activity after a role transition can be measured. Causally crediting or blaming the departing person requires a much stronger study design.

### 15.12 Bots, agents, and assisted work

Automation can generate commits, update dependencies, publish releases, and participate in review workflows. A source may explicitly identify an account as a bot, but the use of AI assistance by a human account is often not directly observable.

repo-health should retain explicit source classifications and allow unknown automation status. It should not infer AI use from writing style or volume and then silently discount contributions. Separate metrics for human-attributed, bot-attributed, and unknown events can be useful where the classification is supported.

A high volume of automated updates can coexist with weak human review capacity. The relevant question is not whether automation exists, but which responsibilities are observed, how changes are reviewed, and whether a stable maintenance core can respond when automation fails.

### 15.13 Identity correction as an analytical transaction

SortingHat's reversible identity structures provide a starting point, but repo-health must connect correction to derived measurements. [GL-SH-MODEL] [GL-SH-SPLIT]

A merge or split should produce a new identity snapshot, identify affected projects and time windows, invalidate dependent projections, and schedule recomputation. Raw source events remain unchanged. The correction record should explain why the mapping changed and who or what authorized the change.

The supplementary identity example demonstrates the basic invariant: three source identities become two person groups after a merge and return to three after a split, while the underlying four events remain four. A production implementation must extend that invariant across historical windows and cross-project edges.

### 15.14 Recommended first continuity metrics

The first release should favor measurements that can be explained directly: observed active periods, first and last observed activity, role-specific participant counts, contribution concentration, eligible cohort retention, and observed handover overlap. Each should include coverage and identity status.

More ambitious measures—maintainer-collapse probability, personal security track record, mentorship quality, or causal succession success—should remain deferred until the system has suitable data and validation. The catalog can reserve identifiers for them without presenting them as implemented or exact.

This approach honors the user's desire for many concrete metrics while protecting the project from the false precision that a large metric inventory can otherwise encourage.

<a id="16-downstream-ecosystem-health-the-graph-analysis-repo-health-should-own"></a>

## 16. Downstream ecosystem health: the graph analysis repo-health should own

### 16.1 The unit of analysis comes before the graph algorithm

A reverse dependency graph can contain repositories, projects, packages, package versions, resolution instances, build artifacts, or deployments. Each is a valid unit for some questions. The first design decision is therefore not which centrality algorithm to use, but what the nodes and edges mean.

The reviewed systems provide different pieces: ecosyste.ms exposes package and dependent-package relationships; deps.dev exposes version-scoped requirements and resolution graphs; community collectors provide repository events; identity systems group accounts. repo-health must join these pieces through explicit mappings rather than treat their identifiers as interchangeable. [EC-PKG-API] [EC-DEP] [DD-PROTO] [CO-BREADTH] [GL-SH-MODEL]

A project-health report should normally aggregate to independent project entities, while retaining the package-version paths that justify the relationship. A security exposure report may need exact artifact or resolution-instance granularity. Those projections should coexist rather than compete for one universal graph.

### 16.2 Define a downstream population explicitly

Let \(P\) be a project, \(t\) an as-of time, \(W\) an observation policy, and \(C\) a dependency-context profile. Define:

\[
D(P,t,W,C)
\]

as the set of distinct downstream project entities for which qualifying dependency evidence is accepted under those conditions. The definition must specify how package-to-project mappings are accepted, how mirrors are deduplicated, which releases or repository snapshots are selected, and which edge types qualify.

This is a proposed notation, not an existing provider API. Its purpose is to make the denominator reproducible. “Dependents” without these qualifications can mix latest releases, historical releases, unresolved declarations, optional dependencies, and multiple representations of the same project.

### 16.3 Independently calculate intrinsic measurements

For each downstream project \(d\), calculate an intrinsic metric vector \(M(d,t,W)\) from that project's own evidence. Do not define it using the health of the focal upstream project \(P\).

This avoids the circular argument that a library is healthy because healthy projects use it, while those projects are healthy because they use the library. Graph-derived measures can be added separately, but the intrinsic evidence used in the downstream view should not recursively depend on the conclusion it is supposed to support.

The vector might contain active release publishers, concentration, covered active periods, review response distributions, and selected technical findings. It need not contain one combined health score. Indeed, separate dimensions are more useful for diagnosing why a downstream ecosystem appears robust or fragile.

### 16.4 Report distributions, not only averages

For metric \(m\), let \(D_m\subseteq D\) be the downstream projects with usable observations. A downstream summary should report the distribution of \(m\) over \(D_m\), together with coverage \(|D_m|/|D|\).

An empirical distribution can be written as:

\[
F_{P,m}(x)=\frac{1}{|D_m|}\sum_{d\in D_m}\mathbf{1}[M_m(d)\le x].
\]

This representation makes it possible to show medians, quantiles, tails, and threshold counts without collapsing every project into one quality number. Unknown projects are not assigned zero. A known-population average should be explicitly labeled as such.

The supplementary example contains two known values and two unknowns. It reports the average over the known values and 50 percent coverage. It does not extrapolate the average to the unobserved projects.

### 16.5 Named policy counts are more honest than “healthy dependents”

A user may still want a convenient summary such as the share of dependents with a stable maintenance core. repo-health can provide that as a named policy result:

```text
Downstream projects meeting continuity-profile-v1:   38 / 61 evaluated
Downstream projects not meeting that profile:        23 / 61 evaluated
Downstream projects with insufficient evidence:      19
Total qualifying downstream projects:                80
```

The example is synthetic. Its advantage is that the rule, evaluated population, and unknown population are visible. It does not assert that “healthy” is a primitive binary property that the observatory has directly measured.

The policy profile can be revised without rewriting the underlying intrinsic observations. Historical reports should retain the profile version used at the time.

### 16.6 Mirrors, forks, and project families

A repository mirror should not ordinarily count as an independent downstream project. A fork may be a mirror, a temporary contribution vehicle, or a genuinely independent project. Deduplicating all forks would lose meaningful adoption; counting all forks independently would inflate it.

repo-health should represent a project-family relation with evidence and a declared purpose. Shared Git history, explicit mirror configuration, package publication, diverging development, and project documentation can support different classifications. The relation should remain revisable.

For downstream analysis, publish both raw repository counts and deduplicated project-family counts when useful. The synthetic fixture shows four repository representations mapped to three declared families. The family mapping is an input assumption in that fixture, not an automatically proven truth.

### 16.7 Multiple packages from one project

A monorepo can publish many packages that all depend on a library. Counting each package as an independent project would inflate downstream adoption. Conversely, a repository can contain components with different maintainers and release processes.

The graph should preserve both package-level and project-component relationships. A project-level report may deduplicate packages to one project, while a component-level report can keep meaningful subdivisions. The aggregation policy should be explicit and supported by project membership evidence.

This is why package-to-repository lookup is only the beginning of the bridge. A repository URL does not necessarily identify the correct organizational unit for maintenance analysis. [EC-PKG-API] [DD-PROTO]

### 16.8 Direct and transitive reachability

Transitive reachability should count unique entities under the selected projection, not paths. In a diamond where A depends on B and C and both depend on D, D is one unique dependency even though there are two paths to it.

Cycles require a visited set or a strongly connected component treatment. A useful implementation condenses strongly connected components into an acyclic graph for certain analyses while retaining the original edges for explanation. The focal node should not accidentally count itself as a dependent merely because a cycle returns to it.

The accompanying diamond and cycle examples test these basic invariants. They are intentionally small because errors in graph semantics should be caught before any distributed graph engine is introduced.

### 16.9 Dependency context is not an importance ranking

The earlier conversation suggested that runtime dependencies are strong signals and development dependencies weaker ones. That can be useful for some adoption questions, but it should not become a universal security weighting. A build-time dependency can execute in a privileged environment, and a test dependency can influence release validation.

repo-health should preserve the scope and execution context rather than assign one fixed “dependency strength” ordering. An adoption report, a runtime exposure report, and a build-chain security policy may legitimately treat the same edge differently.

Optionality also needs context. An optional dependency can be absent from one deployment and essential in another. The graph should retain the condition or feature profile when known, and should not silently convert unknown optionality to an unconditional relationship.

### 16.10 Historical adoption and retention

A dependency relationship is temporal. A project may adopt a library, retain it for several releases, pin an old supported version, or replace it. Latest-state and historical queries should remain distinct, as the inspected ecosyste.ms API already demonstrates. [EC-PKG-API]

A proposed adoption-persistence metric measures how long qualifying dependency evidence remains present across observed snapshots, with gaps and coverage recorded. A removal event should require a successful comparable snapshot in which the relationship is absent; a failed parse is not evidence of migration.

Migration toward another library can sometimes be observed from coordinated manifest changes, but the reason for the migration is usually not established by the graph alone. The report should say that a dependency was replaced or removed, not that the project “lost trust” unless a cited project statement supports that explanation.

### 16.11 Upgrade behavior

Downstream upgrade lag can be informative, but it requires a relevant release and a defined comparison population. A major incompatible release, a security patch, and a routine minor release should not necessarily share one expected adoption curve.

A useful metric records the distribution of elapsed time between an upstream release and the first observed downstream snapshot selecting it or a qualifying fixed version. Projects whose follow-up interval is incomplete are censored. Projects intentionally tracking a supported older branch should be classified separately where support evidence exists.

This is a richer analysis than counting outdated dependencies. It can distinguish delayed adoption, compatibility constraints, maintained long-term branches, and missing observations. The graph must preserve exact versions and context to support those distinctions.

### 16.12 Downstream contribution feedback

One potentially valuable graph question is whether downstream users contribute fixes, tests, documentation, or review effort upstream. Contributor-breadth collectors provide one starting point, but a reliable feedback measure needs to connect an actor's downstream affiliation or participation to a specific upstream contribution without overclaiming representation. [CO-BREADTH] [AV-BREADTH]

A person contributing to both projects is an observed cross-project participant. That does not necessarily mean they acted on behalf of the downstream project. An explicitly linked downstream bug report or jointly documented fix provides stronger evidence of a feedback relationship.

repo-health should therefore offer a conservative primitive such as distinct accounts with qualifying activity in both projects, and reserve stronger “downstream-funded maintenance” or “downstream-originated fix” labels for explicit supporting evidence.

### 16.13 Centrality and blast radius

Graph centrality can identify structural importance in an observed network. It does not directly count users, revenue, critical infrastructure, or social benefit. A high reverse-reachability count means many observed nodes depend on a component under a specified graph definition.

A blast-radius view should preserve that scope. It can show affected package versions, project families, or known deployments when an advisory or disruption matches particular edges. It should not multiply an approximate download count by dependent counts to invent a number of people affected.

Where the graph is incomplete, label the result as observed reachability. Calling it a lower bound is appropriate only when identity and edge validity support that interpretation; unverified matches can also introduce false positives. Uncertainty can increase or decrease a count.

### 16.14 Graph propagation without circular health claims

PageRank-like algorithms or other propagation methods can be useful for structural analysis. They should remain separate from intrinsic health and should disclose edge weighting, damping, treatment of missing nodes, and project-family deduplication.

A propagated importance value is not independent evidence that a project's code is secure. A mutually dependent cluster can be central without being well maintained. A new, carefully engineered library can be peripheral because it has not yet accumulated users.

repo-health can offer structural metrics alongside community and engineering observations. It should not use graph prestige to convert popularity into a proof of trustworthiness.

### 16.15 The most useful first downstream report

A first report should avoid an elaborate global influence algorithm. It should answer a small number of concrete questions: which independently identified projects currently have qualifying dependency evidence; which source and snapshot support each relationship; what intrinsic continuity observations are available for those projects; and what proportion of the downstream population is unknown.

A drill-down should show the exact package-version or manifest path connecting the downstream project to the focal library. A user should be able to challenge a mistaken mapping or mirror classification and see the resulting metrics recomputed.

This is the distinctive vertical slice that should appear early in repo-health's development. It connects the reviewed infrastructure to the user's actual goal without waiting for a complete map of every repository on the internet.

<a id="17-measurement-contracts-and-a-large-metric-catalog-without-semantic-chaos"></a>

## 17. Measurement contracts and a large metric catalog without semantic chaos

### 17.1 Hundreds of metrics require stronger discipline, not weaker definitions

The original architecture proposes 360 candidate metrics. A catalog that large is valuable only if its definitions are consistent enough to compare and maintain. Otherwise it becomes a collection of numbers whose names imply more than their inputs support. [RH-ARCH]

The reviewed projects suggest complementary foundations: CHAOSS for conceptual questions; Aveloxis for catalog synchronization; CollectOSS for executable metric registration; Cereslib for composable transformations; and Scorecard for typed findings, documentation, and correction workflows. [CH-MET] [AV-MET] [CO-MET] [GL-CERES] [SC-WRITE]

repo-health should combine those ideas in a versioned registry rather than add a database column every time a new metric is invented.

### 17.2 A complete metric contract

Each metric should declare its identifier, version, question, entity type, value type, unit, formula or algorithm, event population, grouping key, time window, filters, identity policy, dependency context, required source capabilities, coverage calculation, missingness behavior, cost class, interpretation limits, and test fixtures.

For ratios, the numerator and denominator should be separately recoverable. For percentiles, the population and quantile convention should be stated. For durations, the start and end events must be defined. For counts, event grain and deduplication keys must be explicit. For classifications, the threshold and rule version must be attached.

The contract should also identify whether a value is directly observed, deterministically derived, provider-estimated, model-estimated, or manually asserted. These classes should not be collapsed merely because their outputs are all numeric.

### 17.3 Raw, derived, and modeled values

A raw observation might be a release timestamp or a source-reported counter. A deterministic metric might count releases in a covered interval. A provider estimate might approximate repository population size. A modeled value might predict future maintainer attrition.

The storage layer should retain these distinctions. A model probability requires calibration evidence and an identified training or validation population. A deterministic calculation can still be misleading if its input coverage is poor. A source-reported integer can still be estimated or manipulated.

The goal is not to assign a universal confidence decimal to every field. In many cases, a categorical method and coverage report is more honest and useful than an unsupported probability.

### 17.4 Missingness is part of the result

The original architecture's state vocabulary includes observed, unavailable, unauthorized, partial, stale, not applicable, error, conflicted, suppressed, unsupported, and related distinctions. Scorecard's outcome model provides an implementation reference for preserving several of these states. [RH-ARCH] [SC-FINDING]

A metric result should therefore be a tagged value, not a nullable number with an ambiguous meaning. Null can represent many different conditions. The API should make those conditions queryable and visible in comparisons.

A project with no detected security policy in a fully inspected tree differs from a project whose tree could not be retrieved. A repository with no releases in a covered period differs from one hosted on a platform whose release API is unsupported. The same principle applies across the entire catalog.

### 17.5 Metric families and shared intermediate projections

A large catalog can be computationally manageable when related metrics share intermediate data. A contributor-period table can support active-period counts, retention cohorts, and concentration by period. A normalized dependency edge table can support direct counts, reverse reachability, and adoption transitions. A release-event table can support cadence, publisher concentration, and handover analysis.

The registry should declare dependencies among metrics and intermediate projections. A source correction can then invalidate only the affected computations. This is more efficient and more auditable than recalculating every metric independently from raw API responses.

Shared intermediates should not hide incompatible populations. Two metrics may use the same event table while requiring different identity snapshots or branch scopes. Those parameters must remain part of the computation key.

### 17.6 Cost classes

A useful proposed cost classification is: metadata-only; bounded event aggregation; source-history scan; dependency resolution; graph traversal; source-code analysis; and experimental model inference. The classes describe likely resource behavior, not fixed performance guarantees.

The scheduler can use the classification to prioritize cheap freshness updates and reserve expensive work for changed inputs or explicit user requests. A metric should expose its data freshness separately from the freshness of the entire project record.

This extends the selective collection patterns visible in ecosyste.ms and the phased analysis described by Aveloxis and Graal. [EC-REPO] [AV-ANALYSIS] [GL-GRAAL]

### 17.7 Interpretation text should be generated and constrained

A narrative layer can explain a metric, but it should not invent reasons for a change. If the data show that release activity declined, the explanation should say so and identify the covered interval. It should not infer burnout, loss of interest, or organizational dysfunction without evidence.

Generated summaries should cite the exact metric observations and policy rules they use. A language model can help make explanations readable, but it should not be the authority deciding whether a numerical claim is true. The underlying result must be reproducible without the prose generator.

This is especially important when repo-health feeds coding agents. The agent should consume structured facts and policy results, not rely on persuasive narrative language to decide whether a dependency is admissible.

### 17.8 A metric acceptance checklist

Before a metric enters a stable API, it should have: a documented estimand; a schema; deterministic fixtures; zero and missing-population cases; duplicate and correction cases; a coverage calculation; interpretation limits; a cost bound or budget policy; and a named owner for definition changes.

A metric can remain experimental until those conditions are met. The catalog should distinguish planned identifiers, implemented experimental measurements, and stable measurements. This avoids turning the ambition to collect many metrics into a misleading claim of completed functionality.

<a id="18-operational-architecture-correctness-under-failure-and-limited-resources"></a>

## 18. Operational architecture: correctness under failure and limited resources

### 18.1 A successful API call is not a successful analytical update

The ingestion lifecycle should distinguish successful network acquisition, durable evidence storage, successful normalization, valid relationship projection, and completed metric calculation. A failure at any later stage must not make the earlier evidence disappear or advance an unrelated checkpoint.

The Aveloxis queue and breadth collector provide useful references for persistence ordering and successful-cursor advancement. ecosyste.ms provides useful examples of asynchronous parsing and bounded scheduling. repo-health should adopt those patterns with explicit state transitions and failure injection tests. [AV-QUEUE] [AV-BREADTH] [EC-PARSER] [EC-REPO]

### 18.2 Idempotency and lease fencing

A job may execute more than once because of retries, worker restarts, or lease expiry. The canonical event key should make repeated ingestion harmless. A completed transformation should be identified by its input digest, tool version, and configuration rather than by an arbitrary process invocation alone.

Lease fencing prevents an old worker from overwriting a newer result after losing ownership of a job. A generation token or equivalent mechanism should be checked when committing a projection. The design should not promise exactly-once execution when it actually implements at-least-once execution with idempotent effects.

### 18.3 Provider budgets and fairness

Each provider needs a budget for requests, concurrency, retries, and expensive analysis. Backoff should distinguish rate limits, temporary failures, unsupported operations, and persistent authorization failures. Repeatedly retrying an unsupported endpoint is not resilience.

The scheduler should publish evidence-age distributions and deferred-work counts by source and project cohort. This makes collection bias visible. A high-volume provider should not consume the entire budget while self-hosted or low-activity projects remain permanently stale.

A global observatory also needs a bounded discovery policy. Following every contributor to every repository and every dependency to every dependent can expand rapidly. Discovery depth, node budgets, and reasons for stopping should be part of each collection run's metadata.

### 18.4 Cache immutable inputs, refresh mutable associations

Source files at a content digest and immutable artifact bytes are suitable for long-lived content-addressed caching. Associated metadata, advisories, package ownership, source mappings, and support status can change even when a package version string remains the same.

repo-health should therefore cache evidence at the appropriate layer. A parser result can be reused for identical bytes under an identical transformation. An advisory association or current publisher snapshot needs its own refresh policy. A single cache time-to-live for an entire project record is too coarse.

### 18.5 Monitor the observatory's own dependencies

The Criticality Score infrastructure notice shows why provider availability and data freshness deserve first-class monitoring. [CR-README] [CR-OPS]

repo-health should maintain a provider health dashboard containing last successful collection, current schema version, failure categories, quota pressure, retained historical coverage, and fallback paths. These are measurements of repo-health's information supply chain, not judgments about the software projects being observed.

An outage should change coverage and freshness, not silently lower the health of every downstream subject. A result produced from retained evidence should carry an explicit as-of date and the reason it has not been refreshed.

<a id="19-security-privacy-and-rights-at-the-integration-boundary"></a>

## 19. Security, privacy, and rights at the integration boundary

### 19.1 The observatory processes adversarial inputs

Repository URLs, archives, manifests, source files, issue text, and metadata are untrusted input. The proposed system should assume that some inputs are malformed or deliberately crafted to consume resources, confuse identity resolution, or influence a policy result.

The Parser and Graal-style workflows are especially sensitive because they fetch or unpack source content and invoke analysis tools. The reviewed code and documentation establish those processing boundaries, but this paper has not audited them for all security properties. [EC-PARSER] [GL-GRAAL]

### 19.2 Safe acquisition and analysis controls

The proposed controls include destination validation for server-side fetching, redirect revalidation, rejection of unintended local or private-network targets, bounded response and archive sizes, extraction-path checks, symlink controls, resource limits, and separation of acquisition credentials from analysis workers.

Repository-controlled scripts, package installation hooks, compiler plugins, and analyzer configuration should not execute in the ordinary observation pipeline. Where dynamic analysis is genuinely required, it belongs in a stronger isolated environment with an explicit permission profile.

A tool's output is also untrusted. Findings and filenames must be safely rendered, and an imported narrative must not become instructions for an agent. The canonical metric engine should accept only schema-validated observations and should not execute code embedded in source metadata.

### 19.3 Data minimization for contributor information

Maintainer continuity does not require unrestricted personal profiling. The system should prioritize public technical actions, declared responsibilities, and narrowly relevant affiliation evidence. It should not infer health conditions, personality, gender, or political preferences from contributor behavior.

The reviewed identity and enrichment models demonstrate why selective import is necessary: upstream schemas can contain fields beyond repo-health's purpose. [GL-SH-MODEL] [GL-CERES]

Person-level reports should emphasize coverage and uncertainty, permit correction of mistaken identity merges, and avoid interpreting unobserved activity as a personal failure. Public-interest analysis should not become an opaque reputation system that contributors cannot inspect or challenge.

### 19.4 Correction, suppression, and retention

repo-health needs a correction workflow for identities, project mappings, source classifications, and metric interpretation. Corrections should be auditable and should trigger appropriate recomputation. A maintainer should be able to see which evidence supports a claim and provide a relevant correction without paying for privileged access.

Suppression and deletion are different from correction. Some retained personal content may need restricted access or removal under the system's governance and applicable obligations. A provenance design should support recording that an input was suppressed without preserving the disallowed content in a supposedly immutable public archive.

The archival tradeoff visible in Perceval is a useful warning: redacting a projection does not remove sensitive material from raw storage. [GL-PERCEVAL]

### 19.5 License declarations are evidence, not automatic clearance

The inspected sources contain several different licensing arrangements: MIT declarations in selected community tooling and metric documentation; GPL-3.0-or-later notices in several GrimoireLab components; Apache-2.0 notices in deps.dev utilities, Scorecard, and Criticality Score; and separate API-data licensing declarations in the hosted services. [CH-MET] [CO-README] [CO-BREADTH] [GL-PERCEVAL] [GL-SH-MODEL] [DD-PROTO] [SC-FINDING] [CR-SCORER] [EC-PARSER-DOC]

The implementation should evaluate code incorporation, modified distribution, service operation, data redistribution, attribution, and upstream-content rights separately. This review records observed declarations; it does not establish that every planned integration is legally compatible.

A missing or unread license should remain unresolved. In particular, the Bibliothecary fork's attempted top-level license lookup did not establish its terms. That gap should block unreviewed code incorporation, not be filled by assuming the license of a related repository.

### 19.6 Evidence quality and gaming

A public metric can become a target. Commit splitting, automated issue comments, artificial dependent repositories, duplicated mirrors, and boilerplate policy files can increase visible counts without improving maintenance capacity.

The proposed response is not a secret anti-gaming score. It is transparent event definitions, deduplication, separate automation populations, project-family analysis, multiple independent dimensions, and explicit evidence strength. A project should not be able to turn a burst of trivial activity into several years of observed continuity.

The system must also avoid punishing legitimate practices. Squashed commits, infrequent stable releases, small expert teams, and self-hosting can all produce low values for some metrics without indicating poor software. Context and coverage are safeguards against both manipulation and unfair interpretation.

<a id="20-coding-agent-integration-evidence-guided-choices-without-false-guarantees"></a>

## 20. Coding-agent integration: evidence-guided choices without false guarantees

### 20.1 A policy engine should consume findings, not persuasive prose

The eventual coding-agent integration should query structured evidence about a proposed dependency and evaluate a versioned policy. Scorecard's separation of raw data, findings, and evaluation is a strong reference for this design. [SC-MAINT] [SC-FINDING]

An agent should not be allowed to change the policy, metric definition, or coverage interpretation merely to satisfy its implementation goal. Policy ownership should remain with the user or organization. The result should explain whether the dependency meets the selected requirements, fails a specific requirement, or lacks enough evidence for a decision.

### 20.2 A proposed decision record

```yaml
decision_id: decision-example
subject:
  package: ecosystem/name
  version: exact-version-or-explicit-unresolved-requirement
  composition_context: context-id
policy:
  id: application-dependency-policy
  version: 3
  digest: policy-content-digest
outcome: review_required
reasons:
  - requirement: release-role-redundancy
    status: insufficient_evidence
    observations: [observation-a, observation-b]
  - requirement: known-advisory-policy
    status: satisfied_for_observed-composition
    observations: [observation-c]
coverage:
  dependency_resolution: partial
  maintainer_history: observed_12_months
  native_boundary_analysis: not_performed
```

This is a proposed format, not an implemented guarantee. The point is to preserve the scope of the conclusion. A dependency can satisfy a known-advisory policy while remaining unexamined for native memory safety or malicious behavior.

### 20.3 Unknown should have an explicit workflow

A policy can choose to allow, warn, require review, or block when evidence is insufficient. That is a user's risk decision, not a universal fact about the project. The interface should state what evidence would resolve the uncertainty where feasible.

Automatically rejecting all small or self-hosted projects would create an unfair and potentially self-reinforcing adoption bias. A more useful workflow permits local evidence, maintainer corrections, bounded analysis, or a documented exception. Unknown evidence should not be disguised as bad health.

### 20.4 Formal verification remains a separate layer

repo-health can record evidence of formal verification, memory-safety analysis, or checked interface contracts when a suitable tool supplies it. It should not infer those guarantees from contributor continuity, popularity, or a security-practice score.

For Elisa or elisa-proof integration, a future package admission decision could combine ecosystem evidence with machine-checked properties of a particular artifact or boundary. Those properties would need their own specifications, proof artifacts, checker identity, trusted assumptions, and version binding. The observatory would organize and expose the evidence; it would not transform community metrics into a proof of program correctness.

### 20.5 Measure whether decisions improve

The success criterion is not the number of dependencies rejected. It is whether users receive more accurate, actionable information and make better-supported choices without excessive false alarms or unnecessary exclusion.

A pilot should record which findings changed a decision, whether the finding was correct, what additional evidence resolved uncertainty, and whether maintainers found the result actionable. These observations can improve policy defaults without claiming that a high rejection rate demonstrates safety.

<a id="part-iv-evaluation-implementation-priorities-and-conclusions"></a>

# Part IV — Evaluation, implementation priorities, and conclusions

<a id="21-evaluation-protocol"></a>

## 21. Evaluation protocol

### 21.1 What this review actually validated

The companion script executed **16 deterministic synthetic checks**, all of which passed during preparation of this paper. They cover join cardinality, count-distribution interpretation, cumulative-threshold classification, cohort eligibility, event count versus duration, graph deduplication, cycle termination, graph-instance identity, reversible identity grouping, evidence lineage, watermark overlap, snapshot replacement, missing-input coverage, typed statuses, project-family deduplication, and partial downstream summaries.

These checks validate only the miniature models and invariants encoded in the script. They do not establish that the reviewed projects pass or fail their own integration tests, nor do they prove repo-health is implemented. Several examples are motivated by source observations, but the script does not import or execute the upstream codebases.

### 21.2 A staged empirical evaluation

The first empirical stage should validate acquisition and normalization against a small set of known source objects. The second should validate metric calculations on controlled fixtures and manually checked public examples. The third should validate package-to-project mappings and downstream populations. Only after those stages should the project evaluate whether its reports improve real dependency decisions.

The sequence matters. A sophisticated graph statistic cannot compensate for incorrect identity joins or incomplete dependency parsing. A useful interface cannot make an invalid retention denominator valid.

### 21.3 Sampling the pilot population

A pilot should include projects differing in host type, language ecosystem, age, release cadence, contributor count, repository structure, and availability of public collaboration data. It should include self-hosted sources and mature low-churn projects, not only popular GitHub repositories.

The sample should be documented as a pilot population rather than presented as representative of all open source. Projects whose data cannot be retrieved should remain in the coverage report. Excluding them silently would bias the evaluation toward easy-to-observe communities.

The initial goal is to expose semantic and operational failures, not to estimate one universal global health distribution.

### 21.4 Differential testing

Where two providers expose related information, compare them under matched scope. For example, compare a manifest parser's output with a native resolver export, or compare a provider's dependent list with a sample of the underlying declarations. Disagreements should be classified before they are called errors.

Possible classes include different source snapshots, different dependency contexts, different identity mappings, missing pages, unsupported formats, provider estimates, stale caches, and actual normalization defects. A differential test is useful only when it can distinguish these explanations.

The same principle applies to contributor metrics. Two systems can return different counts because one includes comments and another counts commit authors. The test must compare operational definitions, not just metric names.

### 21.5 Human review and correction quality

A small, consent-based maintainer review can assess whether reports describe project practices accurately and whether corrections are understandable. The review should avoid asking maintainers to endorse a global personal reputation score.

Useful outcomes include the rate of mistaken project mappings, mistaken identity merges, misleading role labels, unsupported abandonment interpretations, and unhelpful remediation. Corrections should become fixtures or definition improvements where possible.

The evaluation should also measure the effort imposed on maintainers. A health observatory that generates many false alarms and requires extensive unpaid explanation can become a burden rather than a benefit.

### 21.6 Performance claims need measured workloads

No throughput or cost benchmark was performed in this review. Existing fleet-scale descriptions are source claims, not independently reproduced results.

repo-health should measure ingestion throughput, evidence storage growth, normalization cost, graph traversal latency, correction fan-out, and provider request consumption on declared workloads. Results should include hardware, dataset size, graph density, cache state, tool versions, and source latency assumptions.

The first performance target should be predictable bounded behavior. A query that returns a complete answer for a declared scope is preferable to an apparently fast global query that silently truncates its population.

### 21.7 Predictive models come later

A future model might estimate the probability of a defined maintenance event or prioritize projects for manual review. Such a model needs labels, temporal validation, calibration, coverage analysis, and fairness review. It should not be trained on a target that merely restates one of its input metrics.

Historical evaluation must avoid future information, including later contributor activity or corrected identities unavailable at the prediction time. Source outages must not be mislabeled as project deterioration. Model outputs should remain separate from directly observed metrics.

Until those requirements are met, repo-health should expose descriptive evidence and named policies rather than advertise a scientifically established probability of maintainer collapse or project failure.

<a id="22-reuse-roadmap-aligned-with-the-existing-implementation-plan"></a>

## 22. Reuse roadmap aligned with the existing implementation plan

### 22.1 Preserve the original milestone discipline

The existing plan uses gated milestones from contracts and safe Git scanning through multi-source collection, package evidence, continuity, graph analysis, user interfaces, operations, broader coverage, and advanced analytics. This review recommends targeted changes within that sequence, not replacing it with a simultaneous integration of every reviewed project. [RH-PLAN]

| Milestone | Reuse or design input from this review | Required exit evidence |
|---|---|---|
| M00 — Contracts and test oracles | CHAOSS crosswalk; Scorecard outcome model; semantic fixtures | Versioned contracts, source register, zero/missing/duplicate tests |
| M01 — Safe Git scan | Perceval envelope concepts; Graal snapshot boundary | Reproducible scan with source scope and no repository-controlled execution |
| M02 — Durable multi-source ingestion | Aveloxis queue/cursor patterns; Perceval capabilities; optional community collector | Retry, overlap, lease, pagination and source-failure fixtures |
| M03 — Package identity and dependencies | ecosyste.ms lookup/parser; deps.dev requirements and graph utilities | Declared/resolved separation, field-preservation tests and provenance |
| M04 — Continuity and identity | SortingHat concepts; CollectOSS/Aveloxis breadth; CHAOSS concentration | Reversible identities, eligible cohorts, role-specific concentration |
| M05 — Temporal downstream graph | ecosyste.ms dependent queries; deps.dev graph identity | Deduplicated populations, context-aware paths, independent downstream metrics |
| M06 — API, interface and policy | Scorecard findings and correction workflow | Every conclusion traces to observations and a rule version |
| M07 — Pilot operations | Provider-health monitoring and isolated analysis | Outage, retention, correction and hostile-input exercises |
| M08 — Broader sources | Selected Perceval backends and additional direct adapters | Per-capability tests, not a brand-level support claim |
| M09 — Expanded metric catalog | Shared intermediates and generated documentation | Each new stable metric passes a complete contract gate |
| M10 — Measured scaling | Bounded sweeps, caching, projections and backpressure | Published workload measurements and coverage-preserving limits |
| M11 — Advanced models or proof evidence | Separate experimental interfaces | Validation and explicit assumptions before decision use |
| M12 — Stable release and governance | Source attribution, correction policy and maintenance ownership | Reproducible release, documented support and sustainable operation |

### 22.2 The first integration should prove the distinctive feature

A particularly useful vertical slice is one focal library with a small set of observed dependents. Collect source history for the focal project, import package associations and dependency evidence, calculate a few intrinsic continuity metrics for the dependents, and show the result with coverage and drill-down evidence.

That slice exercises the hardest conceptual joins without requiring a global index. It also demonstrates something more distinctive than a new commit-frequency dashboard. The user can inspect why each dependent is included and how its condition was measured independently.

### 22.3 Recommended initial backlog

The first backlog should include: a source identity schema; an observation envelope; a metric contract registry; native Git evidence; one external repository/package lookup adapter; one parser adapter with loss reporting; a small canonical dependency graph; contributor-period projections; identity correction fixtures; downstream population deduplication; structured findings; and an evidence drill-down command.

The order should prioritize the contracts that later integrations cannot safely bypass. A new provider should not introduce its own incompatible project identity or missingness semantics merely to produce a quick demonstration.

### 22.4 Upstream contributions can be more valuable than forks

Where a useful upstream component loses needed fields or lacks a small interface feature, an upstream contribution may be the best reuse strategy. Preserving parser fields, improving metric documentation, adding a boundary fixture, or exposing provenance can benefit both repo-health and other consumers.

Potential concerns identified by static inspection should be validated before filing a definitive defect report. A small reproducible test and a precise description are more useful than a broad claim that an upstream metric is wrong. The review's synthetic examples are starting points for such tests, not completed upstream bug reports.

A private fork should be a deliberate decision with an owner, update strategy, and exit plan. Otherwise repo-health risks creating the maintenance burden it is intended to help others understand.

### 22.5 Decisions to defer

The project should defer a universal project-health score, personal trust rankings, large-scale predictive abandonment models, automatic global identity merging, complete dynamic dependency resolution for every ecosystem, and a mandatory distributed graph platform.

These features either require evidence not yet available or introduce substantial semantic and operational complexity. Deferral does not mean they are impossible. It means their prerequisites should be established through the earlier milestones rather than assumed.

<a id="23-threats-to-validity-and-unresolved-questions"></a>

## 23. Threats to validity and unresolved questions

### 23.1 Selection bias

The reviewed shortlist was chosen because it had already surfaced as relevant. It is not a random sample or exhaustive survey. Additional systems may offer stronger implementations of particular features, including downstream analysis, funding observatories, code intelligence, or software composition policy.

The paper therefore supports reuse decisions within the inspected corpus. It does not establish market uniqueness or the absence of prior research elsewhere.

### 23.2 Static inspection versus execution

Source code can reveal structure and potential failure modes, but deployed behavior depends on configuration, versions, data, and uninspected call paths. Documentation can be stale or aspirational. A function that appears problematic in isolation may be protected by surrounding validation.

The review distinguishes these evidence levels and avoids claiming a full audit. The next step for any adopted component is a pinned integration test against the exact interface and workload repo-health will use.

### 23.3 Temporal and provider drift

APIs, source repositories, service availability, and schemas can change after the review date. The pinned code references preserve what was inspected, while default-branch documents are recorded with file-object hashes where available. Neither eliminates the need to refresh the review before deployment.

The Criticality Score availability correction demonstrates why current operational notices matter. A technically accurate historical description can still be a poor basis for a new live integration. [CR-README]

### 23.4 Construct validity

Maintenance continuity, software reliability, security, adoption, and social usefulness are different constructs. No selected set of repository statistics fully measures all of them. A concrete number can still be a weak proxy for the property a user cares about.

repo-health should state these limits in its interface and keep metrics tied to observable questions. The project becomes more credible by declining to overinterpret a signal, not by assigning a number to every desirable concept.

### 23.5 Remaining adoption questions

Before implementation, the project still needs to choose exact supported releases, verify component and dataset licenses for its intended distribution model, inspect selected endpoint schemas, test source-host coverage, evaluate operational cost, and decide which identity-management capabilities to operate locally.

The implementation language also remains a project decision. This review supports a contract-centered architecture that can use several language-specific tools, but it does not establish that one language is empirically optimal for the entire system.

<a id="24-conclusion"></a>

## 24. Conclusion

The reviewed ecosystem already contains substantial parts of repo-health's proposed foundation. CHAOSS provides measurement concepts and interpretation discipline. Aveloxis provides pragmatic integrated collection and analysis patterns. CollectOSS provides rich community event structures and cross-project contributor discovery. GrimoireLab provides heterogeneous collectors, identity management, and reusable enrichment architecture. ecosyste.ms provides discovery and package–repository relationships at a breadth that would be expensive to recreate initially. deps.dev provides explicit package-version and resolution semantics. Scorecard provides structured security findings and a clean separation between evidence and evaluation. Criticality Score provides configurable signal recomputation and a concrete reminder that data-source operations are themselves a dependency. [CH-CAF] [AV-QUEUE] [CO-BREADTH] [GL-PERCEVAL] [GL-SH-MODEL] [EC-PKG-API] [DD-PROTO] [SC-MAINT] [CR-SCORER] [CR-README]

The strongest repo-health project is therefore not another isolated scoring application. It is an evidence-preserving integration and analysis system that keeps units, time, identity, scope, provenance, and uncertainty intact across those components.

Its most important locally owned capabilities should be the canonical temporal model, executable metric contracts, reversible assertion handling, independent downstream-condition analysis, and explainable policy results. These are the places where a careless integration can lose the meaning of otherwise valuable upstream data.

The proposed path is concrete: begin with a small focal project and its observed dependents; reuse mature acquisition and parsing capabilities; retain source evidence and transformation identity; test edge cases before scaling; and expand the metric catalog only when definitions and coverage are defensible. That path offers a credible way to make rapid software development better informed without pretending that popularity, contributor history, or a security badge can guarantee safe software.

<a id="part-v-implementation-facing-appendices"></a>

# Part V — Implementation-facing appendices

<a id="appendix-a-component-disposition-and-adoption-gates"></a>

## Appendix A. Component disposition and adoption gates

The following matrix is a decision aid for repo-health, not a statement that every listed integration has been implemented or tested. “Adopt” refers to an architectural invariant unless the row explicitly says to incorporate code.

| Component | Reuse mode | Specific value | Adoption gate | Avoid |
|---|---|---|---|---|
| CHAOSS metric specifications | Conceptual | Questions, filters, concentration and participation semantics | Versioned crosswalk and local operational definition | Claiming conformance from a shared metric name alone |
| Aveloxis staging architecture | Conceptual or selected implementation | Decoupled acquisition and relational processing | Evidence replay and transactional tests | Treating normalized rows as the only retained evidence |
| Aveloxis queue | Selected compatible code or reference | Atomic claims, retries and collection-start cursors | Lease-fencing, overlap and failure-injection tests | Assuming row locks provide exactly-once execution |
| Aveloxis contributor breadth | Adapter or reference | Discovery of account activity in other repositories | Event-type and time-coverage contract | Presenting bounded activity as a complete career history |
| Aveloxis analysis history | Conceptual | Atomic snapshot replacement and retained history | Failed-versus-empty scan tests | Refreshing evidence age from attempt time alone |
| CollectOSS event collection | Data import or optional sidecar | Rich community event acquisition | Native event identity and deduplication tests | Importing aggregate counts without their event grain |
| CollectOSS contributor metrics | Query reference | Registered calculations and relational joins | Cardinality fixtures and schema verification | Copying a query solely because its label matches |
| CollectOSS breadth worker | Adapter or reference | Cross-project event edges with source fields | Host-qualified identities and cursor tests | Treating every event as a maintainer role |
| Perceval | Optional collector process | Multi-source collection envelope and replay | Capability, provenance and privacy tests | Archiving identifiers that the public projection hides |
| SortingHat | Optional identity service or model reference | Identities, individuals, affiliations, recommendations and audit | Merge/split replay and privacy review | Automatic global merging without evidence or correction |
| GrimoireELK studies | Analytical reference | Grouped, reusable enrichment projections | Defined populations and recomputation cost | Assuming every study is incremental |
| Cereslib transforms | Selected reference or compatible library | Small composable transformations | Row-grain and boundary tests | Using cumulative-position labels as authority roles |
| Graal | Optional analysis-worker pattern | Revision-bound historical source analysis | Pinned tools, safe sandbox, bounded snapshots | Running repository-controlled code in the core service |
| SirMordred | Configuration reference | Collection phases and nested source grouping | Overlap-aware aggregation and secret handling | Equating an analytical group with identity equivalence |
| ecosyste.ms Repos | Data provider | Host/repository discovery and metadata | Coverage, estimates, aliases and freshness contract | Treating every indexed row as fully analyzed open source |
| ecosyste.ms Packages | Data provider | Package mapping and latest/historical dependent queries | Population completeness and registry identity tests | Treating a top list as an exhaustive census |
| ecosyste.ms Parser | Service or isolated worker | Multi-format manifest analysis | Field-preservation, status and extraction tests | Converting unsupported input into zero dependencies |
| Bibliothecary fork | Candidate library | Rich documented dependency representation | Exact license resolution and fixture-based format audit | Assuming related-project licensing or preserving only a subset silently |
| ecosyste.ms Commits/Issues | Candidate data providers | Event-family enrichment | Endpoint-specific schema and coverage review | Inferring lifetime completeness from service descriptions |
| ecosyste.ms Dashboards | Presentation reference | Existing ecosystem views | Inspect selected view and API contract | Making the UI's data model canonical |
| deps.dev stable API | Data provider | Version requirements, graphs and provenance | Context, caps, status and caching tests | Treating generic resolution as an actual deployment |
| deps.dev resolver utility | Candidate library or oracle | Resolver/client separation and typed graph structure | Ecosystem compatibility and differential tests | Assuming utility coverage equals hosted-service coverage |
| deps.dev semver utility | Candidate library or oracle | Ecosystem-specific version semantics | Scheme-specific golden cases | Using lexicographic key order for release precedence |
| Scorecard | Findings provider and optional tool | Structured security-practice evidence | Outcome polarity, missingness, version and lineage tests | Importing only a badge or averaging inconclusive sentinels |
| Criticality Score | Configuration and historical-data reference | Independent acquisition and recomputation | Dated inputs, missingness and model-version tests | Depending on the retired hosted infrastructure as a live feed |

A practical acquisition policy should select one primary source for each kind of evidence and allow corroborating or fallback sources without multiplying origin observations. The matrix does not require repo-health to operate every service simultaneously.

<a id="appendix-b-concrete-metric-crosswalk"></a>

## Appendix B. Concrete metric crosswalk

These are **proposed repo-health metric identifiers**, not claims about existing upstream API names. “Foundation” identifies useful source material or data structures; it does not imply that the upstream project already calculates the exact local metric. All ratios require numerator, denominator, and coverage records. All time windows and identity policies must be versioned.

| Proposed metric | Exact observable or calculation | Foundation | Essential qualification |
|---|---|---|---|
| `history.commits.distinct` | Distinct source-native commit events in selected history | [GL-PERCEVAL] [CO-MET] | Branch scope, rewritten history, authorship versus event count |
| `history.covered_interval` | Earliest/latest covered interval and gaps | [GL-PERCEVAL] [AV-QUEUE] | Source coverage, not project lifetime |
| `collection.last_success_age` | Query time minus last successful acquisition time | [AV-QUEUE] [EC-REPO] | Separate attempt and projection times |
| `collection.failed_attempts` | Failed collection runs in a window | [AV-QUEUE] [EC-PARSER] | Measures the observatory/provider, not project health |
| `collection.duplicate_delivery_count` | Repeated deliveries mapped to existing event or assessment | [CO-BREADTH] [SC-FINDING] | Logical event identity must be stable |
| `collection.coverage_fraction` | Covered eligible units divided by requested eligible units | [GL-PERCEVAL] [SC-README] | Unit may be periods, pages, repositories or checks |
| `contributors.accounts.distinct` | Distinct host-qualified accounts with qualifying events | [CO-BREADTH] [AV-BREADTH] | Account count is not person count |
| `contributors.persons.distinct` | Distinct accepted person projections for the same events | [GL-SH-MODEL] | Identity snapshot and unresolved identities |
| `contributors.first_observed_at` | Minimum qualifying retained event time | [CO-BREADTH] [GL-PERCEVAL] | Not necessarily first-ever contribution |
| `contributors.last_observed_at` | Maximum qualifying retained event time | [CO-BREADTH] [AV-BREADTH] | No inference about private activity |
| `contributors.active_periods` | Number of covered periods with qualifying events | [AV-MET] [CH-OCC] | Period length and event family |
| `contributors.active_period_fraction` | Active covered periods divided by eligible covered periods | [CH-OCC] | Publish unobserved-period coverage separately |
| `contributors.single_event_count` | Actors with exactly one qualifying event in a declared history | [CH-OCC] | Not a negative quality label |
| `contributors.repeat_event_threshold` | Actors crossing an explicit event-count threshold | [AV-MET] | Does not measure duration |
| `contributors.returned_horizon` | Eligible cohort members meeting a specified return condition | [CH-OCC] [AV-MET] | Censoring and follow-up coverage |
| `contributors.cross_project_count` | Distinct projects with observed qualifying account activity | [CO-BREADTH] [AV-BREADTH] | Mapping quality and feed limits |
| `contributors.cross_project_event_types` | Counts by event family across projects | [CO-BREADTH] | Keep comments, reviews and releases separate |
| `contributors.bot_event_fraction` | Explicitly bot-classified qualifying events over classified events | [AV-MET] [GL-SH-MODEL] | Unknown automation status remains separate |
| `roles.release_publishers` | Distinct actors linked to observed release publication | [AV-ARCH] | Observed action versus current permission |
| `roles.documented_maintainers` | Distinct declared maintainers in inspected source material | [EC-REPO] | Declaration provenance and revision |
| `roles.permission_holders` | Actors in an observed permission snapshot | Canonical role model | Only where legitimately exposed; not inferred from commits |
| `roles.active_quarters` | Covered quarters with observed role-specific activity | [GL-ONION] | Role definition and snapshot interpretation |
| `concentration.top_one_share` | Largest actor count divided by total qualifying events | [CH-CAF] | Event family and identity snapshot |
| `concentration.top_three_share` | Sum of three largest counts divided by total | [CH-CAF] | Defined behavior for fewer than three actors |
| `concentration.k50` | Minimum number of actors covering at least half the events | [CH-CAF] | Empty population is undefined, not zero risk |
| `concentration.k80` | Minimum number covering at least 80 percent | [CH-CAF] [GL-CERES] | Explicit extension; crossing actor and ties |
| `concentration.effective_actors` | Reciprocal sum of squared event shares | Mathematical descriptor | Not a literal number of replaceable maintainers |
| `succession.overlap_duration` | Intersection length of two observed role-active intervals | [GL-SH-MODEL] plus role events | Does not prove intentional handover |
| `succession.post_transition_releases` | Releases in a covered follow-up window after a defined transition | [AV-ARCH] plus local projection | Eligibility, support branch and coverage |
| `identity.pending_merges` | Unapplied identity-match recommendations | [GL-SH-MODEL] | Operational data-quality measure |
| `identity.corrections_count` | Accepted merge/split or mapping corrections | [GL-SH-MODEL] [GL-SH-SPLIT] | High count can reflect good correction practice |
| `identity.unresolved_fraction` | Events or actors lacking an accepted person mapping | [GL-SH-MODEL] | Declare denominator; avoid forced merges |
| `affiliation.organization_count` | Distinct supported affiliations in a time window | [GL-SH-MODEL] | Unknowns and historical affiliation dates |
| `affiliation.contribution_share` | Event share assigned under a stated affiliation model | [GL-SH-MODEL] | Domain inference is not employer verification |
| `releases.observed_count` | Distinct releases in a covered window | [AV-ARCH] [CR-README] | Tags versus releases versus registry publications |
| `releases.interval_distribution` | Gaps between comparable release events | [AV-MET] | Mature cadence and supported branches |
| `releases.publisher_concentration` | Concentration of observed release-publishing events | [CH-CAF] plus release events | Human/account identity and delegated automation |
| `dependencies.declared_direct` | Qualifying declarations in selected manifests | [EC-DEP] [DD-PROTO] | Requirements and unknown directness retained |
| `dependencies.resolved_instances` | Nodes in a specific resolution graph, excluding root as defined | [DD-GRAPH] | Instance count, not unique package count |
| `dependencies.unique_versions` | Distinct package-version identities in a selected graph | [DD-GRAPH] | Preserve node multiplicity in source evidence |
| `dependencies.unresolved_count` | Declarations lacking an accepted target or selected version | [EC-DEP] [DD-RESOLVE] | Unresolved target versus unresolved version |
| `dependencies.optional_count` | Dependencies explicitly marked optional under a context | [EC-BIB] | A missing optional flag is unknown |
| `dependencies.integrity_present` | Dependencies carrying declared integrity information | [EC-BIB] | Algorithm and assertion versus verified bytes |
| `dependencies.requirement_churn` | Added/removed/changed declarations between comparable snapshots | [EC-DEP] [AV-ANALYSIS] | Successful comparable snapshots required |
| `dependencies.release_date_lag` | Date difference for an exact selected and relevant comparison version | [AV-ANALYSIS] | Not vulnerability severity or a resolved range |
| `downstream.latest_package_count` | Distinct dependent packages under latest-published query semantics | [EC-PKG-API] | Provider coverage and bounded-list mode |
| `downstream.historical_package_count` | Distinct packages with qualifying historical declarations | [EC-PKG-API] [EC-PKG-REL] | Historical adoption, not present deployment |
| `downstream.project_family_count` | Distinct accepted downstream families after mapping | [EC-PKG-API] plus local graph | Family assertions can be corrected |
| `downstream.metric_coverage` | Downstream projects with usable metric divided by eligible population | Local graph projection | Report separately for each intrinsic metric |
| `downstream.continuity_distribution` | Distribution of a named intrinsic continuity metric | Local graph projection | No recursive use of focal-project health |
| `downstream.policy_match_fraction` | Evaluated dependents meeting a named versioned rule | [SC-FINDING] pattern plus local graph | Evaluated and unknown denominators separate |
| `downstream.adoption_duration` | Covered interval with qualifying dependency observations | [EC-PKG-API] plus temporal edges | Gaps and historical versus latest states |
| `downstream.upgrade_lag` | Time to observed adoption of a defined qualifying version | [DD-PROTO] plus temporal edges | Censoring and relevant release policy |
| `downstream.cross_project_participants` | Actors with qualifying events in upstream and downstream projects | [CO-BREADTH] [AV-BREADTH] | Does not prove organizational representation |
| `graph.unique_reverse_reachability` | Unique qualifying downstream entities reached under context | [DD-GRAPH] plus local reverse index | Cycles, deduplication, scope and completeness |
| `graph.component_size` | Entity count in a strongly connected component | Local graph projection | Projection and edge types defined |
| `graph.path_depth` | Shortest or maximum permitted dependency depth under a stated algorithm | [DD-GRAPH] | Cycles and truncation semantics |
| `provenance.source_mapping_class` | Evidence class of package/artifact-to-source association | [DD-PROTO] | Verified statement is not code correctness |
| `provenance.verified_attestations` | Count of imported attestations reported verified by an identified verifier | [DD-PROTO] | Preserve verifier, statement type and artifact binding |
| `security.findings_by_outcome` | Imported findings grouped by typed outcome and probe | [SC-FINDING] | True/false polarity and tool version |
| `security.executed_check_coverage` | Executed applicable checks over selected check set | [SC-README] [SC-RESULT] | Feed omissions are not failures |
| `security.finding_age` | Time since original assessment of an identified revision | [SC-RESULT] | Delivery date is not assessment date |
| `metadata.security_document_present` | File-presence observation at a source revision | [EC-REPO] | Presence is not process effectiveness |
| `analysis.snapshot_count` | Distinct successfully analyzed source snapshots | [AV-ANALYSIS] [GL-GRAAL] | Tool/configuration identity and scope |
| `analysis.normalization_loss_count` | Required fields absent after a transformation | [EC-PARSER] [EC-BIB] | Separate intentional exclusion and unsupported field |
| `references.repository_mentions` | Qualified repository mentions in a defined source population | [CR-CONFIG] | Not a verified dependency count |
| `criticality.external_indicator` | Imported indicator with its original configuration and input dates | [CR-SCORER] [CR-CONFIG] | Importance, not health; historical freshness |

This crosswalk intentionally includes data-quality and operational measurements alongside project measurements. A large observatory must know the condition of its own evidence before interpreting the condition of the projects it observes.

<a id="appendix-c-proposed-conformance-fixture-catalog"></a>

## Appendix C. Proposed conformance-fixture catalog

The following **48 cases are proposed integration fixtures**. They are not all implemented by the companion script. The executed subset is documented separately in Appendix D.

| ID | Fixture | Required invariant |
|---|---|---|
| F01 | The same event arrives twice on one page | Logical event count is unchanged |
| F02 | An event appears on two overlapping pages | Pagination overlap does not duplicate activity |
| F03 | Collection fails after fetching but before persistence | Next run can recover the event |
| F04 | Worker lease expires and another worker completes | Old worker cannot overwrite the newer generation |
| F05 | An update occurs during a long collection | Start-watermark overlap can recover the update |
| F06 | Source backdates an event | Reconciliation and coverage expose the limitation |
| F07 | Source returns a rate limit | Project metrics do not become negative or zero |
| F08 | Source requires unavailable authorization | Result is unauthorized or unavailable, not false |
| F09 | A generic Git host has no issue API | Issue metrics remain unsupported without health penalty |
| F10 | A repository is renamed on the same host | Stable source identity and historical aliases are preserved |
| F11 | A repository moves to a different host | Migration is an evidence-backed relation, not automatic identity erasure |
| F12 | Two hosts contain identical owner/repository names | Their source namespaces remain distinct |
| F13 | A mirror and original expose the same commits | Raw source events remain traceable; project counts deduplicate by policy |
| F14 | A fork develops independent releases | It can become a separate project family through an explicit assertion |
| F15 | One repository publishes several packages | Project-level adoption does not multiply blindly |
| F16 | One package points to an issue tracker rather than source | Relation type is preserved; no false source mapping |
| F17 | A provider mapping response reaches its cap | Completeness is not claimed |
| F18 | A cached top-dependent list is returned | Population is labeled bounded or selected |
| F19 | A dependency requirement is a range | No exact installed version is invented |
| F20 | A lockfile includes direct and transitive entries | Document kind does not determine directness |
| F21 | An optional dependency lacks a flag after normalization | Unknown is not converted to false |
| F22 | Integrity fields are dropped by a service | Loss is reported and no verification claim is made |
| F23 | Unsupported archive format yields an empty list | Unsupported is not a successful zero-dependency snapshot |
| F24 | Successful parse returns no dependencies | Current projection clears only the covered scope |
| F25 | A parse fails after a successful earlier snapshot | Old evidence is retained as stale, not freshly verified |
| F26 | Same input bytes are parsed by a new tool version | Cache identity includes transformation version |
| F27 | Graph contains a diamond | Unique dependency counts do not count paths |
| F28 | Graph contains a cycle returning to the root | Traversal terminates and root treatment is explicit |
| F29 | Same package version occurs in two graph positions | Resolution instances remain distinct |
| F30 | Provider graph and local lockfile use different environments | Difference is explained by context where supported |
| F31 | Two account identities merge | Actor counts change, event counts do not |
| F32 | An identity merge is reversed | Historical current-corrected metrics can be rebuilt |
| F33 | A person changes affiliation | Old activity is not assigned to the new organization automatically |
| F34 | Unknown affiliation endpoints use sentinel dates | Sentinels do not become factual employment dates |
| F35 | One contributor performs all activity | Concentration includes the crossing contributor |
| F36 | Equal counts straddle a role threshold | Tie behavior is stable and documented |
| F37 | Empty activity population | Concentration is undefined with observed emptiness |
| F38 | Many events occur on one day | Repeat count does not become sustained duration |
| F39 | Recent contributors lack follow-up time | They are excluded from an ineligible retention denominator |
| F40 | Historical coverage begins late | First observed contribution is not labeled first-ever |
| F41 | Author and committer differ | One commit can have multiple roles without becoming two commits |
| F42 | A relational join multiplies rows | Metric cardinality fixtures detect the error |
| F43 | The same Scorecard run arrives through three providers | One origin assessment, three delivery paths |
| F44 | A true probe describes an undesirable condition | Outcome polarity is interpreted from the probe contract |
| F45 | A check is inconclusive or omitted from a public feed | It is not averaged as zero or treated as failed |
| F46 | A formula has missing inputs | Coverage and denominator treatment remain visible |
| F47 | A metric definition changes | Source change and definition change are distinguishable |
| F48 | A contributor requests a justified identity correction or suppression | Evidence governance and affected projections follow the defined workflow |

A fixture should include the input objects, expected canonical entities, expected metric observations, and expected statuses. The same fixture can then be used against several adapters or implementation languages. That is a more durable compatibility test than comparing screenshots.

<a id="appendix-d-executed-synthetic-examples-and-interpretation"></a>

## Appendix D. Executed synthetic examples and interpretation

The companion script uses only the Python standard library and performs no network requests. It is intended to run with Python 3.10 or later:

```bash
python validation_examples.py --output VALIDATION_RESULTS.json
```

The following table summarizes the results generated for this review. All entities and quantities are synthetic.

| Executed check | Result | What it establishes |
|---|---|---|
| Join cardinality | Self-equality example: 6 combinations; explicit foreign-key join: 2 | A local illustration of join multiplication, not a deployed CollectOSS result |
| Count burstiness moments | Poisson count means 1, 4, 16 give 0, −1/3, −0.6 under the stated formula | The formula's interpretation depends on the measured domain |
| Ending-percentile onion boundary | Sole contributor maps to the last interval; covering-set K80 is 1 | Ending cumulative position differs from a minimal covering set |
| Eligible retention denominator | 2 returns among 4 eligible contributors = 50%; naïve denominator gives 25% | Recent ineligible cohort members must not dilute retention |
| Event count versus duration | 6 events in 1 active month | Repetition does not establish a year of persistence |
| Diamond deduplication | 3 unique upstream nodes across 4 edges | Reachability count is not path or edge count |
| Cycle termination | 2 unique dependencies excluding the root | A visited-set traversal terminates under the fixture's cycle |
| Resolution-instance identity | 3 instances, 2 unique package-version labels | Global version identity and graph-local instance identity differ |
| Identity merge/split | Actor groups: 3 → 2 → 3; events remain 4 | Correction changes grouping without rewriting source events |
| Shared evidence lineage | 3 deliveries, 1 origin assessment | Repeated aggregation does not create independent corroboration |
| Collection-start watermark | Mid-collection event is covered by start overlap, not completion cursor | Completion-time advancement can skip a late-observed event in the model |
| Failure versus empty snapshot | Failure preserves old list; successful empty result clears it | Payload emptiness is not enough to determine update semantics |
| Available-input mean | Mean 1.0 with 50% input coverage | A maximum observed mean is compatible with incomplete evidence |
| Typed missingness | False, unavailable, and error remain distinct | Null-like conditions require tagged states |
| Project-family deduplication | 4 repository representations, 3 declared families | Raw repository count and family count are different units |
| Partial downstream summary | Known-population mean 15.0 at 50% coverage | Unknown projects are not imputed as zero |

**Result:** 16 passed, 0 failed for the original miniature tests. The generated JSON contains the per-test details. This result does not validate all proposed fixture cases, prove upstream defects, or establish the correctness of a future repo-health implementation.

<a id="appendix-e-source-register-and-reproducibility-notes"></a>

## Appendix E. Source register and reproducibility notes

### E.1 How to read the register

Each identifier below links to a primary repository file, official service page, or the local repo-health baseline. The machine-readable companion register includes the repository revision where recorded, the returned file-object SHA where available, the inspected ranges, the evidence class, and the access date.

A default-branch source is explicitly distinguished from a commit-pinned source. A file-object SHA is not used as if it were a repository commit. Short search excerpts are labeled as such, and documentation-only reviews are not represented as implementation audits.

The bundle does not contain a complete archive of the upstream repositories or their dependency trees. Reproducing the static review requires retrieving the cited revisions or file objects, and reproducing a deployment would require additional environment and dependency work. The synthetic examples are self-contained and reproducible independently of those upstream services.

### E.2 Source inventory

**[RH-ARCH] — `Architecture.md`.** User-approved proposed repo-health architecture; local baseline. Evidence class: `project_requirement`. Inspected scope: complete structure and selected relevant sections. Local SHA-256: `70389e38101868c605a90f14409393a9c9f4c9e6b5668d1e64d6cd615eb7dde6`. Access date: 2026-09-19.

**[RH-PLAN] — `IMPLEMENTATION_PLAN.md`.** Proposed repo-health implementation plan; local baseline. Evidence class: `project_requirement`. Inspected scope: milestone map and selected implementation sections. Local SHA-256: `4a121de160de09ab20503023426bf01b547bfc1465c8162c5696b4d3209b0911`. Access date: 2026-09-19.

**[CH-CAF] — `chaoss/wg-risk/focus-areas/business-risk/contributor-absence-factor.md`.** Contributor concentration at 50 percent; contribution types and project scope. Evidence class: `metric_specification`. Read from the default branch at access; not claimed to be commit-pinned. File-object SHA: `c75ee8456b57f4285db29de45f43661acd8d008f`. Inspected scope: full returned file. Access date: 2026-09-19.

**[CH-OCC] — `chaoss/wg-metrics-development/focus-areas/people/occasional-contributors.md`.** Occasional participation, thresholds, intervals, and contextual interpretation. Evidence class: `metric_specification`. Read from the default branch at access; not claimed to be commit-pinned. File-object SHA: `ed37f616a9931b1971c7bde6738b3d4c8c77baa8`. Inspected scope: full returned file. Access date: 2026-09-19.

**[CH-UP] — `chaoss/wg-risk/focus-areas/dependency-risk-assessment/upstream-code-dependencies.md`.** Dependency scope, versions, cycles and sustainability interpretation. Evidence class: `metric_specification`. Read from the default branch at access; not claimed to be commit-pinned. File-object SHA: `dda20d868c3a05c44c4b94fda1e31f5fffd5bc7b`. Inspected scope: full returned file. Access date: 2026-09-19.

**[CH-MET] — `chaoss/wg-metrics-development/README.md`.** Metric development process and document-license statement. Evidence class: `repository_documentation`. Read from the default branch at access; not claimed to be commit-pinned. File-object SHA: `f1f3b7ba31b86cf5a939f0349e0dd565971b7559`. Inspected scope: full returned file. Access date: 2026-09-19.

**[CH-SOFT] — Official descriptions of CHAOSS software; not an independent implementation benchmark.** Official descriptions of CHAOSS software; not an independent implementation benchmark. Evidence class: `primary_documentation`. Access date: 2026-09-19.

**[AV-README] — `aveloxis/aveloxis/README.md`.** Project scope and deployment description. Evidence class: `repository_documentation`. Read from the default branch at access; not claimed to be commit-pinned. File-object SHA: `487eca214f5697fda11ad9b791a109a035057174`. Inspected scope: 1–260. Access date: 2026-09-19.

**[AV-ARCH] — `aveloxis/aveloxis/docs/architecture/overview.md`.** Staging, processing, platform abstractions, components, and database organization. Evidence class: `architecture_documentation`. Repository revision: `c601149638ea5b62a8bbbd6269eb90e5ab2ae581`. Inspected scope: returned architecture overview; long response partially truncated. Access date: 2026-09-19.

**[AV-QUEUE] — `aveloxis/aveloxis/internal/db/queue.go`.** Atomic job claiming and successful collection-start cursor advancement. Evidence class: `source_code`. Repository revision: `c601149638ea5b62a8bbbd6269eb90e5ab2ae581`. File-object SHA: `3160e63e24d047b93965c76432c339e9439d5558`. Inspected scope: 1–230. Access date: 2026-09-19.

**[AV-BREADTH] — `aveloxis/aveloxis/internal/collector/breadth.go`.** Cross-repository contributor discovery, coordinator persistence, retry boundaries. Evidence class: `source_code`. Repository revision: `c601149638ea5b62a8bbbd6269eb90e5ab2ae581`. File-object SHA: `702644616eaa6858b5cb8c3036658dd68b4601ca`. Inspected scope: 1–220. Access date: 2026-09-19.

**[AV-MET] — `aveloxis/aveloxis/docs/guide/metrics.md`.** Metric catalog; retention threshold; bucketed burstiness; runtime dependencies. Evidence class: `metric_documentation`. Repository revision: `c601149638ea5b62a8bbbd6269eb90e5ab2ae581`. File-object SHA: `e0e63cb32a734dc8c3d661c5da0547bdde00f373`. Inspected scope: full returned file. Access date: 2026-09-19.

**[AV-ANALYSIS] — `aveloxis/aveloxis/docs/architecture/analysis.md`.** Temporary checkouts, dependency scanning, libyear, transactional history replacement. Evidence class: `architecture_documentation`. Repository revision: `c601149638ea5b62a8bbbd6269eb90e5ab2ae581`. File-object SHA: `83ace1485ba13e7d39222d21b6a055709e11d038`. Inspected scope: full returned file. Access date: 2026-09-19.

**[CO-README] — `chaoss/CollectOSS/README.md`.** Relational community collection, production release branch, MIT declaration. Evidence class: `repository_documentation`. Read from the default branch at access; not claimed to be commit-pinned. File-object SHA: `983fdfe66e57c37760ddf6a6e1744ac9d429f9d6`. Inspected scope: full returned file. Access date: 2026-09-19.

**[CO-MET] — `chaoss/CollectOSS/collectoss/api/metrics/contributor.py`.** Registered contributor metrics and SQL aggregation; join condition examined. Evidence class: `source_code`. Repository revision: `274301dc8da04ae17f6de851ecaad6185a0e0d42`. File-object SHA: `4dbc35e8f0b514d49c1e2e361af3aa2b53fd4f44`. Inspected scope: 1–210. Access date: 2026-09-19.

**[CO-DEPLOY] — `chaoss/CollectOSS/docker-compose.yml`.** PostgreSQL, Redis, keyman, RabbitMQ, core and optional monitoring. Evidence class: `deployment_configuration`. Repository revision: `274301dc8da04ae17f6de851ecaad6185a0e0d42`. File-object SHA: `e86e284275718fd02af32a6a7856a59b1f52508e`. Inspected scope: 1–220. Access date: 2026-09-19.

**[CO-BREADTH] — `chaoss/CollectOSS/collectoss/tasks/data_analysis/contributor_breadth_worker/contributor_breadth_worker.py`.** GitHub event-based contributor breadth, native IDs, provenance, incremental cutoff. Evidence class: `source_code`. Repository revision: `274301dc8da04ae17f6de851ecaad6185a0e0d42`. File-object SHA: `5f5aff7676a1f2a8b46eae80a8cd54fcff5a1581`. Inspected scope: full returned file. Access date: 2026-09-19.

**[GL-README] — `chaoss/grimoirelab/README.md`.** Toolkit architecture, deployment and bibliography pointer. Evidence class: `repository_documentation`. Read from the default branch at access; not claimed to be commit-pinned. File-object SHA: `dab4c82946a33452499bc462aa2ed55cdae101d0`. Inspected scope: 1–240. Access date: 2026-09-19.

**[GL-MODULES] — `chaoss/grimoirelab/.gitmodules`.** Canonical component repository identities, including SirMordred. Evidence class: `repository_configuration`. Read from the default branch at access; not claimed to be commit-pinned. File-object SHA: `7166ab3c5bb0f7f351e72cbd01483b8d08a43d76`. Inspected scope: full returned file. Access date: 2026-09-19.

**[GL-PERCEVAL] — `chaoss/grimoirelab-perceval/perceval/backend.py`.** Backend capabilities, envelope metadata, summaries, archives and redaction incompatibility. Evidence class: `source_code`. Repository revision: `a06f083bf9778d153634621fda23e407f085a246`. File-object SHA: `f58e140d0b8c23a3db30c457bcd837b3252a2795`. Inspected scope: 1–230; 260–450. Access date: 2026-09-19.

**[GL-SH-README] — `chaoss/grimoirelab-sortinghat/README.md`.** Identity versus individual and time-bounded affiliation model. Evidence class: `repository_documentation`. Read from the default branch at access; not claimed to be commit-pinned. File-object SHA: `bd9dd7509b86c8e9df8797f2a6ddac6d7c12887c`. Inspected scope: 1–190. Access date: 2026-09-19.

**[GL-SH-MODEL] — `chaoss/grimoirelab-sortinghat/sortinghat/core/models.py`.** Identities, enrollments, merge recommendations, operations and transactions. Evidence class: `source_code`. Repository revision: `b3fbfd05b415368e5e4e2675d76ee7868f920bce`. File-object SHA: `0e2490b9b760f332a7dd447c434764540335d167`. Inspected scope: 1–430. Access date: 2026-09-19.

**[GL-SH-SPLIT] — `chaoss/grimoirelab-sortinghat/sortinghat/core/api.py`.** Atomic identity-unmerge entry point; not a full implementation audit. Evidence class: `source_search_excerpt`. Repository revision: `b3fbfd05b415368e5e4e2675d76ee7868f920bce`. Inspected scope: unmerge_identities search excerpt. Access date: 2026-09-19.

**[GL-ONION] — `chaoss/grimoirelab-elk/grimoire_elk/enriched/study_ceres_onion.py`.** Quarter/project/organization study and explicit nonincremental implementation. Evidence class: `source_code`. Repository revision: `f878e4a6b1d5eb4155bf0afbeb575b4b1bcf87df`. File-object SHA: `e4835c9f9b9002af0fc8021e857c5834b1c9f4ae`. Inspected scope: 1–240. Access date: 2026-09-19.

**[GL-CERES] — `chaoss/grimoirelab-cereslib/cereslib/enrich/enrich.py`.** Composable enrichments and cumulative-percentile Onion classifier. Evidence class: `source_code`. Repository revision: `ff6488227adfa6eb3b8093d57c5fd57419243846`. File-object SHA: `137e4e6c9beecb1b16529b2538f5bda8161d2216`. Inspected scope: 1–220; 380–570; 650–end. Access date: 2026-09-19.

**[GL-GRAAL] — `chaoss/grimoirelab-graal/README.md`.** Historical checkout analysis and external-tool hooks; installation examples not validated. Evidence class: `repository_documentation`. Read from the default branch at access; not claimed to be commit-pinned. File-object SHA: `f9f46b69f82701a6e11e7b173d1ca25ed96edb12`. Inspected scope: 1–185. Access date: 2026-09-19.

**[GL-MORDRED] — `chaoss/grimoirelab-sirmordred/README.md`.** Independent collection/enrichment phases and nested source-to-project grouping. Evidence class: `repository_documentation`. Read from the default branch at access; not claimed to be commit-pinned. File-object SHA: `a3cd5ebb9710362b8b029af5d75c0c06886a66f2`. Inspected scope: 1–200. Access date: 2026-09-19.

**[EC-REPO] — `ecosyste-ms/repos/app/models/repository.rb`.** Scheduling, selective enrichment, dependency parsing, manifests and snapshot updates. Evidence class: `source_code`. Repository revision: `dbd45a85b8653f44e19bec18563987a00410a8a0`. File-object SHA: `3dce28b7705002c8fadd5ec225e1ad8731d9d4f9`. Inspected scope: 1–425. Access date: 2026-09-19.

**[EC-HOST] — `ecosyste-ms/repos/app/models/host.rb`.** Host identity, repository reconciliation, approximate counts and request failure states. Evidence class: `source_code`. Repository revision: `dbd45a85b8653f44e19bec18563987a00410a8a0`. File-object SHA: `1210873179495293c441c968ae3e4f5abddb1b44`. Inspected scope: 1–205. Access date: 2026-09-19.

**[EC-DEP] — `ecosyste-ms/packages/app/models/dependency.rb`.** Version-scoped dependency declarations and optional resolved package association. Evidence class: `source_code`. Repository revision: `601562d9302ca540dac6002ff1f78b0a9e6b2130`. File-object SHA: `b6b17eabf86c193e05e39d2043d4c8678eb71c49`. Inspected scope: full returned file. Access date: 2026-09-19.

**[EC-PKG-API] — `ecosyste-ms/packages/app/controllers/api/v1/packages_controller.rb`.** Package lookup, latest/historical dependents, cached lists and response provenance. Evidence class: `source_code`. Repository revision: `601562d9302ca540dac6002ff1f78b0a9e6b2130`. File-object SHA: `ff9e6dfb9e95476d0fe7b9fb552f47aa92feb365`. Inspected scope: 1–235. Access date: 2026-09-19.

**[EC-PKG-REL] — `ecosyste-ms/packages/app/models/package.rb`.** Historical version-to-package reverse dependency projection. Evidence class: `source_search_excerpt`. Repository revision: `601562d9302ca540dac6002ff1f78b0a9e6b2130`. Inspected scope: dependent_packages implementation excerpt. Access date: 2026-09-19.

**[EC-PARSER-DOC] — `ecosyste-ms/parser/README.md`.** Parser service scope and separate code/data license declarations. Evidence class: `repository_documentation`. Read from the default branch at access; not claimed to be commit-pinned. File-object SHA: `872e52a25c6e68b041562bd127a6e81a767ae964`. Inspected scope: full returned file. Access date: 2026-09-19.

**[EC-PARSER] — `ecosyste-ms/parser/app/models/job.rb`.** Content-hash reuse, asynchronous parsing, output normalization and extraction boundary. Evidence class: `source_code`. Repository revision: `6a251ef298389fbf35c66698f2fd20b9c5ff884c`. File-object SHA: `242e328d436ae06f9afe43f67d4e294acbb3641a`. Inspected scope: 1–235. Access date: 2026-09-19.

**[EC-BIB] — `ecosyste-ms/bibliothecary/README.md`.** Manifest discovery, dependency fields, integrity data and format catalog. Evidence class: `repository_documentation`. Read from the default branch at access; not claimed to be commit-pinned. File-object SHA: `bc53e35aca881d4f40a279da9ee171a18e5b8ccc`. Inspected scope: 1–205. Access date: 2026-09-19.

**[EC-DASH] — `ecosyste-ms/dashboards/README.md`.** Presentation service and code/data license declaration. Evidence class: `repository_documentation`. Read from the default branch at access; not claimed to be commit-pinned. File-object SHA: `5f59dcc9f9075d74577a859ca028820f21003a8c`. Inspected scope: full returned file. Access date: 2026-09-19.

**[EC-COMMITS] — `ecosyste-ms/commits/README.md`.** Commit-metadata service; no detailed coverage or implementation audit. Evidence class: `repository_documentation`. Read from the default branch at access; not claimed to be commit-pinned. File-object SHA: `94ab018909704733314c836e5d96367003b20dd8`. Inspected scope: full returned file. Access date: 2026-09-19.

**[EC-ISSUES] — `ecosyste-ms/issues/README.md`.** Issue and pull-request metadata service; no detailed implementation audit. Evidence class: `repository_documentation`. Read from the default branch at access; not claimed to be commit-pinned. File-object SHA: `9079f9875280bede01ba68f06107df35edf3859d`. Inspected scope: full returned file. Access date: 2026-09-19.

**[EC-REPOS-WEB] — Repository service scope, provider inventory and displayed aggregate counters.** Repository service scope, provider inventory and displayed aggregate counters. Evidence class: `primary_documentation`. Access date: 2026-09-19.

**[EC-PACKAGES-WEB] — Package service and registry inventory.** Package service and registry inventory. Evidence class: `primary_documentation`. Access date: 2026-09-19.

**[DD-README] — `google/deps.dev/README.md`.** Public repository scope, services, examples, data and caching terms. Evidence class: `repository_documentation`. Read from the default branch at access; not claimed to be commit-pinned. File-object SHA: `78acc56674fe87bc830bd016821c3a760e80b0ea`. Inspected scope: 1–215. Access date: 2026-09-19.

**[DD-PROTO] — `google/deps.dev/api/v3/api.proto`.** Stable service contract, environment assumptions, keys and provenance fields. Evidence class: `source_interface`. Repository revision: `fe0055f3c59851339332b4bc435837a459b19049`. File-object SHA: `f8251b01c733d60df87b054f1c1e0eda208559f3`. Inspected scope: 1–250. Access date: 2026-09-19.

**[DD-RESOLVE] — `google/deps.dev/util/resolve/resolve.go`.** Client/Resolver separation, concrete versus requirement versions and key ordering. Evidence class: `source_code`. Repository revision: `fe0055f3c59851339332b4bc435837a459b19049`. File-object SHA: `e1bf97b0fe91a2d26cf1d4b949b6c99e3015143d`. Inspected scope: 1–230. Access date: 2026-09-19.

**[DD-GRAPH] — `google/deps.dev/util/resolve/graph.go`.** Graph-local node IDs, dependency edges, graph/node errors and canonicalization. Evidence class: `source_code`. Repository revision: `fe0055f3c59851339332b4bc435837a459b19049`. File-object SHA: `d4af157b155fe7ee903ab57abb709ba34e69ad29`. Inspected scope: 1–235. Access date: 2026-09-19.

**[DD-SEMVER] — `google/deps.dev/util/semver/README.md`.** Ecosystem-specific version parsing and constraint matching. Evidence class: `repository_documentation`. Repository revision: `fe0055f3c59851339332b4bc435837a459b19049`. File-object SHA: `502786a36c580957d4526e55e11ce89bf29f94a6`. Inspected scope: full returned file. Access date: 2026-09-19.

**[DD-API] — Stable API semantics, coverage, graph nodes, mapping limits and provenance.** Stable API semantics, coverage, graph nodes, mapping limits and provenance. Evidence class: `primary_documentation`. Access date: 2026-09-19.

**[SC-README] — `ossf/scorecard/README.md`.** Structured results, heuristic limitations, public scan omissions and data license. Evidence class: `repository_documentation`. Read from the default branch at access; not claimed to be commit-pinned. File-object SHA: `5f290d6372cad5a32d51d77bdda4ed8b22288b4c`. Inspected scope: 1–245. Access date: 2026-09-19.

**[SC-FINDING] — `ossf/scorecard/finding/finding.go`.** Typed outcomes, probe identity, evidence locations and remediation. Evidence class: `source_code`. Repository revision: `f92023a3f77879f96e0c9c1305f289d755be4bb6`. File-object SHA: `71b338a75f9580f4b9b5aaa68e9d629990d729a4`. Inspected scope: 1–210. Access date: 2026-09-19.

**[SC-RESULT] — `ossf/scorecard/checker/check_result.go`.** Versioned check result, inconclusive sentinel and proportional score handling. Evidence class: `source_code`. Repository revision: `f92023a3f77879f96e0c9c1305f289d755be4bb6`. File-object SHA: `79993e6ee08254b12aa08e4711b1f89fca3c6728`. Inspected scope: 1–205. Access date: 2026-09-19.

**[SC-MAINT] — `ossf/scorecard/checks/maintained.go`.** Raw collection to probes to evaluation orchestration. Evidence class: `source_code`. Repository revision: `f92023a3f77879f96e0c9c1305f289d755be4bb6`. File-object SHA: `9bcdf6c42e8c77c551fc7bf62abd063f65a8e6f2`. Inspected scope: full returned file. Access date: 2026-09-19.

**[SC-RAW] — `ossf/scorecard/checks/raw/maintained.go`.** Archived state, commits, issues and creation date collection. Evidence class: `source_code`. Repository revision: `f92023a3f77879f96e0c9c1305f289d755be4bb6`. File-object SHA: `9af1230c21abd10759fad71ae44bf487fb612018`. Inspected scope: full returned file. Access date: 2026-09-19.

**[SC-WRITE] — `ossf/scorecard/checks/write.md`.** Check contribution process, correction, fixtures and generated documentation. Evidence class: `contributor_documentation`. Repository revision: `f92023a3f77879f96e0c9c1305f289d755be4bb6`. File-object SHA: `2a517daa696cfaaf37ed8461179a0ee4f9bbe2bf`. Inspected scope: full returned file. Access date: 2026-09-19.

**[CR-README] — `ossf/criticality_score/README.md`.** Operational shutdown notice, legacy signals, CLI and scoring scope. Evidence class: `repository_documentation`. Read from the default branch at access; not claimed to be commit-pinned. File-object SHA: `a1d182bf8f2d8ff16cb7a24f47677c043fc7b8f0`. Inspected scope: full returned file. Access date: 2026-09-19.

**[CR-CONFIG] — `ossf/criticality_score/config/scorer/original_pike.yml`.** Explicit weights, bounds, transformations and actual signal names. Evidence class: `source_configuration`. Repository revision: `0e76c6a99d865dddcbd89dff4117f0a54b1abfb8`. File-object SHA: `f2a1563dabe3b2dc2c1a2f701bb4229c0d161787`. Inspected scope: full returned file. Access date: 2026-09-19.

**[CR-SCORER] — `ossf/criticality_score/internal/scorer/scorer.go`.** Configurable recomputation and numeric parsing semantics. Evidence class: `source_code`. Repository revision: `0e76c6a99d865dddcbd89dff4117f0a54b1abfb8`. File-object SHA: `c720207b055c49249c26a5f0b44c281a4d748511`. Inspected scope: 1–220. Access date: 2026-09-19.

**[CR-WAM] — `ossf/criticality_score/internal/scorer/algorithm/wam/wam.go`.** Weighted mean over available transformed inputs. Evidence class: `source_code`. Repository revision: `0e76c6a99d865dddcbd89dff4117f0a54b1abfb8`. File-object SHA: `9773df9536eeec1abd3caf5924a3284136725c4b`. Inspected scope: full returned file. Access date: 2026-09-19.

**[CR-OPS] — Maintainer operational notice concerning infrastructure retirement; read as an attributed operational report.** Maintainer operational notice concerning infrastructure retirement; read as an attributed operational report. Evidence class: `primary_documentation`. Access date: 2026-09-19.

### E.3 Important boundaries on reuse of this paper

The proposed schemas, metric names, policies, and roadmap changes are design recommendations. They are not statements of existing repo-health functionality. The code concerns discussed in the source chapters are qualified static observations or miniature mathematical examples unless explicitly stated otherwise.

Before adopting an upstream component, refresh the source review, select a supported release, verify its license and data terms for the intended use, run the relevant conformance fixtures, and document who will maintain the adapter. The most valuable output of this paper is not a fixed list of dependencies, but a disciplined way to reuse them without losing the meaning of their evidence.

[RH-ARCH]: Architecture.md
[RH-PLAN]: IMPLEMENTATION_PLAN.md
[CH-CAF]: https://github.com/chaoss/wg-risk/blob/main/focus-areas/business-risk/contributor-absence-factor.md
[CH-OCC]: https://github.com/chaoss/wg-metrics-development/blob/main/focus-areas/people/occasional-contributors.md
[CH-UP]: https://github.com/chaoss/wg-risk/blob/main/focus-areas/dependency-risk-assessment/upstream-code-dependencies.md
[CH-MET]: https://github.com/chaoss/wg-metrics-development/blob/main/README.md
[CH-SOFT]: https://www.chaoss.community/software/
[AV-README]: https://github.com/aveloxis/aveloxis/blob/main/README.md
[AV-ARCH]: https://github.com/aveloxis/aveloxis/blob/c601149638ea5b62a8bbbd6269eb90e5ab2ae581/docs/architecture/overview.md
[AV-QUEUE]: https://github.com/aveloxis/aveloxis/blob/c601149638ea5b62a8bbbd6269eb90e5ab2ae581/internal/db/queue.go
[AV-BREADTH]: https://github.com/aveloxis/aveloxis/blob/c601149638ea5b62a8bbbd6269eb90e5ab2ae581/internal/collector/breadth.go
[AV-MET]: https://github.com/aveloxis/aveloxis/blob/c601149638ea5b62a8bbbd6269eb90e5ab2ae581/docs/guide/metrics.md
[AV-ANALYSIS]: https://github.com/aveloxis/aveloxis/blob/c601149638ea5b62a8bbbd6269eb90e5ab2ae581/docs/architecture/analysis.md
[CO-README]: https://github.com/chaoss/CollectOSS/blob/main/README.md
[CO-MET]: https://github.com/chaoss/CollectOSS/blob/274301dc8da04ae17f6de851ecaad6185a0e0d42/collectoss/api/metrics/contributor.py
[CO-DEPLOY]: https://github.com/chaoss/CollectOSS/blob/274301dc8da04ae17f6de851ecaad6185a0e0d42/docker-compose.yml
[CO-BREADTH]: https://github.com/chaoss/CollectOSS/blob/274301dc8da04ae17f6de851ecaad6185a0e0d42/collectoss/tasks/data_analysis/contributor_breadth_worker/contributor_breadth_worker.py
[GL-README]: https://github.com/chaoss/grimoirelab/blob/main/README.md
[GL-MODULES]: https://github.com/chaoss/grimoirelab/blob/main/.gitmodules
[GL-PERCEVAL]: https://github.com/chaoss/grimoirelab-perceval/blob/a06f083bf9778d153634621fda23e407f085a246/perceval/backend.py
[GL-SH-README]: https://github.com/chaoss/grimoirelab-sortinghat/blob/main/README.md
[GL-SH-MODEL]: https://github.com/chaoss/grimoirelab-sortinghat/blob/b3fbfd05b415368e5e4e2675d76ee7868f920bce/sortinghat/core/models.py
[GL-SH-SPLIT]: https://github.com/chaoss/grimoirelab-sortinghat/blob/b3fbfd05b415368e5e4e2675d76ee7868f920bce/sortinghat/core/api.py
[GL-ONION]: https://github.com/chaoss/grimoirelab-elk/blob/f878e4a6b1d5eb4155bf0afbeb575b4b1bcf87df/grimoire_elk/enriched/study_ceres_onion.py
[GL-CERES]: https://github.com/chaoss/grimoirelab-cereslib/blob/ff6488227adfa6eb3b8093d57c5fd57419243846/cereslib/enrich/enrich.py
[GL-GRAAL]: https://github.com/chaoss/grimoirelab-graal/blob/main/README.md
[GL-MORDRED]: https://github.com/chaoss/grimoirelab-sirmordred/blob/main/README.md
[EC-REPO]: https://github.com/ecosyste-ms/repos/blob/dbd45a85b8653f44e19bec18563987a00410a8a0/app/models/repository.rb
[EC-HOST]: https://github.com/ecosyste-ms/repos/blob/dbd45a85b8653f44e19bec18563987a00410a8a0/app/models/host.rb
[EC-DEP]: https://github.com/ecosyste-ms/packages/blob/601562d9302ca540dac6002ff1f78b0a9e6b2130/app/models/dependency.rb
[EC-PKG-API]: https://github.com/ecosyste-ms/packages/blob/601562d9302ca540dac6002ff1f78b0a9e6b2130/app/controllers/api/v1/packages_controller.rb
[EC-PKG-REL]: https://github.com/ecosyste-ms/packages/blob/601562d9302ca540dac6002ff1f78b0a9e6b2130/app/models/package.rb
[EC-PARSER-DOC]: https://github.com/ecosyste-ms/parser/blob/main/README.md
[EC-PARSER]: https://github.com/ecosyste-ms/parser/blob/6a251ef298389fbf35c66698f2fd20b9c5ff884c/app/models/job.rb
[EC-BIB]: https://github.com/ecosyste-ms/bibliothecary/blob/main/README.md
[EC-DASH]: https://github.com/ecosyste-ms/dashboards/blob/main/README.md
[EC-COMMITS]: https://github.com/ecosyste-ms/commits/blob/main/README.md
[EC-ISSUES]: https://github.com/ecosyste-ms/issues/blob/main/README.md
[EC-REPOS-WEB]: https://repos.ecosyste.ms/
[EC-PACKAGES-WEB]: https://packages.ecosyste.ms/
[DD-README]: https://github.com/google/deps.dev/blob/main/README.md
[DD-PROTO]: https://github.com/google/deps.dev/blob/fe0055f3c59851339332b4bc435837a459b19049/api/v3/api.proto
[DD-RESOLVE]: https://github.com/google/deps.dev/blob/fe0055f3c59851339332b4bc435837a459b19049/util/resolve/resolve.go
[DD-GRAPH]: https://github.com/google/deps.dev/blob/fe0055f3c59851339332b4bc435837a459b19049/util/resolve/graph.go
[DD-SEMVER]: https://github.com/google/deps.dev/blob/fe0055f3c59851339332b4bc435837a459b19049/util/semver/README.md
[DD-API]: https://docs.deps.dev/api/v3/
[SC-README]: https://github.com/ossf/scorecard/blob/main/README.md
[SC-FINDING]: https://github.com/ossf/scorecard/blob/f92023a3f77879f96e0c9c1305f289d755be4bb6/finding/finding.go
[SC-RESULT]: https://github.com/ossf/scorecard/blob/f92023a3f77879f96e0c9c1305f289d755be4bb6/checker/check_result.go
[SC-MAINT]: https://github.com/ossf/scorecard/blob/f92023a3f77879f96e0c9c1305f289d755be4bb6/checks/maintained.go
[SC-RAW]: https://github.com/ossf/scorecard/blob/f92023a3f77879f96e0c9c1305f289d755be4bb6/checks/raw/maintained.go
[SC-WRITE]: https://github.com/ossf/scorecard/blob/f92023a3f77879f96e0c9c1305f289d755be4bb6/checks/write.md
[CR-README]: https://github.com/ossf/criticality_score/blob/main/README.md
[CR-CONFIG]: https://github.com/ossf/criticality_score/blob/0e76c6a99d865dddcbd89dff4117f0a54b1abfb8/config/scorer/original_pike.yml
[CR-SCORER]: https://github.com/ossf/criticality_score/blob/0e76c6a99d865dddcbd89dff4117f0a54b1abfb8/internal/scorer/scorer.go
[CR-WAM]: https://github.com/ossf/criticality_score/blob/0e76c6a99d865dddcbd89dff4117f0a54b1abfb8/internal/scorer/algorithm/wam/wam.go
[CR-OPS]: https://github.com/ossf/criticality_score/issues/833
