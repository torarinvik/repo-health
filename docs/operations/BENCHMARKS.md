# Local benchmark scope

The checked-in benchmark is a deterministic local regression harness, not a
deployment capacity claim. `tools/bench.sh` writes `rh-bench/2` and
`tools/profile.sh` writes `rh-profile/2`. Both time the process from outside;
the measured interval includes deterministic dataset construction and process
startup. A second execution checks structural determinism, but is not included
as a timing repetition. Timing values are machine-specific and tests assert
structure, not speed.

The current graph workloads are:

| Nodes | Seed | Distribution | Bench stage | Profile stages |
|---:|---:|---|---|---|
| 100 | 42 | uniform | all | graph, query, metrics |
| 1,000 | 42 | uniform | all | graph, query, metrics |
| 10,000 | 7 | uniform | metrics | graph, metrics |
| 1,000 | 17 | long-tail | graph | graph, metrics |
| 1,000 | 23 | central hubs | graph | graph, query |
| 1,000 | 29 | cycle | graph | graph, query |

Each generator attempts `2 * nodes` edges. Uniform selection uses a fixed LCG;
long-tail selection biases destinations toward lower-numbered nodes; the hub
case selects among four central dependencies; and the cycle case creates
deterministic cyclic layers. Digests and exact resulting edge counts are in
each manifest run.

These workloads measure graph construction, reverse traversal on bounded
cases, and indegree concentration. They do not yet represent project histories,
package versions, mirrors, partial source coverage, or historical corrections.
The harness also does not report memory, disk, latency percentiles, external
request budgets, concurrent-job load, or deployment hardware details. Those
measurements remain required before using these results to publish capacity
limits or claim the M10 exit gate.
