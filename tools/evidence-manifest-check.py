#!/usr/bin/env python3
"""Validate the versioned line-oriented evidence bundle manifest contract."""
import json
import pathlib
import re
import sys


def fail(message):
    raise ValueError(message)


def validate(path, schema_path):
    spec = json.loads(pathlib.Path(schema_path).read_text())
    if spec.get("schema") != "rh-evidence-bundle-manifest-schema/1":
        fail("unknown manifest schema")
    raw = pathlib.Path(path).read_bytes()
    if not raw.endswith(b"\n") or b"\r" in raw:
        fail("manifest must use canonical LF line endings")
    lines = raw.decode("utf-8").splitlines()
    if not lines:
        fail("empty manifest")
    version_key, version_spec = next(((key, value) for key, value in spec["versions"].items() if value["header"] == lines[0]), (None, None))
    if version_spec is None:
        fail("unsupported manifest header")
    rows = []
    for line in lines[1:]:
        if not line or ": " not in line:
            fail("malformed manifest row")
        key, value = line.split(": ", 1)
        if not key or not value:
            fail("empty manifest key or value")
        rows.append((key, value))
    repeated = set(version_spec["repeated_sha256"])
    repeated.update(version_spec["expected_outputs"])
    repeated.update(version_spec["optional_outputs"])
    values = {}
    positions = {}
    for index, (key, value) in enumerate(rows):
        if key in values and key not in repeated:
            fail("duplicate singleton field: " + key)
        if key not in repeated and key not in version_spec["fixed_fields"]:
            fail("unknown field: " + key)
        values.setdefault(key, []).append(value)
        positions.setdefault(key, []).append(index)
    required = set(version_spec["fixed_fields"] + version_spec["repeated_sha256"] + version_spec["expected_outputs"])
    missing = required - set(values)
    if missing:
        fail("missing fields: " + ", ".join(sorted(missing)))
    allowed = required | set(version_spec["optional_outputs"])
    unknown = set(values) - allowed
    if unknown:
        fail("unknown fields: " + ", ".join(sorted(unknown)))
    expected_order = version_spec["fixed_fields"] + version_spec["repeated_sha256"] + version_spec["expected_outputs"] + [k for k in version_spec["optional_outputs"] if k in values]
    actual_order = [key for key, _ in rows]
    if actual_order != expected_order:
        fail("fields are not in canonical order")
    if values["bundle-schema"] != [version_spec["bundle_schema"]]:
        fail("header and bundle schema disagree")
    if values["report-schema"] != [spec["report_schema"]]:
        fail("unexpected report schema")
    expected_files = spec.get("files_by_version", {}).get(version_key, spec["files"])
    if values["files"] != [" ".join(expected_files)]:
        fail("unexpected evidence file set or order")
    enums = spec["enums"]
    for key, allowed_values in enums.items():
        if values[key][0] not in allowed_values:
            fail("invalid enum value: " + key)
    for key in spec["nonnegative_integer_fields"]:
        if not re.fullmatch(r"0|[1-9][0-9]*", values[key][0]):
            fail("invalid nonnegative integer: " + key)
    for key in spec["positive_integer_fields"]:
        if int(values[key][0]) <= 0:
            fail("invalid positive integer: " + key)
    if not re.fullmatch(r"[0-9a-f]{16}", values["digest-fnv1a64"][0]):
        fail("invalid legacy FNV digest")
    for key in version_spec["repeated_sha256"] + version_spec["expected_outputs"] + version_spec["optional_outputs"]:
        if key in values and not re.fullmatch(r"[0-9a-f]{64}", values[key][0]):
            fail("invalid SHA-256 digest: " + key)
    if len(values["source"][0]) > 4096 or any(ord(char) < 32 for char in values["source"][0]):
        fail("invalid source locator")
    if not values["tool"][0].startswith("rh_cli "):
        fail("invalid tool identity")
    return True


if __name__ == "__main__":
    if len(sys.argv) not in (2, 3):
        print("usage: evidence-manifest-check.py MANIFEST [SCHEMA]", file=sys.stderr)
        raise SystemExit(2)
    schema = sys.argv[2] if len(sys.argv) == 3 else pathlib.Path(__file__).resolve().parents[1] / "schemas/evidence-bundle-manifest.spec.json"
    try:
        validate(sys.argv[1], schema)
    except (OSError, json.JSONDecodeError, ValueError, KeyError) as exc:
        print("evidence-manifest-check: " + str(exc), file=sys.stderr)
        raise SystemExit(1)
    print("evidence-manifest-check OK")
