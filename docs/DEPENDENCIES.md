# Dependency inventory and update procedure

Repo-health has no application package manifest and downloads no dependencies
as part of its normal build. The implementation lives in Elisa; external
programs and native libraries are isolated at explicit process or ABI
boundaries.

## Build and test tools

| Component | Required use | Boundary and update check |
|---|---|---|
| Elisa compiler | Compiles every `src/*.elisa` program through `tools/build.sh`. | Pin the compiler snapshot and runtime together; see [`TOOLCHAIN.md`](../TOOLCHAIN.md). Update only from a reviewed Elisa compiler revision, rebuild all targets, and run `bash tools/check.sh`. Never float to an unreviewed `latest` binary. |
| POSIX shell and core utilities | Run build/test scripts and create isolated fixtures. | The scripts are Bash-oriented and use standard utilities such as `mktemp`, `find`, `cmp`, `sed`, and `grep`. Review changes to command construction and shell quoting with [`THREAT_MODEL.md`](THREAT_MODEL.md). |
| Python 3 standard library | Test assertions and the bounded DNS resolver helper invoked by the HTTP transport. | No third-party Python package is required. Keep the resolver helper on `python3 -I -S`; review any module/import or command change for isolation and resolver semantics. |
| Git | Repository history collection and test fixture construction. | Tests and source collection call Git through the allowlisted boundary in `src/rh_git.elisa`. Recheck accepted arguments and hostile-path tests when changing Git usage. |
| Mercurial, Subversion, Fossil | Optional native-history collection and their integration tests. | These are optional for the general build; a missing executable makes only its native collection path unavailable. Keep each command's arguments allowlisted and retain parser fixtures for captured formats. |
| cURL | Optional live HTTPS/API acquisition. | All requests pass through the bounded transport in `src/rh_git.elisa`: redirects, ambient cURL config, and proxies are disabled; routes and credentials are constrained by callers. Recheck the DNS-pinning cases in `tests/test_m07.sh` and connector tests after a cURL/TLS or invocation change. |
| LLVM/Clang | Used by the Elisa compiler toolchain to emit native executables; not called directly by the normal build script. | Use the version recorded in [`TOOLCHAIN.md`](../TOOLCHAIN.md) when updating the compiler snapshot. Re-run the full deterministic gate on each supported host architecture. |

The repository test scripts use Python's standard library for fixture
generation and JSON checks. `tools/check.sh` is the authoritative local suite;
it compiles before running the shell harnesses. PostgreSQL migration rehearsals
are opt-in and use Docker with PostgreSQL 16. They do not make Docker or a
database server a normal build dependency.

## Native libraries and optional services

| Component | Use | Boundary and update check |
|---|---|---|
| OS libc / POSIX APIs | File operations, process launch, sockets, dynamic library loading, locks, and directory synchronization. | Elisa declares the narrow ABI surface at each call site. Review ABI types, ownership, error handling, and platform assumptions in the affected module; run sanitizer and platform-specific tests where available. |
| zlib | Raw DEFLATE decoding and CRC32 only for Go module ZIP verification. | Linked only into `rh_cli` with `-lz`. ZIP structure, path/name handling, limits, ordering, and Go `h1` hashing remain in Elisa. Re-run `tests/test_artifact_observation_cli.sh` including stored, deflated, CRC-invalid, and limit cases after a zlib/toolchain update. |
| libpq | Optional PostgreSQL adapter, loaded dynamically by `src/rh_postgres.elisa`. | No link-time libpq requirement. The adapter calls the extended parameterized-query API; arbitrary SQL is not accepted from input. Validate with `tests/test_pg_adapter.sh` and `tests/test_postgres_cli.sh`; run `tests/test_pg_adapter_live.sh` and `tests/test_migrations_live.sh` against PostgreSQL 16 when Docker/libpq are available. |
| PostgreSQL 16 | Optional persistence and live migration/recovery rehearsals. | The supported schema is versioned in `db/migrations/`. Review migration compatibility and run the live migration suite before changing the supported server major version. |
| PostgreSQL client tools (`pg_dump`, `pg_restore`, `psql`) | Optional `tools/backup-postgres.sh` and `tools/restore-postgres-backup.sh` backup/restore workflow. | Connection URLs are supplied through `PGDATABASE`, not command-line arguments. Pair binding currently reads at most 64 MiB; larger streaming dumps are not yet supported. |

## Update procedure

1. Identify the exact component and the boundary it serves above; do not add a
   package-manager dependency when the required behavior belongs in Elisa or an
   existing standard library.
2. Review the upstream release notes and security advisories, then pin the
   selected compiler/runtime or server/tool version in `TOOLCHAIN.md` or the
   relevant capability contract. Keep optional dependencies optional.
3. Update boundary-specific tests, including malformed-input and failure-path
   tests. Native libraries must remain narrow implementation details rather
   than becoming parsers or policy authorities.
4. Run the focused test first, then `bash tools/check.sh`. Run opt-in live and
   sanitizer suites when the changed boundary supports them; record unavailable
   gates rather than treating them as passed.
5. Update this inventory and `CHANGELOG.md` in the same change when a dependency
   is added, removed, upgraded, or gains a new authority over input or output.

This inventory covers build, test, runtime, and optional persistence
dependencies. Data-provider terms and redistribution constraints are tracked
separately in connector manifests and the M07 source-review register.
