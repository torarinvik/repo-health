#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
bash "$ROOT/tools/build.sh" >/dev/null
cat >"$TMP/audit.json" <<'JSON'
{"schema":"rh-pylock-audit/1","requires_python":">=3.11,<4","extras":["speedups"],"dependency_groups":["dev","test"],"default_groups":["default"],"environments":["sys_platform == 'linux' or sys_platform == 'win32'"],"packages":[{"name":"yes","version":"1.0","marker":"'default' in dependency_groups and python_version >= '3.10'","requires_python":">=3.10,<4"},{"name":"no","version":"2.0","marker":"sys_platform == 'win32'","requires_python":">=3.13"},{"name":"unknown","version":null,"marker":"platform_release == 'future'","requires_python":"==3.12.*"}]}
JSON
cat >"$TMP/context.json" <<'JSON'
{"schema":"rh-pylock-evaluation-context/1","environment":{"python_version":"3.12","python_full_version":"3.12.1","sys_platform":"linux"},"dependency_groups":["default"],"extras":[]}
JSON
"$ROOT/build/rh_cli" pylock-evaluate --audit "$TMP/audit.json" --context "$TMP/context.json" --out "$TMP/out.json" >/dev/null
python3 - "$TMP/out.json" <<'PY'
import json, sys
import hashlib
d = json.load(open(sys.argv[1]))
audit_path = sys.argv[1].replace("out.json", "audit.json")
context_path = sys.argv[1].replace("out.json", "context.json")
out_bytes = open(sys.argv[1], "rb").read()
sidecar = json.load(open(sys.argv[1] + ".transformations.json"))
assert d["schema"] == "rh-pylock-marker-evaluation/1", d
assert d["environment_state"] == "true", d
assert d["top_level_requires_python_state"] == "true", d
assert d["dependency_semantics"] == "informational_only" and d["installation_graph"] is False, d
assert [x["marker_state"] for x in d["package_markers"]] == ["true", "false", "unknown"], d
assert [x["requires_python_state"] for x in d["package_markers"]] == ["true", "false", "unknown"], d
assert d["coverage"] == {"package_count": 3, "marker_unknown_count": 1}, d
assert len(d["audit_sha256"]) == len(d["context_sha256"]) == 64, d
assert sidecar["source_input_sha256"] == hashlib.sha256(open(audit_path, "rb").read()).hexdigest(), sidecar
assert sidecar["source_context_sha256"] == hashlib.sha256(open(context_path, "rb").read()).hexdigest(), sidecar
assert sidecar["normalized_output_sha256"] == hashlib.sha256(out_bytes).hexdigest(), sidecar
assert sidecar["output_schema"] == d["schema"] and sidecar["configuration_sha256"] != "0" * 64, sidecar
assert any(x["state"] == "unsupported" and x["target"] == "installation_graph" for x in sidecar["fields"]), sidecar
print("pylock evaluate output OK")
PY
cat >"$TMP/no-version-context.json" <<'JSON'
{"schema":"rh-pylock-evaluation-context/1","environment":{"python_version":"3.12","sys_platform":"linux"}}
JSON
"$ROOT/build/rh_cli" pylock-evaluate --audit "$TMP/audit.json" --context "$TMP/no-version-context.json" --out "$TMP/no-version.json" >/dev/null
python3 - "$TMP/no-version.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["top_level_requires_python_state"] == "unknown", d
assert all(x["requires_python_state"] == "unknown" for x in d["package_markers"]), d
assert d["package_markers"][0]["marker_state"] == "true", d
print("missing python_full_version unknown; omitted groups use default_groups")
PY
cat >"$TMP/empty-groups-context.json" <<'JSON'
{"schema":"rh-pylock-evaluation-context/1","environment":{"python_version":"3.12","sys_platform":"linux"},"dependency_groups":[]}
JSON
"$ROOT/build/rh_cli" pylock-evaluate --audit "$TMP/audit.json" --context "$TMP/empty-groups-context.json" --out "$TMP/empty-groups.json" >/dev/null
python3 - "$TMP/empty-groups.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["package_markers"][0]["marker_state"] == "false", d
print("explicit empty dependency_groups overrides default_groups")
PY
python3 - "$TMP/audit.json" "$TMP/unconstrained-audit.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d.pop("requires_python", None)
for package in d["packages"]:
    package.pop("requires_python", None)
json.dump(d, open(sys.argv[2], "w"))
PY
"$ROOT/build/rh_cli" pylock-evaluate --audit "$TMP/unconstrained-audit.json" --context "$TMP/context.json" --out "$TMP/unconstrained.json" >/dev/null
python3 - "$TMP/unconstrained.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["top_level_requires_python_state"] == "true", d
assert all(x["requires_python_state"] == "true" for x in d["package_markers"]), d
print("absent requires-python is unconstrained")
PY
cat >"$TMP/undeclared-context.json" <<'JSON'
{"schema":"rh-pylock-evaluation-context/1","environment":{"python_version":"3.12","python_full_version":"3.12.1","sys_platform":"linux"},"dependency_groups":["typo"],"extras":[]}
JSON
if "$ROOT/build/rh_cli" pylock-evaluate --audit "$TMP/audit.json" --context "$TMP/undeclared-context.json" --out "$TMP/bad.json" >/dev/null 2>&1; then
  echo "undeclared dependency group unexpectedly accepted" >&2
  exit 1
fi
cat >"$TMP/duplicate-context.json" <<'JSON'
{"schema":"rh-pylock-evaluation-context/1","environment":{"python_version":"3.12"},"environment":{"python_version":"3.11"}}
JSON
if "$ROOT/build/rh_cli" pylock-evaluate --audit "$TMP/audit.json" --context "$TMP/duplicate-context.json" --out "$TMP/bad.json" >/dev/null 2>&1; then
  echo "duplicate evaluation context key unexpectedly accepted" >&2
  exit 1
fi
echo "test_pylock_evaluate_cli OK"
