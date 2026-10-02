# Maintainer pilot procedure

Use this procedure for the opt-in empirical stage in the research evaluation
(paper §§20.5 and 21.2–21.5). The pilot is for finding semantic and operational
failures. It is not a representative sample of open source, an audit, or a
maintainer endorsement of a score.

## Before recruiting

Confirm the local deterministic checks pass, the selected source and rights
reviews permit the proposed collection, the privacy and deletion procedures
are ready, and a report can be replayed from its retained inputs. Invite
maintainers to opt in, explain the data collected and the review effort, and
make clear that participation does not publish a personal or project ranking.
Do not contact upstream maintainers through notification delivery.

Choose a small sample across host type, language ecosystem, project age,
release cadence, contributor count, repository structure, and availability of
public collaboration data. Include self-hosted sources, mature low-churn
projects, and projects with different collaboration workflows when feasible.
Keep every selected project in the coverage denominator. Record inaccessible
projects and unavailable capabilities as such; do not silently replace them
with easier-to-observe projects. Describe the sample as a pilot population.

## Review in stages

1. Check acquisition and normalization against known source objects. Retain
   the source snapshot and classify disagreements as snapshot/context
   differences, identity mapping, missing pages, unsupported formats, provider
   estimates, stale caches, or normalization defects.
2. Check metric calculations on controlled fixtures and manually verified
   public examples. Keep the operational definition and evidence in view.
3. Manually check package-to-project mappings, identity merges, role labels,
   and downstream inclusion before asking whether a finding changed a decision.
4. Ask maintainers whether report explanations are understandable and whether
   findings are correct, actionable, and useful. Ask what evidence resolved an
   unknown and how much effort corrections required. Record false alarms and
   missed findings; do not treat agreement with the report as the success
   measure.
5. Exercise a provider outage or stale response. Confirm the affected
   capability becomes stale/unknown or unsupported and that unrelated usable
   capabilities remain available.

## Keep the case ledger private

For each reviewed case, use a pseudonymous case reference and retain the
source snapshot or finding digest needed to reproduce it. Record the sampled
host/ecosystem/project strata, expected and observed mapping, identity-merge
and role-label correctness, downstream inclusion, whether a finding changed a
decision, whether the finding was correct and actionable, what evidence
resolved an unknown, correction outcome, hands-on correction effort, and
turnaround time. Keep active effort separate from elapsed turnaround. Avoid
names, email addresses, and unnecessary contributor-level notes. Store any
mapping from pseudonyms to projects separately with access limited to the
review team.

The `rh_cli pilot-review` record is the bounded aggregate, not the case ledger.
It accepts mapping counts, requested/resolved corrections and median
turnaround, usefulness and false-positive/false-negative counts, one outage
observation, and measured event/byte/time costs. Keep the detailed case ledger
under the pilot's restricted retention policy. Do not infer missing counts as
zero. Record the review scope as a pilot sample and keep the operator-provided
observations distinct from independent verification.

For each completed review, prepare an input with schema
`rh-pilot-review-input/1` and run:

```sh
build/rh_cli pilot-review --input pilot-review-input.json --out pilot-review-result.json
```

Retain the exact input, `pilot-review-result.json`, and its
`pilot-review-result.json.transformations.json` sidecar together. The sidecar
binds the input and normalized output bytes. Record measured events, bytes,
and elapsed milliseconds from the exercised workload; do not substitute
estimates. Keep the private case ledger separate from these aggregate files.

## Closeout

Summarize the sample composition, inaccessible projects, missing capabilities,
correction effort, mistaken mappings/merges, role-label errors, decision
changes, findings that were wrong or unhelpful, resolved unknowns, provider
outage behavior, and measured costs. Preserve limitations and unresolved
systematic misrepresentation. Turn reproducible defects into regression
fixtures or definition changes, then rerun the applicable checks.

Governance review must record the reviewed evidence, unresolved issues, and
approved beta scope before release. A pilot with few errors does not establish
population-wide accuracy or safety; the publication gate still requires
traceable explanations, rights and privacy review, exercised restoration,
honest source coverage, and no unresolved systematic misrepresentation.
