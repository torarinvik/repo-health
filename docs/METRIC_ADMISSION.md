# Metric admission classes and standards crosswalks

Every versioned metric definition declares `measurement_class`:

- `raw` records a source-level observation or an unadjusted tally of source
  records. It does not imply complete source coverage.
- `derived` records a value produced by filtering, joining, grouping,
  arithmetic, or temporal interpretation of evidence.
- `modeled` records a value that depends on an explicit analytical model or
  assumptions. Modeled metrics stay in the experimental group and outside the
  default runtime registry.

The class describes how the reported value is produced. It does not replace
the observation status, denominator, evidence links, or coverage state. A raw
count may still be partial, and a derived value may still be exact for its
stated population.

Definitions may include `standards_crosswalks` when a reviewed external
measurement concept has a meaningful local counterpart. Each mapping records
the upstream source identity and pinning limits, the local metric version and
population, its formula and boundary rules, deliberate differences, and an
interpretation limit. A shared name or threshold alone does not establish
equivalence.

The Contributor Absence Factor mapping is attached to both the canonical
commit-concentration metric and its compatibility alias. The reviewed CHAOSS
file was read from its default branch; the recorded Git blob object ID is
`c75ee8456b57f4285db29de45f43661acd8d008f`, and is not a commit pin. The local
population is qualifying Git commit events in the selected repository and
scan window. Empty populations remain `not_applicable`; the metric describes
event concentration and does not predict project failure after a departure.
`tools/metric-lint.sh` checks each class and mapping against the definition it
describes. `tests/test_metric_admission.sh` includes negative controls for a
missing class and a changed threshold boundary.
