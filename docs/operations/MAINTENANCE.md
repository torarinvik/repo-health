# Recurring maintenance schedule (M12)

This schedule turns the M12 maintenance requirement into recurring, reviewable
work. It defines expected reviews; it does not claim that a review has happened.
Record each run, including a missed or blocked run, under `ops/maintenance/`
using the [record guidance](../../ops/maintenance/README.md). Each record should
name the review scope and operator roles, link the evidence and findings, list
follow-up work, and set the next due date. Do not put
credentials or restricted pilot case details in the record.

## Schedule

| Cadence | Review | Evidence to retain |
|---|---|---|
| Every release candidate | Check supported source and format versions, source-rights register entries, dependency review, public contract compatibility, metric-definition changes, migration notes, and the release packet. | Current `ops/source-review-register.json`, `ops/dependency-review.json`, `ops/provider-dependency-review.json`, `ops/public-contracts.json`, migration review, generated packet, and the separately captured local check output. |
| Monthly | Review enabled connectors against their pinned provider documentation, API versions, pagination and rate limits, authorization states, and known format changes. Review direct and transitive dependency updates and security advisories. | Dated connector and dependency review records. Update `ops/provider-dependency-review.json`, `ops/dependency-review.json`, or `ops/source-review-register.json` when evidence changes; record “no change” with the source and review date when it does not. |
| Quarterly | Exercise schema compatibility and migration rollback, complete a backup/restore rehearsal on a clean target, review one metric family for denominator, missingness, evidence, and interpretation validity, and review correction and user-research feedback. | Migration rehearsal output, restore/replay evidence, metric review notes, correction register references, and consented research summary or an explicit “no sessions this quarter” record. |
| On a material change | Review immediately after a provider contract or rights change, a material dependency advisory, a published-result correction, a security incident, or evidence corruption. | The relevant incident or correction record, affected source/contract/metric scope, actions taken, and the follow-up review date. |

For local release evidence, use the commands named by
[`RELEASE.md`](RELEASE.md) and the migration and restore procedures in
[`MIGRATIONS.md`](MIGRATIONS.md) and [`runbooks.md`](runbooks.md). Live
PostgreSQL migration rehearsal is opt-in; when its environment is unavailable,
record it as not performed rather than treating static checks as a live
rehearsal.

## Operator coverage

Track a primary and a secondary qualified operator for release, backup/restore,
credential rotation, source-rights review, and publication correction where
feasible. Review this coverage quarterly and after a maintainer departure.
Keep personal contact details in the access-controlled operations channel, not
in public evidence. An uncovered role remains an operational gap; a runbook or
successful test alone does not establish that a second person can perform the
procedure.

## Missed reviews and closeout

A missed review stays open until completed or explicitly retired with a reason.
For each finding, record impact, an owner role, a due date, and the release or
collection paths affected. Do not convert an unrun review into a passing status
or infer provider compatibility from the absence of incidents. The M12 release
review should include overdue items and operator-coverage gaps alongside the
release packet and limitations statement.
