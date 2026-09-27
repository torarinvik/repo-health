# Local benchmark scope

The checked-in benchmark is a deterministic local regression harness, not a
deployment capacity claim. `tools/bench.sh` writes `rh-bench/3` and
`tools/profile.sh` writes `rh-profile/3`. Each workload has one untimed warmup
batch and ten timed fresh-process batches by default. Set
`RH_BENCH_CONCURRENT_JOBS` from 1 to 32 to launch that many identical workload
processes in each batch; the default is 1. The measured interval includes
process startup and deterministic dataset construction, but excludes compiler
startup. Every process in a batch must produce byte-identical structural output.
Manifests retain every batch latency and the largest individual child peak-RSS
sample and a sampled concurrent RSS peak. The driver sums live-child RSS reads
within each poll pass at a 1 ms target interval. Very short peaks may be missed,
and batches with no successful sample are null with their sample count preserved.
The sum of child high-water marks is also recorded as a conservative upper
bound. That bound may overstate the simultaneous peak because each child's
high-water mark can occur at a different time. The sampled and upper-bound RSS
series report median, p95, maximum, and per-batch samples where available.
Manifests also report latency variance and aggregate batch node/edge throughput,
successful and failed repetition counts, and transitive-query truncation rate
when the selected stage runs a query. A failed sample aborts manifest
publication. Tests validate sample counts and outcomes without asserting
performance thresholds.

Each manifest also records the source revision, working-tree status, benchmark
binary and harness SHA-256 digests, compiler path/settings and pinned toolchain
revision, OS/architecture/CPU and available memory context, disk capacity/free
space, database applicability, warmup and cache conditions, and the actual
concurrent-process count. The workload itself makes zero external requests. OS
cache state and other host processes remain
uncontrolled; `disk_context` describes the host, while `disk_workload` reports
the temporary store corpus footprint described below.

`tools/bench-render.sh [out_dir]` writes `rh-render-bench/1` for the real
`rh_cli render` parse, HTML-generation, and file-write path. It uses
deterministic reports with 10, 1,000, and 10,000 metric rows, verifies stable
input/output SHA-256 digests across every warmup and measured process, and
records latency and per-process/concurrent RSS using the same warmup,
repetition, and concurrency controls. Set `RH_RENDER_BENCH_REPS` to override
the default `RH_BENCH_REPS` count. It makes no network requests and does not
measure database persistence or browser rendering. `tests/test_render_bench.sh`
checks digest stability and profile structure without imposing machine-specific
performance thresholds.

Set `RH_PROFILE_REPO` to opt into a full-history scan of a local Git repository
through `rh_cli scan`. The profile records its revision, dirty state, commit and
identity counts, history digest, latency, and memory samples. Every repetition
uses its own temporary report directory, and the temporary evidence is deleted
after profiling; the manifest does not retain raw author identities or commit
messages. The scan reads local history only and does not fetch from a remote.

Each `rh-bench/3` manifest also contains a temporary local-store disk profile.
The harness puts 17 deterministic evidence files (13 unique contents) through
`rh_cli store put`, verifies every content-addressed object, and records source
bytes, stored logical bytes, deduplication, and allocated bytes when the
filesystem reports them. Temporary files are removed after measurement. This
measures the current local filesystem store's footprint; it does not measure
write latency, PostgreSQL, or remote object storage.

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
current 1,000-node fixture includes four historical derived revisions per
subject. Its 32 accepted corrections invalidate 128 derived records from those
historical revisions and replay the corrected values. These are controlled
synthetic inputs, not claims about real ecosystem distributions or a production
correction history.

These workloads measure graph construction, reverse traversal on bounded
cases, indegree concentration, and the ecosystem projection operations listed
above. They do not yet represent real project histories or replay corrections
across arbitrary historical snapshots. The per-process peak RSS, sampled
concurrent memory, conservative concurrent memory upper bound, and latency
samples cover only this synthetic graph runner. The sampled RSS can miss peaks
between polling intervals. The harness also does not measure workload disk
consumption beyond the local evidence-store profile, and it does not represent
a deployed database or external request budget. Those
measurements remain required before using these results to publish capacity
limits or claim the M10 exit gate.
Concurrent processes exercise local CPU and memory contention only; they do not
measure scheduler throughput or saturation behavior. PostgreSQL claim logic defers optional graph queries while collection jobs are queued or leased, and generic claims rank collection jobs first; the opt-in migration rehearsal covers deferral and resumption. Worker unit/CLI tests cover bounded source rotation and full-reconcile priority. A daemon regression proves same-host processes sharing one output serialize their cursor and suppress duplicate unchanged inputs; fairness across hosts or database workers remains unmeasured.

`tools/bench-aggregate.sh` writes `rh-aggregate-bench/1` for the daily/weekly
aggregate path. It uses deterministic event inputs, seeds an independent state
store for every partial-cache sample, and records full-recompute and partial
cache latency and peak RSS with one warmup and at least two measured repetitions.
It compares output bytes for every full and partial result, records input and
binary digests, event and partition counts, cache-seeding cost, and the number
of reused partition rows. Set `RH_AGG_BENCH_EVENTS`, `RH_AGG_BENCH_REPS`,
`RH_AGG_BENCH_CONCURRENT_JOBS`, and `RH_AGG_BENCH_OUT` to control the workload
and manifest path. This synthetic benchmark includes input parsing and local
state-store I/O, uses no external services, and does not establish a deployed
capacity limit.

