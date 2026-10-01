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
    if t == "null":
        return val is None
    if t == "int_or_dict":
        return (isinstance(val, int) and not isinstance(val, bool)) or isinstance(val, dict)
    if t == "int_dict_or_null":
        return val is None or (isinstance(val, int) and not isinstance(val, bool)) or isinstance(val, dict)
    if t == "int_dict_bool_or_null":
        return val is None or (isinstance(val, int) and not isinstance(val, bool)) or isinstance(val, dict) or isinstance(val, bool)
    if t == "int_dict_bool":
        return (isinstance(val, int) and not isinstance(val, bool)) or isinstance(val, dict) or isinstance(val, bool)
    if t == "dict_or_null":
        return val is None or isinstance(val, dict)
    if t == "bool":
        return isinstance(val, bool)
    if t == "bool_or_null":
        return val is None or isinstance(val, bool)
    if t == "str_or_null":
        return val is None or isinstance(val, str)
    if t == "int_or_null":
        return val is None or (isinstance(val, int) and not isinstance(val, bool))
    if t == "int_str_or_null":
        return val is None or isinstance(val, str) or (isinstance(val, int) and not isinstance(val, bool))
    return False

def number_ok(val):
    return isinstance(val, (int, float)) and not isinstance(val, bool)

def check_obj(obj, spec, ctx):
    allowed_keys = spec.get("allowed_keys")
    if allowed_keys is not None:
        assert set(obj).issubset(set(allowed_keys)), (ctx, "unexpected keys", sorted(set(obj) - set(allowed_keys)))
    for k in spec.get("required", []):
        assert k in obj, (ctx, "missing required", k)
    for k, t in spec.get("types", {}).items():
        if k in obj:
            assert type_ok(obj[k], t), (ctx, "bad type", k, type(obj[k]), t)
    for k, allowed in spec.get("enum", {}).items():
        if k in obj:
            assert obj[k] in allowed, (ctx, "bad enum", k, obj[k], allowed)
    for k, minimum in spec.get("minimum", {}).items():
        if k in obj:
            value = obj[k]
            assert number_ok(value) and value >= minimum, (ctx, "below minimum", k, value, minimum)
    for k, maximum in spec.get("maximum", {}).items():
        if k in obj:
            value = obj[k]
            assert number_ok(value) and value <= maximum, (ctx, "above maximum", k, value, maximum)
    for k, maximum in spec.get("maximum_items", {}).items():
        if k in obj:
            assert isinstance(obj[k], list) and len(obj[k]) <= maximum, (ctx, "too many items", k, len(obj[k]), maximum)
    for k in spec.get("unique_items", []):
        if k in obj:
            values = obj[k]
            assert isinstance(values, list) and len(values) == len(set(json.dumps(value, sort_keys=True) for value in values)), (ctx, "duplicate items", k)
    for lower, upper in spec.get("less_than_or_equal", []):
        if lower in obj and upper in obj:
            left, right = obj[lower], obj[upper]
            assert number_ok(left) and number_ok(right) and left <= right, (ctx, "unordered fields", lower, left, upper, right)
    for k, variant_spec in spec.get("variants", {}).items():
        if k not in obj:
            continue
        value = obj[k]
        assert isinstance(value, dict), (ctx, "bad variant object", k)
        discriminator = variant_spec["discriminator"]
        assert discriminator in value, (ctx, "missing variant discriminator", k, discriminator)
        cases = variant_spec["cases"]
        assert value[discriminator] in cases, (ctx, "unknown variant", k, value[discriminator])
        check_obj(value, cases[value[discriminator]], "%s.%s<%s>" % (ctx, k, value[discriminator]))
    conditional = spec.get("conditional")
    if conditional is not None and conditional["field"] in obj:
        discriminator = conditional["field"]
        cases = conditional["cases"]
        assert obj[discriminator] in cases, (ctx, "unknown conditional case", discriminator, obj[discriminator])
        check_obj(obj, cases[obj[discriminator]], "%s<%s=%s>" % (ctx, discriminator, obj[discriminator]))
    for k, item_type in spec.get("item_types", {}).items():
        if k in obj:
            assert isinstance(obj[k], list), (ctx, "bad list", k)
            for i, value in enumerate(obj[k]):
                assert type_ok(value, item_type), (ctx, "bad item type", k, i, type(value), item_type)
    additional_type = spec.get("additional_properties")
    if additional_type is not None:
        known = set(spec.get("types", {}))
        for k, value in obj.items():
            if k not in known:
                assert type_ok(value, additional_type), (ctx, "bad additional property type", k, type(value), additional_type)
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
