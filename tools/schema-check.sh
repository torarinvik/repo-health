#!/usr/bin/env bash
# tools/schema-check.sh — validate checked-in fixtures against the
# versioned public schemas in schemas/. Tested independently of generated code:
# the schemas are data, this is the only checker, and it runs over the
# real fixture files.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "$ROOT" <<'PY'
import glob, json, os, sys
root = sys.argv[1]
schema_dir = os.path.join(root, "schemas")
schemas = []
for p in sorted(glob.glob(os.path.join(schema_dir, "*.schema.json"))):
    s = json.load(open(p))
    assert s["schema"] == "rh-jsonschema/1", p
    schemas.append((p, s))
assert schemas, "no schemas"

def type_ok(val, t):
    if t == "str":
        return isinstance(val, str)
    if t == "int":
        return isinstance(val, int) and not isinstance(val, bool)
    if t == "list":
        return isinstance(val, list)
    if t == "dict":
        return isinstance(val, dict)
    if t == "str_or_null":
        return val is None or isinstance(val, str)
    return False

def check_obj(obj, spec, ctx):
    for k in spec.get("required", []):
        assert k in obj, (ctx, "missing required", k)
    for k, t in spec.get("types", {}).items():
        if k in obj:
            assert type_ok(obj[k], t), (ctx, "bad type", k, type(obj[k]), t)
    for k, allowed in spec.get("enum", {}).items():
        if k in obj:
            assert obj[k] in allowed, (ctx, "bad enum", k, obj[k], allowed)
    items = spec.get("items", {})
    if items:
        for k, ispec in items.items():
            if k not in obj or not isinstance(obj[k], list):
                continue
            for i, el in enumerate(obj[k]):
                if isinstance(el, dict):
                    check_obj(el, ispec, "%s.%s[%d]" % (ctx, k, i))
    nested = spec.get("nested", {})
    for k, nspec in nested.items():
        if k in obj and isinstance(obj[k], dict):
            check_obj(obj[k], nspec, "%s.%s" % (ctx, k))

checked = 0
for path, s in schemas:
    files = []
    for pat in s["targets"]:
        files.extend(glob.glob(os.path.join(root, pat)))
    assert files, ("schema has no fixture files", s["name"], s["targets"])
    for f in sorted(files):
        if f.endswith(".lock.json") or f.endswith(".package.json"):
            continue
        name = os.path.basename(f)
        if name in ("npm-diamond.lock.json",):
            continue
        try:
            obj = json.load(open(f))
        except json.JSONDecodeError:
            continue
        check_obj(obj, s, name)
        checked += 1
        print("schema %-18s %s" % (s["name"], name))
print("schema-check OK: %d files, %d schemas" % (checked, len(schemas)))
PY
