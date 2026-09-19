#!/usr/bin/env bash
# tests/test_rpm_spec_cli.sh — bounded RPM spec preamble execution path.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-rpm-spec"

fail() { echo "[rpm-spec] FAIL: $1" >&2; exit 1; }

echo "[rpm-spec] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T"
cat > "$T/demo.spec" <<'SPEC'
Name:           demo
Version:        1.2.3
Release:        4%{?dist}
Epoch:          1
Summary:        Demo package
License:        MIT
URL:            https://example.invalid/demo
Source0:        https://example.invalid/demo-%{version}.tar.gz
Patch1:         fix.patch
BuildArch:      x86_64
BuildRequires:  gcc >= 11
Requires:       libfoo >= 2.0 libbar
Recommends:     docs
Provides:       demo-api
Conflicts:      old-demo
%description
The body is not interpreted.
%prep
%setup -q
SPEC
"$ROOT/build/rh_cli" rpm-spec --input "$T/demo.spec" --out "$T/out.json" >/dev/null || fail "run"
python3 - "$T/out.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-rpm-spec-result/1" and d["format"] == "rpm-spec", d
assert d["name"] == "demo" and d["version"] == "1.2.3" and d["release"] == "4%{?dist}", d
assert d["sources"] == ["https://example.invalid/demo-%{version}.tar.gz"], d
assert d["patches"] == ["fix.patch"], d
assert [(r["name"], r["scope"], r["requirement"]) for r in d["relations"]] == [
    ("gcc", "build", ">= 11"), ("libfoo", "runtime", ">= 2.0"),
    ("libbar", "runtime", None), ("docs", "recommend", None),
    ("demo-api", "provide", None), ("old-demo", "conflict", None)
], d["relations"]
assert d["unknown_fields"] == 0 and d["unresolved_relations"] == 0, d
assert "not expanded or executed" in d["note"], d["note"]
print("[rpm-spec] preamble fields, scopes, and section boundary OK")
PY

echo "[rpm-spec] macro relation remains unresolved"
cat > "$T/macro.spec" <<'SPEC'
Name: macro-demo
Version: 1
Release: 1
Requires: %{name}
%description
SPEC
"$ROOT/build/rh_cli" rpm-spec --input "$T/macro.spec" --out "$T/macro.json" >/dev/null || fail "macro run"
python3 - "$T/macro.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["unresolved_relations"] == 1 and d["relations"][0]["state"] == "unresolved", d
print("[rpm-spec] macro unresolved state OK")
PY

echo "[rpm-spec] deterministic replay + malformed negatives"
"$ROOT/build/rh_cli" rpm-spec --input "$T/demo.spec" --out "$T/out2.json" >/dev/null || fail "rerun"
cmp -s "$T/out.json" "$T/out2.json" || fail "rpm output not deterministic"
set +e
printf 'Name: demo\nVersion: 1\nName: duplicate\nRelease: 1\n' > "$T/duplicate.spec"
"$ROOT/build/rh_cli" rpm-spec --input "$T/duplicate.spec" --out "$T/x" >/dev/null 2>&1; rc_dup=$?
printf 'Name demo\nVersion: 1\nRelease: 1\n' > "$T/nocolon.spec"
"$ROOT/build/rh_cli" rpm-spec --input "$T/nocolon.spec" --out "$T/x" >/dev/null 2>&1; rc_colon=$?
printf 'Name: demo\nRelease: 1\n' > "$T/noversion.spec"
"$ROOT/build/rh_cli" rpm-spec --input "$T/noversion.spec" --out "$T/x" >/dev/null 2>&1; rc_version=$?
printf 'not json' > "$T/not.spec"
"$ROOT/build/rh_cli" rpm-spec --input "$T/not.spec" --out "$T/x" >/dev/null 2>&1; rc_not=$?
set -e
for rc in "$rc_dup" "$rc_colon" "$rc_version" "$rc_not"; do
  [[ "$rc" -eq 4 ]] || fail "malformed rpm spec must exit 4 (got $rc)"
done

echo "test_rpm_spec_cli OK"
