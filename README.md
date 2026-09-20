# repo-health

An evidence-first observatory for the health of open-source software
infrastructure. Reference implementation written in
[Elisa](https://github.com/zoidbergclawd/elisa).

> **Status: early development.** The foundation (M00) and first scan slice
> (M01) are in progress. Anything not backed by tested code is marked
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
```

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