One pinned local run at revision `422472f` used 10,000 events across 91 daily
and 14 weekly partitions on macOS 27 / arm64 / Apple M5 (10 logical CPUs,
24 GiB RAM). Five measured repetitions after one warmup reported full
recomputation median/p95/max of 1,070/1,317/1,374 ms and partial-cache
median/p95/max of 914/1,099/1,128 ms. A one-event actor correction reused 103
of 105 partition rows, and full and partial output bytes matched
(`6cc6ba4ac00af04fdf9a6556dd22ae317ea20fd035f05d9c7327743546b24061`). Maximum
individual-child peak RSS was 18.17 MiB full and 18.46 MiB partial. Seeding the
prior cache took a separate median 1,193 ms and is excluded from the partial
timings. This is a single local synthetic profile; it is not a service
capacity or production workload claim.


A follow-up at revision `7d64f3b` used 12,000 events, the same 91 daily and 14
weekly partitions, and three measured repetitions. Full recomputation had a
1,566 ms median and 27.36 MiB maximum individual-child peak RSS; partial-cache
recomputation had a 1,270 ms median and 28.77 MiB maximum peak RSS. It reused
103 of 105 partition rows and produced byte-identical output
(`37f5dcb7bbb35fb7c28709fde2982d27440ed3e6d8b115e9d3dd02dd7957d177`). Cache
seeding took a separate 3,645 ms median. Attempts at 20,000 and 100,000 events
were rejected by the JSON parser's 200,000-node bound before measurement. This
exposes a concrete input-scale ceiling; larger aggregate workloads need a
bounded parsing strategy or a justified parser budget change before they can
be benchmarked. These measurements remain local synthetic evidence, not a
capacity claim.


After replacing sibling-chain walks in the bounded JSON DOM with a retained
last-child index, a clean run at revision `c60f219` repeated the 12,000-event,
three-repetition workload. Full recomputation measured 316 ms median and
30.39 MiB maximum individual-child peak RSS; partial-cache recomputation
measured 201 ms median and 31.82 MiB maximum peak RSS, reusing 103/105 rows.
Both paths again produced output SHA-256
`37f5dcb7bbb35fb7c28709fde2982d27440ed3e6d8b115e9d3dd02dd7957d177`. On the
same machine, this is about 80% lower full-recompute median and 84% lower
partial-cache median than the earlier 12,000-event sample. The three-sample
result is a local comparison, not a general speedup guarantee. The independent
JSON-node ceiling remains: 20,000 events are rejected before aggregate
measurement.


A clean 100,000-event run at revision `df99160` used two measured repetitions
after one warmup across 91 daily and 14 weekly partitions. Full recomputation
had a 12,490 ms median and 225.90 MiB maximum individual-child peak RSS; partial
cache had a 3,344 ms median and 243.17 MiB peak RSS. It reused 103/105 rows,
with byte-identical output SHA-256
`d824ba36a4ecd6a766f8a3d465975734692b6c9475b6f6cfad2283ed454fa76e`. Cache
seeding took a separate 10,450 ms median. The result confirms operation at
100k events under the aggregate-only 1.5m-node budget, but the two-sample
latencies varied substantially and memory use is material. This is a single
synthetic local run; it does not support deployment capacity claims. Ordinary
JSON adapter parsing remains capped at 200,000 nodes, and larger aggregate
workloads still require memory measurement before increasing the explicit cap.


The aggregate command now uses a dedicated parser limit while all ordinary JSON
adapters keep the 200,000-node default. A hard ceiling of 2 million nodes
limits that opt-in path; aggregate inputs use 1.5 million. A 20,000-event
worktree run (two repetitions) measured 981 ms full and 637 ms partial medians,
with 38.0 MiB and 40.0 MiB maximum peak RSS respectively. The clean 100,000-
event run above demonstrates the upper tested point. Both workloads matched
full and cached output bytes. The 100k memory and latency costs make further
cap increases contingent on explicit resource measurements.


The aggregate accumulator now uses bounded open-addressed actor and role
indexes, with capacities derived from events in uncached partitions only. A
clean run at revision `f734447` repeated the 100,000-event workload with three
repetitions. Full recomputation measured 2,640 ms median; partial-cache
recomputation measured 2,306 ms median while reusing 103/105 rows. Full and
partial output bytes matched (`d824ba36a4ecd6a766f8a3d465975734692b6c9475b6f6cfad2283ed454fa76e`). Maximum individual-child peak RSS was 234.88 MiB full and
243.19 MiB partial. Host load varied across this and prior small-sample runs,
so compare only the paired full/partial samples from one manifest.


The aggregate indexes use Elisa's allocation-free `hash_sview` for actor and
role keys, followed by exact span comparisons on collisions. A clean run at
revision `9da8021` measured the same 100,000-event input with three
repetitions: full recomputation median 2,565 ms, partial-cache median 2,288 ms,
103/105 rows reused, and byte-identical output SHA-256
`d824ba36a4ecd6a766f8a3d465975734692b6c9475b6f6cfad2283ed454fa76e`. Maximum
individual-child peak RSS remained 234.88 MiB full and 243.19 MiB partial.
Sample latency varied across runs; the paired timings are local synthetic
evidence only.
