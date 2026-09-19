# Threat model (M00-07) — URL submission to public report publication

## Trust boundaries

1. **CLI argument boundary** — untrusted: repository URL/path, output
   directory. Trusted after `rh_git` validation (allowlist + kind check).
2. **Subprocess boundary** — `git` is invoked via `system(3)`, which uses a
   shell. Mitigation (documented deviation from plan §M01-02 "no shell"):
   strict allowlist validation in Elisa *before* any call; only
   `[A-Za-z0-9/_:.@-]` bytes permitted in user-supplied arguments; any shell
   metacharacter (`;&|$` `` ` `` `(){}<>!*?~#'"`, whitespace, backslash,
   `=^`) rejects the input with exit 3. Internal flags are constants, never
   user-controlled. `system()` return is checked; nonzero is a bounded error,
   never a fallback to invented data.
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
loopback/private/link-local literals (public IPv4 literals pass); curl is
pinned to `--proto`=https/file with redirects disabled and wall-clock/byte
caps, so a redirect can neither downgrade the scheme nor re-send anything
(there are no credentials to re-send: the M02 slice sends no Authorization
header, and authed endpoints report `unauthorized` honestly). Shell safety
is separate from URL semantics: single-quote wrapping plus rejection of
quote/backtick/dollar/backslash/controls. DNS rebinding is NOT mitigated
at this layer (a name that resolves safe then flips is outside URL policy);
follow-up in M07: per-connection resolution pinning and an approval-gated
instance allowlist before any non-test fetching beyond public APIs.

## Resource bounds (S012)

Bounded default scan (plan §M01-03): `--full-history` required for unbounded
log walks; output caps on log bytes; child-process exit + timeout checked.
Over-limit input is a bounded error, never a bypass of isolation.
