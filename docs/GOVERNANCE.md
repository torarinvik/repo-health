# Metric governance and change process (M09/M12)

This document is the process the repository actually enforces through
tests, not an aspiration. Where a rule is tested, the test is named.

## Adding or changing a metric

1. **Definition first.** Author `metrics/definitions/<key>.json` with the
   full contract. A `ratio` must name its numerator and denominator. A
   metric must declare its `raw`, `derived`, or `modeled` class; experimental
   metrics are modeled. A standards relationship belongs in
   `standards_crosswalks` with its source pinning, local population, boundary,
   differences, and interpretation limit. A metric that is not yet
   `implemented` must also carry the admission template (`inputs`, `params`,
   `missing_behavior`, `confounders`). Enforced by `tools/metric-lint.sh` and
   `tests/test_metric_admission.sh`.
2. **Oracle before implementation.** Add a test asserting exact expected
   values (or an invariant) that fails before the implementation exists.
   Oracle/unit values live in the `test_*` binaries; invariants live in
   `src/test_properties.elisa`.
3. **Implementation on the real path.** Wire it into the scan/report path,
   not a fixture-only path. Fixture-only output is a demo, not an
   integration.
4. **Status transitions.** `planned` → `prototype` → `implemented` (→
   `validated`/`released`). A metric is `implemented` only when it is
   computed on the real path and tested. **A `planned` metric must not
   appear in the runtime registry**; enforced by `tests/test_m00.sh`.
5. **Availability.** The reachable set is derived mechanically:
   `reachable == implementation_status == "implemented"`. A not-available
   metric must never be advertised as reachable; enforced by
   `tests/test_profile.sh`.

6. **Performance evidence.** Scaling claims use the deterministic stage
   profile in `tools/profile.sh`; `repo-health` records dataset digests and
   stage names while leaving machine-specific timings as observations,
   enforced by `tests/test_profile_bench.sh`.

## Changing a published metric

- A changed denominator or definition is a **new version**, never a silent
  rewrite of the old one. `coverage.window_completeness` ships `1.0.0`
  (`implemented`) and `2.0.0` (`prototype`) as separate definitions;
  enforced by `src/test_oracles.elisa` (`registry-versioned-distinct`,
  `registry-v2-denominator-differs`, `registry-unknown-version-no-fallback`).
- Results of different versions are not comparable and must not be merged
  under one label.
- A retired metric keeps its history and migration notes; the same
  key+version is never silently reinterpreted.

## Correction and dispute

- Identity/mapping/measurement disputes use the correction workflow in
  `src/rh_correction.elisa`: acceptance advances a revision and supersedes
  targeted derived results; the raw ledger is never rewritten.
- A correction is recorded with who/what/why; a challenged merge recomputes
  and supersedes with audit rather than silently editing prior output.

## Roles and conflicts

- Critical operations (identity merges, privacy/publication decisions,
  access terms, transport security, execution capabilities, predictions)
  require human review; the runbooks in `docs/operations/runbooks.md` are
  the procedures.
- Paid integrations must not change public method or soften findings for a
  sponsor; the same definitions and thresholds apply to everyone.
- Attribution appeals are handled through the source review register
  (`ops/source-review-register.json`) contact field plus the correction
  workflow.
- Core facts and correction access are never paywalled.

## Public limitations

- The release packet (`tools/release-packet.sh`) always states known
  limitations and never presents roadmap as released; `tests/test_release_packet.sh`
  forbids safety/trust verdicts in the generated output.
