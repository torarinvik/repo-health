#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
bash "$ROOT/tools/build.sh" >/dev/null
cat >"$TMP/audit.json" <<'JSON'
{"schema":"rh-pylock-audit/1","requires_python":">=3.11,<4","environments":["sys_platform == 'linux' or sys_platform == 'win32'"],"packages":[{"name":"yes","version":"1.0","marker":"python_version >= '3.10'","requires_python":">=3.10,<4"},{"name":"no","version":"2.0","marker":"sys_platform == 'win32'","requires_python":">=3.13"},{"name":"unknown","version":null,"marker":"platform_release == 'future'","requires_python":"==3.12.*"}]}
JSON
cat >"$TMP/context.json" <<'JSON'
{"schema":"rh-pylock-evaluation-context/1","environment":{"python_version":"3.12","python_full_version":"3.12.1","sys_platform":"linux"},"dependency_groups":["dev"],"extras":[]}
JSON
"$ROOT/build/rh_cli" pylock-evaluate --audit "$TMP/audit.json" --context "$TMP/context.json" --out "$TMP/out.json" >/dev/null
python3 - "$TMP/out.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["schema"] == "rh-pylock-marker-evaluation/1", d
assert d["environment_state"] == "true", d
assert d["top_level_requires_python_state"] == "true", d
assert d["dependency_semantics"] == "informational_only" and d["installation_graph"] is False, d
assert [x["marker_state"] for x in d["package_markers"]] == ["true", "false", "unknown"], d
assert [x["requires_python_state"] for x in d["package_markers"]] == ["true", "false", "unknown"], d
assert d["coverage"] == {"package_count": 3, "marker_unknown_count": 1}, d
assert len(d["audit_sha256"]) == len(d["context_sha256"]) == 64, d
print("pylock evaluate output OK")
PY
cat >"$TMP/no-version-context.json" <<'JSON'
{"schema":"rh-pylock-evaluation-context/1","environment":{"sys_platform":"linux"},"dependency_groups":[],"extras":[]}
JSON
"$ROOT/build/rh_cli" pylock-evaluate --audit "$TMP/audit.json" --context "$TMP/no-version-context.json" --out "$TMP/no-version.json" >/dev/null
python3 - "$TMP/no-version.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["top_level_requires_python_state"] == "unknown", d
assert all(x["requires_python_state"] == "unknown" for x in d["package_markers"]), d
print("missing python_full_version remains unknown")
PY
if "$ROOT/build/rh_cli" pylock-evaluate --audit "$TMP/audit.json" --context "$TMP/audit.json" --out "$TMP/bad.json" >/dev/null 2>&1; then
  echo "invalid evaluation context unexpectedly accepted" >&2
  exit 1
fi
echo "test_pylock_evaluate_cli OK"
