# Local benchmark scope

The checked-in benchmark is a deterministic local regression harness, not a
deployment capacity claim. `tools/bench.sh` writes `rh-bench/3` and
`tools/profile.sh` writes `rh-profile/3`. Each workload has one untimed warmup
and ten timed fresh-process repetitions. The measured interval includes
process startup and deterministic dataset construction, but excludes compiler
startup. Every repetition must produce byte-identical structural output.
Manifests retain every latency and peak-RSS sample and report median, p95,
maximum, and latency variance. They also report node/edge throughput, successful
and failed repetition counts, and transitive-query truncation rate when the
selected stage runs a query. A failed sample aborts manifest publication. Tests
validate sample counts and outcomes without asserting performance thresholds.

Each manifest also records the source revision, working-tree status, benchmark
binary and harness SHA-256 digests, compiler path/settings and pinned toolchain
revision, OS/architecture/CPU and available memory context, disk capacity/free
space, database applicability, warmup and cache conditions, and the declared
concurrent-job count when `RH_BENCH_CONCURRENT_JOBS` is set. The workload itself
makes zero external requests. OS cache state and other host processes remain
uncontrolled; disk fields describe host context, not workload disk consumption.

The current graph workloads are:

| Nodes | Seed | Distribution | Bench stage | Profile stages |
|---:|---:|---|---|---|
| 100 | 42 | uniform | all | graph, query, metrics |
| 1,000 | 42 | uniform | all | graph, query, metrics |
| 10,000 | 7 | uniform | metrics | graph, metrics |
| 1,000 | 17 | long-tail | graph | graph, metrics |
| 1,000 | 23 | central hubs | graph | graph, query |
| 1,000 | 29 | cycle | graph | graph, query |
| 1,000 | 31 | ecosystem | ecosystem | ecosystem |

Each generator attempts `2 * nodes` edges. Uniform selection uses a fixed LCG;
long-tail selection biases destinations toward lower-numbered nodes; the hub
case selects among four central dependencies; and the cycle case creates
deterministic cyclic layers. Digests and exact resulting edge counts are in
each manifest run.

The ecosystem profile represents each graph node as a package version and
pairs two versions under each of 500 package/project identities. It adds 250
accepted mirror assertions, independent 50% history and review coverage masks,
and dependency edges with scope, platform, introduction, removal, and first
observation fields. Its timed stage runs valid-time and known-time projections,
a runtime/Linux projection, mirror-family grouping, per-metric coverage, and
the correction engine's accepted-correction invalidation and replay path. The
current 1,000-node fixture includes 32 accepted corrections and invalidates 64
derived records. These are controlled synthetic inputs, not claims about real
ecosystem distributions or a production correction history.

These workloads measure graph construction, reverse traversal on bounded
cases, indegree concentration, and the ecosystem projection operations listed
above. They do not yet represent real project histories or replay corrections
across arbitrary historical snapshots. The per-process peak RSS and latency
samples cover only this synthetic graph runner. The harness does not measure
workload disk consumption or latency under controlled concurrency, and it does
not represent a deployed database or external request budget. Those
measurements remain required before using these results to publish capacity
limits or claim the M10 exit gate.
