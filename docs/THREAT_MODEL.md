# Threat model (M00-07) — URL submission to public report publication

## Trust boundaries

1. **CLI argument boundary** — untrusted: repository URL/path, output
   directory. Trusted after `rh_git` validation (allowlist + kind check).
2. **Subprocess boundary** — Git acquisition, native VCS collectors, DNS
   resolution, and curl transport use the `rh_process` POSIX spawn bridge with
   NUL-delimited argv/env, explicit child environments, a combined 64 MiB
   stdout/stderr cap, bounded optional stdin, and a monotonic wall-clock
   timeout. Each child starts in its own process group, which is killed on
   timeout or output overflow. Its tests
   prove shell metacharacters stay literal, byte-vector arguments preserve
   their boundaries, and transport credentials travel through stdin rather
   than argv or retained files. The process runner does not yet enforce child memory/process creation. Its
   Elisa API returns typed exit, timeout, output-limit, setup-error, signal, and
   I/O-error results; explicit compatibility adapters still map those results
   to numeric statuses for the remaining transport and utility APIs. No Elisa
   source calls `system(3)`; subprocess call sites in `rh_git` use the bounded
   process runner. Individual fetchers retain
   their own byte limits.
3. **No server endpoint** scans arbitrary server paths (M01-01): this CLI is
   local-only; there is no network listener in M00/M01.
4. **No source-code execution** (S001): repositories are read with
   `git log --format` plumbing and `rev-parse` only. No hooks, filters,
   smudge/clean drivers, or build scripts are ever executed. (Enforced by
   never invoking `checkout`, `clone` with hooks enabled, or `archive`
   extraction in the scan path.)
5. **Credential handling** (S003): no credentials are accepted, stored, or
   copied. `tests/test_m01.sh` seeds a git credential-store token and a
   `userinfo` remote URL and asserts the canary never appears in report,
   evidence, or stdout/stderr. A secret a project itself commits as author
   data is evidence (history), not a leaked transport credential. Evidence
   manifests record tool versions and sanitized command purposes only —
   never URLs with embedded `user:pass@`, tokens, or environment dumps.

## Review record (M07-01)

A per-boundary review checklist lives at `ops/threat-model-review.json`: for
each boundary above it records the assets, the attack, the tested control,
and the residual risk, and it names the areas NOT covered (no independent
third-party audit, no release signing, no general fuzzing harness). It is an
internal artifact and makes no safety claim.

## Protected assets

- User's filesystem (bounded writes to the chosen `--out` directory only).
- Correctness of published reports (no silent unknown→value conversion).
- Private data: raw author identities stay in the local evidence bundle and
  are never printed to stdout by default.

## Prohibited inferences (S010, R030)

No person-level moral/medical/sensitive-attribute inference. No universal
health or contributor-trust score. Concentration metrics describe *event
distributions*, never maintainer worth.

## Network policy (S002)

M00/M01 perform no outbound connections except when the user explicitly
passes a public `https://` remote to `scan` (fetch via `git`, same
restrictions as a manual clone). No loopback/private/link-local targets are
ever constructed by the tool; `http://`, `ssh://`, `git@`, and `file://`
remotes are rejected as `unsupported` in the M01 slice.

M02 forge fetch (`rh_run_https_get`, `rh_fetch_guard` + `rh_fetch_arg_safe`):
https or caller-named `file://` fixtures only; no ports, no userinfo, no
percent-escapes or brackets in the host, no bare `localhost`, no IPv4
loopback/private/link-local literals (public IPv4 literals pass). Before an
HTTPS request, Python 3's standard resolver runs in a worker thread with a
10-second join bound; the
complete, deduplicated result set is capped at 32 addresses, and every IPv4 or
IPv6 address must pass `rh_addr_guard`, which conservatively excludes special
purpose ranges such as TEST-NET, Teredo, and the IPv6 documentation blocks in
the [IANA IPv4](https://www.iana.org/assignments/iana-ipv4-special-registry)
and [IPv6](https://www.iana.org/assignments/iana-ipv6-special-registry)
registries. The bounded result is supplied to cURL
with `--resolve`, so the connection uses only those checked addresses even if
DNS changes after lookup. cURL user config and proxies are disabled, and its
protocol is restricted to HTTPS or caller-named file fixtures; redirects stay
disabled and wall-clock/byte caps bound the transfer. A redirect therefore
cannot downgrade the scheme or re-send anything (the M02 slice sends no
Authorization header, and authed endpoints report `unauthorized` honestly).
Shell safety is separate from URL semantics: single-quote wrapping plus
rejection of quote/backtick/dollar/backslash/controls. The deterministic M07
transport test injects mixed public/private answers and proves cURL is not run,
then verifies the complete safe IPv4/IPv6 set appears in `--resolve`. An
approval-gated instance allowlist is still required before non-test fetching
beyond public APIs.

## Resource bounds (S012)

Bounded default scan (plan §M01-03): `--full-history` required for unbounded
log walks; output caps on log bytes; child-process exit + timeout checked.
Over-limit input is a bounded error, never a bypass of isolation.

Go module ZIP observation is also bounded: the compressed archive and total
expanded contents are each capped at 64 MiB, entry count at 10,000, and total
filename bytes at 8 MiB. ZIP metadata parsing, Go `h1` ordering, graph binding,
and error handling run in Elisa. The OS-provided zlib library is limited to raw
DEFLATE decoding and CRC32; no archive paths are created and no content is
extracted to the filesystem. ZIP64, split, encrypted, duplicate-name, malformed,
CRC-invalid, and over-limit archives fail closed.
