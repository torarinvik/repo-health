# repo-health

An evidence-first observatory for the health of open-source software
infrastructure. Reference implementation written in
[Elisa](https://github.com/zoidbergclawd/elisa).

> **Status: early development.** M00 and M01 are implemented; M02–M12 remain
> in progress with their gates and limitations tracked in
> [STATUS.md](STATUS.md). Anything not backed by tested code is marked
> `planned` in [STATUS.md](STATUS.md) — no exceptions.

## Documentation

| Document | Description |
|---|---|
| [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) | Delivery plan, v0.1.0 |
| [Architecture.md](Architecture.md) | Architecture baseline, v0.1.0 |
| [docs/adr/ADR-000.md](docs/adr/ADR-000.md) | Language decision: Elisa |
| [STATUS.md](STATUS.md) | Honest implementation status per work item |

## Quick start

Requirements: the pinned Elisa toolchain (see `TOOLCHAIN.md`). HTTPS fetches
also require Python 3 and cURL. No credentials are needed; local scans and
the default checks use local data, while HTTPS fetches need network access.

```sh
./tools/check.sh   # verify toolchain
./tools/build.sh   # build binaries into build/

# Scan a repository
./build/rh_cli scan --repo <path-or-https-url> --out ./report/

# Recompute offline from the retained bundle (no network, no clock)
./build/rh_cli replay --bundle ./report/bundle.manifest --out ./report-replay/

# Show implemented metrics (explicit subset — never "all 360")
./build/rh_cli registry

# Query OSV for one package/version (the server version match is fuzzy)
./build/rh_cli osv-query --input ./fixtures/packages/osv-query-cargo.json --out ./osv-query/

# Optionally follow at most four pages; a remaining token stays explicit
./build/rh_cli osv-query --input ./fixtures/packages/osv-query-cargo.json --out ./osv-query-pages/ --continue-pagination

# Query OSV for one full Git commit hash
./build/rh_cli osv-query --input ./fixtures/packages/osv-query-commit.json --out ./osv-commit-query/

# Query up to 64 eligible nodes from a dependency graph in one OSV batch
./build/rh_cli osv-query --graph ./deps-cargo-graph.json --out ./osv-query-batch/

# Optionally follow per-query cursors for at most four batch rounds
./build/rh_cli osv-query --graph ./deps-cargo-graph.json --out ./osv-query-batch-pages/ --continue-pagination

# Optionally fetch full records for at most 64 distinct batch advisory IDs
./build/rh_cli osv-query --graph ./deps-cargo-graph.json --out ./osv-query-batch-hydrated/ --continue-pagination --hydrate-advisories
```

`osv-query` accepts `rh-osv-query-input/1` for one supported ecosystem, package
name, and supplied version string, or `rh-osv-query-input/2` for one full
40- or 64-hex Git commit hash. OSV describes package-version matching as fuzzy,
so the request does not guarantee an exact server-side match. It contacts only
`https://api.osv.dev/v1/query`, retains
the request, raw response, HTTP status, capture time, and response digest, and
writes a normalized OSV response. Package/version responses can be supplied to
`rh_cli deps --osv`; commit-query results remain separate context evidence and
are not automatically matched against a package graph.
Without `--continue-pagination`, the command keeps its one-page
`rh-osv-query-result/1` behavior and marks a returned `next_page_token` as
`more_available`. The opt-in continuation mode emits
`rh-osv-query-result/2`, follows at most four pages, keeps raw request/response,
status, stderr, and a digest for each page, and combines the returned
advisories for the offline matcher. If page four still returns a token, the
result is `partial` and the continuation value is retained in
`osv-query-next-page-token.txt`.

The explicit `--graph` mode accepts `rh-dep-graph/1`, submits up to 64
versioned nodes in request order to the fixed `/v1/querybatch` endpoint, and
reports path/Git or versionless nodes as skipped and over-cap nodes as omitted.
It retains the ordered request, raw response, HTTP status, stderr, and response
digest in `rh-osv-query-batch-result/1`, including a positional map from each
query to its graph node. OSV's batch response contains per-query
advisory ID and modification summaries rather than full advisory records.
Without continuation, returned per-query cursors make the result partial. With
`--continue-pagination`, the `rh-osv-query-batch-result/2` path follows at most
four rounds, resubmits only queries that returned cursors, and retains each
request/response/status/stderr/digest with its original query indexes. If the
four-round cap leaves work, the result is partial and the remaining request is
saved as `osv-query-batch-next-request.json`. These summaries are not a
`deps --osv` matcher input. With `--hydrate-advisories`, the
`rh-osv-query-batch-result/3` path fetches each distinct returned ID from the
fixed `/v1/vulns/{id}` endpoint, checks that the full record contains the exact
requested ID, and retains request, raw response, status, stderr, and digest
evidence. Hydration stops after 64 distinct records, 32 MiB of combined record
bodies, 120 seconds total, or 10 seconds for one request; any unsafe ID, failed lookup, cap, or unfinished batch is
reported as partial. The resulting `osv-query-hydrated-response.json` can be
passed to `deps --osv` for offline matching, with the result envelope retained
to inspect its coverage state. This only hydrates IDs observed for submitted
nodes and captured rounds. Batches remain capped, so they do not establish
complete lockfile coverage.

## Repository layout

```
src/        Elisa sources — domain, temporal primitives, observations,
            metric registry, evidence bundles, metrics, Git runner, CLI
tests/      Test harnesses and oracle programs; golden fixtures in fixtures/
schemas/    Versioned JSON schemas (reports, bundles, metric definitions)
metrics/    Implemented metric definitions (explicit subset)
docs/       Architecture decisions, threat model, API and operations guides
tools/      build.sh, check.sh — the local verification suite
```

## Design guarantees

- **Unknown is not zero.** Missing data is reported as `unavailable` or
  `unknown` — never synthesized.
- **No universal score.** The project publishes inspectable measurements,
  never a single health or trust rating.
- **Evidence for everything.** Every reported value traces back to retained,
  replayable inputs.
- **Strict identity discipline.** Accounts are not persons; contributors are
  not maintainers; version labels are not artifact digests.

## License

Public domain — see [LICENSE](LICENSE). Third-party toolchain and
data-source terms are unaffected; see the per-source review register.
