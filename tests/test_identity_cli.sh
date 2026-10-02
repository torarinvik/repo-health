#!/usr/bin/env bash
# tests/test_identity_cli.sh — M04-03 reversible identity-link execution
# path: `rh_cli identity` turns an rh-identity-input/1 ledger into
# rh-identity-result/1 with the identity revision, clusters over ACCEPTED
# links only, and a per-actor cluster map. Revoking recomputes clusters and
# changes the revision; rejected/proposed links change nothing; malformed
# input fails closed.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="/tmp/rh-identity"

fail() { echo "[identity] FAIL: $1" >&2; exit 1; }

echo "[identity] build"
bash "$ROOT/tools/build.sh" >/dev/null
[[ -x "$ROOT/build/rh_cli" ]] || fail "rh_cli not built"

rm -rf "$T"; mkdir -p "$T"
cat > "$T/a.json" <<'JSON'
{"schema":"rh-identity-input/1","actor_count":5,"links":[{"a":0,"b":1,"state":"accepted","revision_added":1},{"a":1,"b":2,"state":"accepted","revision_added":2},{"a":3,"b":0,"state":"rejected","revision_added":3}],"actor_kinds":["human","human","unresolved","bot_known","service_known"],"actor_kind_sources":["provider","provider","unknown","provider","project"],"actor_kind_observed_at":[1700000000,null,1700000200,1700000300,1700000400],"actor_kind_evidence_refs":["evidence:provider-run-8",null,"evidence:project-declaration-2","evidence:provider-run-8","evidence:operator-review-3"],"actors":[{"source":"github","source_instance":"github.com/acme","native_object_id":"repo-1","display_name":"shared","aliases":[{"value":"old-name","observed_at":100}]},{"source":"github","source_instance":"github.com/acme","native_object_id":"repo-2","display_name":"other","aliases":[]},{"source":"gitlab","source_instance":"gitlab.com/acme","native_object_id":"repo-1","display_name":"shared","aliases":[]},{"source":"github","source_instance":"github.com/acme","native_object_id":"bot-1","display_name":"bot","aliases":[]},{"source":"github","source_instance":"github.com/acme","native_object_id":"service-1","display_name":"automation service","aliases":[]}]}
JSON
cat > "$T/b.json" <<'JSON'
{"schema":"rh-identity-input/1","actor_count":4,"links":[{"a":0,"b":1,"state":"accepted","revision_added":1},{"a":1,"b":2,"state":"revoked","revision_added":4},{"a":3,"b":0,"state":"rejected","revision_added":3}]}
JSON

"$ROOT/build/rh_cli" identity --input "$T/a.json" --out "$T/a.out" >/dev/null || fail "A run"
python3 - "$T/a.json" "$T/a.out" <<'PY'
import hashlib, json, sys
source, output = sys.argv[1:]
v = json.load(open(output + ".evidence-verification.json"))
n = json.load(open(output + ".identity-review-notices.json"))
tr = json.load(open(output + ".transformations.json"))
assert v["state"] == "unverified" and v["verified_reference_count"] == 0, v
assert n["state"] == "unverified" and n["notice_count"] == 0 and n["notices"] == [], n
assert v["source_input_sha256"] == n["source_input_sha256"] == hashlib.sha256(open(source, "rb").read()).hexdigest()
assert v["identity_output_sha256"] == n["identity_output_sha256"] == hashlib.sha256(open(output, "rb").read()).hexdigest()
assert tr["schema"] == "rh-adapter-transformation-report/1" and tr["adapter"] == "reviewed-identity-ledger", tr
assert tr["source_input_sha256"] == hashlib.sha256(open(source, "rb").read()).hexdigest(), tr
assert tr["normalized_output_sha256"] == hashlib.sha256(open(output, "rb").read()).hexdigest(), tr
assert tr["configuration_sha256"] == hashlib.sha256(b"repo-health/reviewed-identity-ledger/1").hexdigest(), tr
assert {f["state"] for f in tr["fields"]} == {"preserved", "transformed", "unknown", "unsupported", "discarded"}, tr
print("[identity] absent evidence-store state is explicit and bound")
PY
python3 - "$T/a.out" "$ROOT" <<'PY'
import glob, json, sys
d = json.load(open(sys.argv[1]))
root = sys.argv[2]
assert d["schema"] == "rh-identity-result/1", d
assert d["actor_count"] == 5 and d["identity_revision"] == 2, d
assert d["cluster_count"] == 3, d
assert d["metrics"][0]["key"] == "contributor.accepted_actor_clusters" and d["metrics"][0]["value"] == 3, d
assert d["metrics"][1]["key"] == "contributor.known_human_accounts" and d["metrics"][1]["value"] == 2, d
metrics = {metric["key"]: metric for metric in d["metrics"]}
definitions = {}
for path in glob.glob(root + "/metrics/definitions/*.json"):
    definition = json.load(open(path))
    definitions[(definition["key"], definition["version"])] = definition
expected = {
    "contributor.accepted_actor_clusters": {
        "inputs": ["actor_count", "identity_link_ledger"],
        "unit": "clusters",
        "denominator_rule": "none; distinct actor clusters induced by accepted identity links",
    },
    "contributor.known_human_accounts": {
        "inputs": ["actor_count", "identity_actor_kind_ledger"],
        "unit": "accounts",
        "denominator_rule": "none; accounts explicitly classified human in the supplied identity-kind ledger",
    },
}
assert set(metrics) == set(expected), metrics
for key, metric in metrics.items():
    identity = (key, metric["version"])
    definition = definitions[identity]
    assert definition["implementation_status"] == "implemented", (identity, definition)
    assert definition["subject_kind"] == "project", (identity, definition["subject_kind"])
    assert definition["source_requirements"] == ["identity-ledger"], (identity, definition["source_requirements"])
    assert definition["inputs"] == expected[key]["inputs"], (identity, definition["inputs"])
    assert definition["output"] == {"unit": expected[key]["unit"], "type": "integer"}, (identity, definition["output"])
    assert definition["denominator_rule"] == expected[key]["denominator_rule"], (identity, definition["denominator_rule"])
    assert metric["status"] == "observed" and type(metric["value"]) is int and metric["value"] >= 0, (identity, metric)
print("[identity] both emitted metric rows match catalog subjects, sources, inputs, types, and denominators")
for metric in d["metrics"]:
    assert metric["status"] == "observed", metric
    assert metric["evidence"] == ["identity-input"], metric
    assert metric["quality_dimensions"] == {
        "completeness": "complete",
        "freshness": "unknown",
        "validity": "valid",
        "provenance": "evidence_backed",
    }, metric
assert d["clusters"] == [[0, 1, 2], [3], [4]], d["clusters"]
assert d["cluster_id_by_actor"] == [0, 0, 0, 3, 4], d["cluster_id_by_actor"]
assert d["actor_kinds"] == {"human": 2, "bot_known": 1, "service_known": 1, "unresolved": 1}, d["actor_kinds"]
assert d["actor_kind_sources"] == {"provider": 3, "project": 1, "operator": 0, "unknown": 1}, d["actor_kind_sources"]
assert d["actor_kind_observation_times"] == {"observed": 4, "unknown": 1}, d["actor_kind_observation_times"]
assert d["actor_kind_evidence_references"] == {"present": 4, "unknown": 1}, d["actor_kind_evidence_references"]
assert d["actor_classifications"][0] == {"actor_id": 0, "kind": "human", "source": "provider", "observed_at": 1700000000, "evidence_ref": "evidence:provider-run-8"}, d["actor_classifications"]
assert d["actor_classifications"][1] == {"actor_id": 1, "kind": "human", "source": "provider", "observed_at": None, "evidence_ref": None}, d["actor_classifications"]
assert d["actor_classifications"][4] == {"actor_id": 4, "kind": "service_known", "source": "project", "observed_at": 1700000400, "evidence_ref": "evidence:operator-review-3"}, d["actor_classifications"]
assert d["actors"][0]["source_instance"] == "github.com/acme", d
assert d["actors"][0]["aliases"] == [{"value": "old-name", "observed_at": 100}], d
assert d["actors"][0]["display_name"] == d["actors"][2]["display_name"] and d["actors"][0]["source_instance"] != d["actors"][2]["source_instance"], d
assert "unresolved never forced human" in d["note"], d["note"]
print("[identity] clusters + kinds OK")
PY

echo "[identity] actor kind/source/time/evidence cross-product"
python3 - "$T/metadata-cross.json" "$T/metadata-cross-expected.json" <<'PY'
import itertools, json, pathlib, sys
input_path, expected_path = map(pathlib.Path, sys.argv[1:])
kinds = ("human", "bot_known", "service_known", "unresolved")
sources = ("provider", "project", "operator", "unknown")
classifications = []
for actor_id, (kind, source, has_time, has_evidence) in enumerate(
    itertools.product(kinds, sources, (False, True), (False, True))
):
    classifications.append({
        "actor_id": actor_id,
        "kind": kind,
        "source": source,
        "observed_at": 1700000000 + actor_id if has_time else None,
        "evidence_ref": f"evidence:actor-{actor_id}" if has_evidence else None,
    })
input_doc = {
    "schema": "rh-identity-input/1",
    "actor_count": len(classifications),
    "links": [],
    "actor_kinds": [row["kind"] for row in classifications],
    "actor_kind_sources": [row["source"] for row in classifications],
    "actor_kind_observed_at": [row["observed_at"] for row in classifications],
    "actor_kind_evidence_refs": [row["evidence_ref"] for row in classifications],
    "actors": [
        {"source":"github", "source_instance":"github.com/acme",
         "native_object_id":f"repo-{row['actor_id']}", "display_name":f"repo-{row['actor_id']}", "aliases":[]}
        for row in classifications
    ],
}
input_path.write_text(json.dumps(input_doc, separators=(",", ":")) + "\n")
expected = {
    "actor_count": 64,
    "clusters": [[actor_id] for actor_id in range(64)],
    "identity_revision": 0,
    "actor_kinds": {kind: 16 for kind in kinds},
    "actor_kind_sources": {source: 16 for source in sources},
    "actor_kind_observation_times": {"observed": 32, "unknown": 32},
    "actor_kind_evidence_references": {"present": 32, "unknown": 32},
    "actor_classifications": classifications,
}
expected_path.write_text(json.dumps(expected, sort_keys=True, separators=(",", ":")) + "\n")
PY
"$ROOT/build/rh_cli" identity --input "$T/metadata-cross.json" --out "$T/metadata-cross.out" >/dev/null || fail "actor metadata cross-product"
python3 - "$T/metadata-cross-expected.json" "$T/metadata-cross.out" <<'PY'
import json, sys
expected, actual = json.load(open(sys.argv[1])), json.load(open(sys.argv[2]))
for field in expected:
    assert actual[field] == expected[field], (field, actual.get(field), expected[field])
print("[identity] all 64 actor metadata combinations match independent classification oracles")
PY

echo "[identity] actor metadata × two-edge lifecycle cross-product"
python3 - "$T/metadata-lifecycle.json" "$T/metadata-lifecycle-expected.json" <<'PY'
import itertools, json, pathlib, sys

input_path, expected_path = map(pathlib.Path, sys.argv[1:])
kinds = ("human", "bot_known", "service_known", "unresolved")
sources = ("provider", "project", "operator", "unknown")
metadata = tuple(itertools.product(kinds, sources, (False, True), (False, True)))
lifecycles = tuple(itertools.product(("accepted", "proposed", "rejected", "revoked"), repeat=2))
actor_count = len(metadata) * len(lifecycles) * 3
links = []
actor_kinds = []
actor_kind_sources = []
actor_kind_observed_at = []
actor_kind_evidence_refs = []
classifications = []
kind_counts = {kind: 0 for kind in kinds}
source_counts = {source: 0 for source in sources}
time_counts = {"observed": 0, "unknown": 0}
evidence_counts = {"present": 0, "unknown": 0}
parent = list(range(actor_count))

def find(actor):
    while parent[actor] != actor:
        actor = parent[actor]
    return actor

for lifecycle_index, states in enumerate(lifecycles):
    for metadata_index in range(len(metadata)):
        first_actor = (lifecycle_index * len(metadata) + metadata_index) * 3
        for edge_index, (left, right) in enumerate(((0, 1), (1, 2))):
            links.append({
                "a": first_actor + left,
                "b": first_actor + right,
                "state": states[edge_index],
                "revision_added": edge_index + 1,
            })
        for position in range(3):
            actor_id = first_actor + position
            kind, source, has_time, has_evidence = metadata[(metadata_index + position * 21) % len(metadata)]
            observed_at = 1700000000 + actor_id if has_time else None
            evidence_ref = f"evidence:actor-{actor_id}" if has_evidence else None
            actor_kinds.append(kind)
            actor_kind_sources.append(source)
            actor_kind_observed_at.append(observed_at)
            actor_kind_evidence_refs.append(evidence_ref)
            classifications.append({
                "actor_id": actor_id,
                "kind": kind,
                "source": source,
                "observed_at": observed_at,
                "evidence_ref": evidence_ref,
            })
            kind_counts[kind] += 1
            source_counts[source] += 1
            time_counts["observed" if has_time else "unknown"] += 1
            evidence_counts["present" if has_evidence else "unknown"] += 1
    for link in links[lifecycle_index * len(metadata) * 2:(lifecycle_index + 1) * len(metadata) * 2]:
        if link["state"] == "accepted":
            left, right = find(link["a"]), find(link["b"])
            parent[max(left, right)] = min(left, right)

clusters = {}
for actor in range(actor_count):
    clusters.setdefault(find(actor), []).append(actor)
document = {
    "schema": "rh-identity-input/1",
    "actor_count": actor_count,
    "links": links,
    "actor_kinds": actor_kinds,
    "actor_kind_sources": actor_kind_sources,
    "actor_kind_observed_at": actor_kind_observed_at,
    "actor_kind_evidence_refs": actor_kind_evidence_refs,
}
expected = {
    "actor_count": actor_count,
    "clusters": list(clusters.values()),
    "identity_revision": max((link["revision_added"] for link in links
                               if link["state"] in ("accepted", "revoked")), default=0),
    "actor_kinds": kind_counts,
    "actor_kind_sources": source_counts,
    "actor_kind_observation_times": time_counts,
    "actor_kind_evidence_references": evidence_counts,
    "actor_classifications": classifications,
}
input_path.write_text(json.dumps(document, separators=(",", ":")) + "\n")
expected_path.write_text(json.dumps(expected, sort_keys=True, separators=(",", ":")) + "\n")
PY
"$ROOT/build/rh_cli" identity --input "$T/metadata-lifecycle.json" --out "$T/metadata-lifecycle.out" >/dev/null || fail "actor metadata and link lifecycle cross-product"
python3 - "$T/metadata-lifecycle-expected.json" "$T/metadata-lifecycle.out" <<'PY'
import json, sys
expected, actual = json.load(open(sys.argv[1])), json.load(open(sys.argv[2]))
for field, value in expected.items():
    assert actual[field] == value, (field, actual.get(field), value)
print("[identity] all 1,024 lifecycle/metadata pairings match independent classification and graph oracles")
PY

echo "[identity] actor metadata × triangle lifecycle cross-product"
python3 - "$T/metadata-triangle.json" "$T/metadata-triangle-expected.json" <<'PY'
import itertools, json, pathlib, sys

input_path, expected_path = map(pathlib.Path, sys.argv[1:])
states = ("accepted", "proposed", "rejected", "revoked")
kinds = ("human", "bot_known", "service_known", "unresolved")
sources = ("provider", "project", "operator", "unknown")
lifecycles = tuple(itertools.product(states, repeat=3))
metadata = tuple(itertools.product(kinds, sources, (False, True), (False, True)))
edges = ((0, 1), (1, 2), (2, 0))
actor_count = len(lifecycles) * len(metadata) * 3
links = []
actor_kinds = []
actor_kind_sources = []
actor_kind_observed_at = []
actor_kind_evidence_refs = []
classifications = []
kind_counts = {kind: 0 for kind in kinds}
source_counts = {source: 0 for source in sources}
time_counts = {"observed": 0, "unknown": 0}
evidence_counts = {"present": 0, "unknown": 0}
parent = list(range(actor_count))

def find(actor):
    while parent[actor] != actor:
        actor = parent[actor]
    return actor

for lifecycle_index, lifecycle in enumerate(lifecycles):
    for metadata_index in range(len(metadata)):
        first_actor = (lifecycle_index * len(metadata) + metadata_index) * 3
        for edge_index, (left, right) in enumerate(edges):
            links.append({
                "a": first_actor + left,
                "b": first_actor + right,
                "state": lifecycle[edge_index],
                "revision_added": edge_index + 1,
            })
        for position in range(3):
            actor_id = first_actor + position
            kind, source, has_time, has_evidence = metadata[(metadata_index + position * 21) % len(metadata)]
            observed_at = 1800000000 + actor_id if has_time else None
            evidence_ref = f"evidence:triangle-actor-{actor_id}" if has_evidence else None
            actor_kinds.append(kind)
            actor_kind_sources.append(source)
            actor_kind_observed_at.append(observed_at)
            actor_kind_evidence_refs.append(evidence_ref)
            classifications.append({
                "actor_id": actor_id,
                "kind": kind,
                "source": source,
                "observed_at": observed_at,
                "evidence_ref": evidence_ref,
            })
            kind_counts[kind] += 1
            source_counts[source] += 1
            time_counts["observed" if has_time else "unknown"] += 1
            evidence_counts["present" if has_evidence else "unknown"] += 1
        for edge_index, (left, right) in enumerate(edges):
            if lifecycle[edge_index] == "accepted":
                left_root, right_root = find(first_actor + left), find(first_actor + right)
                parent[max(left_root, right_root)] = min(left_root, right_root)

clusters = {}
for actor in range(actor_count):
    clusters.setdefault(find(actor), []).append(actor)
cluster_id_by_actor = [find(actor) for actor in range(actor_count)]
document = {
    "schema": "rh-identity-input/1",
    "actor_count": actor_count,
    "links": links,
    "actor_kinds": actor_kinds,
    "actor_kind_sources": actor_kind_sources,
    "actor_kind_observed_at": actor_kind_observed_at,
    "actor_kind_evidence_refs": actor_kind_evidence_refs,
}
expected = {
    "actor_count": actor_count,
    "clusters": list(clusters.values()),
    "cluster_id_by_actor": cluster_id_by_actor,
    "identity_revision": max((link["revision_added"] for link in links
                               if link["state"] in ("accepted", "revoked")), default=0),
    "actor_kinds": kind_counts,
    "actor_kind_sources": source_counts,
    "actor_kind_observation_times": time_counts,
    "actor_kind_evidence_references": evidence_counts,
    "actor_classifications": classifications,
    "accepted_actor_clusters": len(clusters),
    "known_human_accounts": kind_counts["human"],
}
input_path.write_text(json.dumps(document, separators=(",", ":")) + "\n")
expected_path.write_text(json.dumps(expected, sort_keys=True, separators=(",", ":")) + "\n")
PY
"$ROOT/build/rh_cli" identity --input "$T/metadata-triangle.json" --out "$T/metadata-triangle.out" >/dev/null || fail "actor metadata and triangle lifecycle cross-product"
python3 - "$T/metadata-triangle-expected.json" "$T/metadata-triangle.out" <<'PY'
import json, sys
expected, actual = json.load(open(sys.argv[1])), json.load(open(sys.argv[2]))
for field, value in expected.items():
    if field in ("accepted_actor_clusters", "known_human_accounts"):
        continue
    assert actual[field] == value, (field, actual.get(field), value)
metrics = {metric["key"]: metric["value"] for metric in actual["metrics"]}
assert metrics["contributor.accepted_actor_clusters"] == expected["accepted_actor_clusters"], metrics
assert metrics["contributor.known_human_accounts"] == expected["known_human_accounts"], metrics
print("[identity] all 4,096 triangle lifecycle/metadata pairings match independent graph and classification oracles")
PY

echo "[identity] rejecting a link changes nothing; revoking recomputes"
"$ROOT/build/rh_cli" identity --input "$T/b.json" --out "$T/b.out" >/dev/null || fail "B run"
python3 - "$T/a.out" "$T/b.out" <<'PY'
import json, sys
a = json.load(open(sys.argv[1]))
b = json.load(open(sys.argv[2]))
# A has an extra accepted link (1-2); B has it revoked. Revision drops and
# the cluster splits. The revision follows the ledger watermark, so revoking
# a link cannot move the snapshot key backwards.
assert a["identity_revision"] == 2 and b["identity_revision"] == 4, (a, b)
assert b["clusters"] == [[0, 1], [2], [3]], b["clusters"]
assert b["cluster_id_by_actor"] == [0, 0, 2, 3], b["cluster_id_by_actor"]
print("[identity] revoke recompute OK")
PY

echo "[identity] proposed/rejected-only ledgers never merge"
cat > "$T/none.json" <<'JSON'
{"schema":"rh-identity-input/1","actor_count":3,"links":[{"a":0,"b":1,"state":"proposed"},{"a":1,"b":2,"state":"rejected"}]}
JSON
"$ROOT/build/rh_cli" identity --input "$T/none.json" --out "$T/none.out" >/dev/null || fail "none run"
python3 - "$T/none.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["identity_revision"] == 0 and d["cluster_count"] == 3, d
assert d["metrics"][0]["value"] == 3, d
assert d["metrics"][0]["quality_dimensions"] == {
    "completeness": "complete",
    "freshness": "unknown",
    "validity": "valid",
    "provenance": "evidence_backed",
}, d
assert d["metrics"][1]["status"] == "unsupported" and d["metrics"][1]["value"] is None, d
assert d["metrics"][1]["reason"] == "actor-kind-classification-not-supplied", d
assert d["metrics"][1]["evidence"] == ["identity-input"], d
assert d["metrics"][1]["quality_dimensions"] == {
    "completeness": "unknown",
    "freshness": "unknown",
    "validity": "unknown",
    "provenance": "evidence_backed",
}, d
assert d["clusters"] == [[0], [1], [2]], d["clusters"]
print("[identity] no-op links OK")
PY

echo "[identity] exhaustive two-edge lifecycle cross-product"
python3 - "$T" <<'PY'
import itertools, json, pathlib, sys
root = pathlib.Path(sys.argv[1])
states = ("accepted", "proposed", "rejected", "revoked")
expected = {}
for case, pair in enumerate(itertools.product(states, repeat=2)):
    links = [
        {"a": a, "b": b, "state": state, "revision_added": index + 1}
        for index, ((a, b), state) in enumerate(zip(((0, 1), (1, 2)), pair))
    ]
    source = {"schema": "rh-identity-input/1", "actor_count": 3, "links": links}
    (root / f"cross-{case:02d}.json").write_text(json.dumps(source, separators=(",", ":")) + "\n")

    # Independent oracle: only accepted edges join actors. The revision is the
    # maximum ledger watermark that changed the accepted identity graph.
    parent = list(range(3))
    def find(actor):
        while parent[actor] != actor:
            actor = parent[actor]
        return actor
    for link in links:
        if link["state"] == "accepted":
            left, right = find(link["a"]), find(link["b"])
            parent[max(left, right)] = min(left, right)
    clusters = {}
    for actor in range(3):
        clusters.setdefault(find(actor), []).append(actor)
    expected[f"{case:02d}"] = {
        "clusters": list(clusters.values()),
        "revision": max((link["revision_added"] for link in links
                         if link["state"] in ("accepted", "revoked")), default=0),
    }
(root / "cross-expected.json").write_text(json.dumps(expected, sort_keys=True, separators=(",", ":")) + "\n")
PY
for case in 00 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15; do
  "$ROOT/build/rh_cli" identity --input "$T/cross-$case.json" --out "$T/cross-$case.out" >/dev/null || fail "lifecycle cross-product $case"
done
python3 - "$T/cross-expected.json" "$T" <<'PY'
import json, pathlib, sys
expected, root = json.load(open(sys.argv[1])), pathlib.Path(sys.argv[2])
for case, contract in expected.items():
    actual = json.load(open(root / f"cross-{case}.out"))
    assert actual["clusters"] == contract["clusters"], (case, actual, contract)
    assert actual["identity_revision"] == contract["revision"], (case, actual, contract)
print("[identity] all 16 lifecycle combinations match independent cluster/revision oracle")
PY

echo "[identity] exhaustive three-edge lifecycle cross-product"
python3 - "$T" <<'PY'
import itertools, json, pathlib, sys
root = pathlib.Path(sys.argv[1])
states = ("accepted", "proposed", "rejected", "revoked")
expected = {}
for case, chain in enumerate(itertools.product(states, repeat=3)):
    links = [
        {"a": actor, "b": actor + 1, "state": state, "revision_added": index + 1}
        for index, (actor, state) in enumerate(zip(range(3), chain))
    ]
    source = {"schema": "rh-identity-input/1", "actor_count": 4, "links": links}
    (root / f"chain-{case:02d}.json").write_text(json.dumps(source, separators=(",", ":")) + "\n")

    # Independent oracle: only accepted links join; the revision watermark
    # advances for accepted and revoked lifecycle entries.
    parent = list(range(4))
    def find(actor):
        while parent[actor] != actor:
            actor = parent[actor]
        return actor
    for link in links:
        if link["state"] == "accepted":
            left, right = find(link["a"]), find(link["b"])
            parent[max(left, right)] = min(left, right)
    clusters = {}
    for actor in range(4):
        clusters.setdefault(find(actor), []).append(actor)
    expected[f"{case:02d}"] = {
        "clusters": list(clusters.values()),
        "revision": max((link["revision_added"] for link in links
                         if link["state"] in ("accepted", "revoked")), default=0),
    }
(root / "chain-expected.json").write_text(json.dumps(expected, sort_keys=True, separators=(",", ":")) + "\n")
PY
python3 - "$ROOT/build/rh_cli" "$T" <<'PY'
import json, pathlib, subprocess, sys
binary, root = sys.argv[1], pathlib.Path(sys.argv[2])
expected = json.load(open(root / "chain-expected.json"))
for case, contract in expected.items():
    source, output = root / f"chain-{case}.json", root / f"chain-{case}.out"
    subprocess.run([binary, "identity", "--input", str(source), "--out", str(output)], check=True, stdout=subprocess.DEVNULL)
    actual = json.load(open(output))
    assert actual["clusters"] == contract["clusters"], (case, actual, contract)
    assert actual["identity_revision"] == contract["revision"], (case, actual, contract)
print("[identity] all 64 three-edge lifecycle combinations match independent cluster/revision oracle")
PY

echo "[identity] exhaustive four-edge cycle lifecycle cross-product"
python3 - "$T" <<'PY'
import itertools, json, pathlib, sys
root = pathlib.Path(sys.argv[1])
states = ("accepted", "proposed", "rejected", "revoked")
edges = ((0, 1), (1, 2), (2, 3), (3, 0))
expected = {}
for case, cycle in enumerate(itertools.product(states, repeat=len(edges))):
    links = [
        {"a": a, "b": b, "state": state, "revision_added": index + 1}
        for index, ((a, b), state) in enumerate(zip(edges, cycle))
    ]
    source = {"schema": "rh-identity-input/1", "actor_count": 4, "links": links}
    (root / f"cycle-{case:03d}.json").write_text(json.dumps(source, separators=(",", ":")) + "\n")

    # This oracle is independent of the CLI's clustering implementation:
    # accepted cycle edges union components; lifecycle watermark advances
    # only for accepted or revoked links.
    parent = list(range(4))

    def find(actor):
        while parent[actor] != actor:
            actor = parent[actor]
        return actor

    for link in links:
        if link["state"] == "accepted":
            left, right = find(link["a"]), find(link["b"])
            parent[max(left, right)] = min(left, right)
    clusters = {}
    for actor in range(4):
        clusters.setdefault(find(actor), []).append(actor)
    expected[f"{case:03d}"] = {
        "clusters": list(clusters.values()),
        "revision": max((link["revision_added"] for link in links
                         if link["state"] in ("accepted", "revoked")), default=0),
    }
(root / "cycle-expected.json").write_text(json.dumps(expected, sort_keys=True, separators=(",", ":")) + "\n")
PY
python3 - "$ROOT/build/rh_cli" "$T" <<'PY'
import json, pathlib, subprocess, sys
binary, root = sys.argv[1], pathlib.Path(sys.argv[2])
expected = json.load(open(root / "cycle-expected.json"))
for case, contract in expected.items():
    source, output = root / f"cycle-{case}.json", root / f"cycle-{case}.out"
    subprocess.run([binary, "identity", "--input", str(source), "--out", str(output)], check=True, stdout=subprocess.DEVNULL)
    actual = json.load(open(output))
    assert actual["clusters"] == contract["clusters"], (case, actual, contract)
    assert actual["identity_revision"] == contract["revision"], (case, actual, contract)
print("[identity] all 256 four-edge cycle lifecycle combinations match independent cluster/revision oracle")
PY

echo "[identity] exhaustive four-edge star lifecycle cross-product"
python3 - "$T" <<'PY'
import itertools, json, pathlib, sys
root = pathlib.Path(sys.argv[1])
states = ("accepted", "proposed", "rejected", "revoked")
edges = ((0, 1), (0, 2), (0, 3), (0, 4))
expected = {}
for case, star in enumerate(itertools.product(states, repeat=len(edges))):
    links = [
        {"a": a, "b": b, "state": state, "revision_added": index + 1}
        for index, ((a, b), state) in enumerate(zip(edges, star))
    ]
    source = {"schema": "rh-identity-input/1", "actor_count": 5, "links": links}
    (root / f"star-{case:03d}.json").write_text(json.dumps(source, separators=(",", ":")) + "\n")

    # Independent star-graph oracle: only accepted spokes join the center to
    # leaves; accepted/revoked lifecycle entries advance the ledger watermark.
    parent = list(range(5))

    def find(actor):
        while parent[actor] != actor:
            actor = parent[actor]
        return actor

    for link in links:
        if link["state"] == "accepted":
            left, right = find(link["a"]), find(link["b"])
            parent[max(left, right)] = min(left, right)
    clusters = {}
    for actor in range(5):
        clusters.setdefault(find(actor), []).append(actor)
    expected[f"{case:03d}"] = {
        "clusters": list(clusters.values()),
        "revision": max((link["revision_added"] for link in links
                         if link["state"] in ("accepted", "revoked")), default=0),
    }
(root / "star-expected.json").write_text(json.dumps(expected, sort_keys=True, separators=(",", ":")) + "\n")
PY
python3 - "$ROOT/build/rh_cli" "$T" <<'PY'
import json, pathlib, subprocess, sys
binary, root = sys.argv[1], pathlib.Path(sys.argv[2])
expected = json.load(open(root / "star-expected.json"))
for case, contract in expected.items():
    source, output = root / f"star-{case}.json", root / f"star-{case}.out"
    subprocess.run([binary, "identity", "--input", str(source), "--out", str(output)], check=True, stdout=subprocess.DEVNULL)
    actual = json.load(open(output))
    assert actual["clusters"] == contract["clusters"], (case, actual, contract)
    assert actual["identity_revision"] == contract["revision"], (case, actual, contract)
print("[identity] all 256 four-edge star lifecycle combinations match independent cluster/revision oracle")
PY

echo "[identity] exhaustive five-edge chain lifecycle cross-product"
python3 - "$T" <<'PY'
import itertools, json, pathlib, sys
root = pathlib.Path(sys.argv[1])
states = ("accepted", "proposed", "rejected", "revoked")
edges = tuple((actor, actor + 1) for actor in range(5))
expected = {}
for case, chain in enumerate(itertools.product(states, repeat=len(edges))):
    links = [
        {"a": a, "b": b, "state": state, "revision_added": index + 1}
        for index, ((a, b), state) in enumerate(zip(edges, chain))
    ]
    source = {"schema": "rh-identity-input/1", "actor_count": 6, "links": links}
    (root / f"chain5-{case:04d}.json").write_text(json.dumps(source, separators=(",", ":")) + "\n")

    # Independent path oracle: accepted edges union adjacent actors; only
    # accepted and revoked entries advance the visible ledger revision.
    parent = list(range(6))

    def find(actor):
        while parent[actor] != actor:
            actor = parent[actor]
        return actor

    for link in links:
        if link["state"] == "accepted":
            left, right = find(link["a"]), find(link["b"])
            parent[max(left, right)] = min(left, right)
    clusters = {}
    for actor in range(6):
        clusters.setdefault(find(actor), []).append(actor)
    expected[f"{case:04d}"] = {
        "clusters": list(clusters.values()),
        "revision": max((link["revision_added"] for link in links
                         if link["state"] in ("accepted", "revoked")), default=0),
    }
(root / "chain5-expected.json").write_text(json.dumps(expected, sort_keys=True, separators=(",", ":")) + "\n")
PY
python3 - "$ROOT/build/rh_cli" "$T" <<'PY'
import json, pathlib, subprocess, sys
binary, root = sys.argv[1], pathlib.Path(sys.argv[2])
expected = json.load(open(root / "chain5-expected.json"))
for case, contract in expected.items():
    source, output = root / f"chain5-{case}.json", root / f"chain5-{case}.out"
    subprocess.run([binary, "identity", "--input", str(source), "--out", str(output)], check=True, stdout=subprocess.DEVNULL)
    actual = json.load(open(output))
    assert actual["clusters"] == contract["clusters"], (case, actual, contract)
    assert actual["identity_revision"] == contract["revision"], (case, actual, contract)
print("[identity] all 1,024 five-edge chain lifecycle combinations match independent cluster/revision oracle")
PY

echo "[identity] exhaustive six-edge chain lifecycle cross-product"
python3 - "$ROOT/build/rh_cli" "$T" <<'PY'
import itertools, json, pathlib, subprocess, sys
binary, root = sys.argv[1], pathlib.Path(sys.argv[2])
states = ("accepted", "proposed", "rejected", "revoked")
edges = tuple((actor, actor + 1) for actor in range(6))
for case, lifecycle in enumerate(itertools.product(states, repeat=len(edges))):
    links = [
        {"a": left, "b": right, "state": state, "revision_added": index + 1}
        for index, ((left, right), state) in enumerate(zip(edges, lifecycle))
    ]
    source = {"schema": "rh-identity-input/1", "actor_count": 7, "links": links}
    input_path = root / f"chain6-{case:04d}.json"
    output_path = root / f"chain6-{case:04d}.out"
    input_path.write_text(json.dumps(source, separators=(",", ":")) + "\n")
    subprocess.run([binary, "identity", "--input", str(input_path), "--out", str(output_path)],
                   check=True, stdout=subprocess.DEVNULL)

    # Independent oracle: accepted links alone define the partition; only
    # accepted or revoked ledger entries advance the identity revision.
    parent = list(range(7))

    def find(actor):
        while parent[actor] != actor:
            actor = parent[actor]
        return actor

    for link in links:
        if link["state"] == "accepted":
            left, right = find(link["a"]), find(link["b"])
            parent[max(left, right)] = min(left, right)
    clusters = {}
    for actor in range(7):
        clusters.setdefault(find(actor), []).append(actor)
    revision = max((link["revision_added"] for link in links
                    if link["state"] in ("accepted", "revoked")), default=0)
    actual = json.loads(output_path.read_text())
    assert actual["clusters"] == list(clusters.values()), (case, actual, clusters)
    assert actual["identity_revision"] == revision, (case, actual, revision)
print("[identity] all 4,096 six-edge chain lifecycle combinations match independent cluster/revision oracle")
PY

echo "[identity] exhaustive triangle-with-tail lifecycle cross-product"
python3 - "$T" <<'PY'
import itertools, json, pathlib, sys
root = pathlib.Path(sys.argv[1])
states = ("accepted", "proposed", "rejected", "revoked")
edges = ((0, 1), (1, 2), (2, 0), (2, 3), (3, 4))
expected = {}
for case, graph in enumerate(itertools.product(states, repeat=len(edges))):
    links = [
        {"a": a, "b": b, "state": state, "revision_added": index + 1}
        for index, ((a, b), state) in enumerate(zip(edges, graph))
    ]
    source = {"schema": "rh-identity-input/1", "actor_count": 5, "links": links}
    (root / f"triangle-tail-{case:04d}.json").write_text(json.dumps(source, separators=(",", ":")) + "\n")

    # Independent branched-cycle oracle: union accepted edges in the triangle
    # and tail; revision follows accepted/revoked ledger entries only.
    parent = list(range(5))

    def find(actor):
        while parent[actor] != actor:
            actor = parent[actor]
        return actor

    for link in links:
        if link["state"] == "accepted":
            left, right = find(link["a"]), find(link["b"])
            parent[max(left, right)] = min(left, right)
    clusters = {}
    for actor in range(5):
        clusters.setdefault(find(actor), []).append(actor)
    expected[f"{case:04d}"] = {
        "clusters": list(clusters.values()),
        "revision": max((link["revision_added"] for link in links
                         if link["state"] in ("accepted", "revoked")), default=0),
    }
(root / "triangle-tail-expected.json").write_text(json.dumps(expected, sort_keys=True, separators=(",", ":")) + "\n")
PY
python3 - "$ROOT/build/rh_cli" "$T" <<'PY'
import json, pathlib, subprocess, sys
binary, root = sys.argv[1], pathlib.Path(sys.argv[2])
expected = json.load(open(root / "triangle-tail-expected.json"))
for case, contract in expected.items():
    source, output = root / f"triangle-tail-{case}.json", root / f"triangle-tail-{case}.out"
    subprocess.run([binary, "identity", "--input", str(source), "--out", str(output)], check=True, stdout=subprocess.DEVNULL)
    actual = json.load(open(output))
    assert actual["clusters"] == contract["clusters"], (case, actual, contract)
    assert actual["identity_revision"] == contract["revision"], (case, actual, contract)
print("[identity] all 1,024 triangle-with-tail lifecycle combinations match independent cluster/revision oracle")
PY

echo "[identity] exhaustive four-actor diamond lifecycle cross-product"
python3 - "$T" <<'PY'
import itertools, json, pathlib, sys
root = pathlib.Path(sys.argv[1])
states = ("accepted", "proposed", "rejected", "revoked")
edges = ((0, 1), (0, 2), (1, 2), (1, 3), (2, 3))
expected = {}
for case, diamond in enumerate(itertools.product(states, repeat=len(edges))):
    links = [
        {"a": a, "b": b, "state": state, "revision_added": index + 1}
        for index, ((a, b), state) in enumerate(zip(edges, diamond))
    ]
    source = {"schema": "rh-identity-input/1", "actor_count": 4, "links": links}
    (root / f"diamond-{case:04d}.json").write_text(json.dumps(source, separators=(",", ":")) + "\n")

    # Independent diamond oracle: accepted edges form components; accepted
    # and revoked entries alone advance the identity revision watermark.
    parent = list(range(4))

    def find(actor):
        while parent[actor] != actor:
            actor = parent[actor]
        return actor

    for link in links:
        if link["state"] == "accepted":
            left, right = find(link["a"]), find(link["b"])
            parent[max(left, right)] = min(left, right)
    clusters = {}
    for actor in range(4):
        clusters.setdefault(find(actor), []).append(actor)
    expected[f"{case:04d}"] = {
        "clusters": list(clusters.values()),
        "revision": max((link["revision_added"] for link in links
                         if link["state"] in ("accepted", "revoked")), default=0),
    }
(root / "diamond-expected.json").write_text(json.dumps(expected, sort_keys=True, separators=(",", ":")) + "\n")
PY
python3 - "$ROOT/build/rh_cli" "$T" <<'PY'
import json, pathlib, subprocess, sys
binary, root = sys.argv[1], pathlib.Path(sys.argv[2])
expected = json.load(open(root / "diamond-expected.json"))
for case, contract in expected.items():
    source, output = root / f"diamond-{case}.json", root / f"diamond-{case}.out"
    subprocess.run([binary, "identity", "--input", str(source), "--out", str(output)], check=True, stdout=subprocess.DEVNULL)
    actual = json.load(open(output))
    assert actual["clusters"] == contract["clusters"], (case, actual, contract)
    assert actual["identity_revision"] == contract["revision"], (case, actual, contract)
print("[identity] all 1,024 diamond lifecycle combinations match independent cluster/revision oracle")
PY

echo "[identity] endpoint orientation and link-order invariance"
python3 - "$ROOT/build/rh_cli" "$T" <<'PY'
import itertools, json, pathlib, subprocess, sys
binary, root = sys.argv[1], pathlib.Path(sys.argv[2])
edges = ((0, 1), (1, 2), (2, 3), (3, 0))
patterns = (
    ("accepted", "accepted", "accepted", "accepted"),
    ("accepted", "proposed", "accepted", "rejected"),
    ("accepted", "proposed", "accepted", "revoked"),
    ("revoked", "revoked", "revoked", "revoked"),
)
cases = 0
for pattern_index, states in enumerate(patterns):
    base_links = [
        {"a": left, "b": right, "state": state, "revision_added": index + 1}
        for index, ((left, right), state) in enumerate(zip(edges, states))
    ]
    for permutation_index, order in enumerate(itertools.permutations(range(4))):
        for reverse_mask in range(16):
            links = []
            for position, edge_index in enumerate(order):
                link = dict(base_links[edge_index])
                if reverse_mask & (1 << edge_index):
                    link["a"], link["b"] = link["b"], link["a"]
                links.append(link)
            source = {"schema": "rh-identity-input/1", "actor_count": 4, "links": links}
            key = f"{pattern_index:02d}-{permutation_index:02d}-{reverse_mask:02d}"
            input_path, output_path = root / f"order-{key}.json", root / f"order-{key}.out"
            input_path.write_text(json.dumps(source, separators=(",", ":")) + "\n")

            # Recompute the expected partition from undirected accepted edges;
            # order and endpoint orientation do not enter this oracle.
            parent = list(range(4))

            def find(actor):
                while parent[actor] != actor:
                    actor = parent[actor]
                return actor

            for link in base_links:
                if link["state"] == "accepted":
                    left, right = find(link["a"]), find(link["b"])
                    parent[max(left, right)] = min(left, right)
            clusters = {}
            for actor in range(4):
                clusters.setdefault(find(actor), []).append(actor)
            expected_clusters = list(clusters.values())
            expected_revision = max(
                (link["revision_added"] for link in base_links
                 if link["state"] in ("accepted", "revoked")),
                default=0,
            )
            subprocess.run(
                [binary, "identity", "--input", str(input_path), "--out", str(output_path)],
                check=True, stdout=subprocess.DEVNULL,
            )
            actual = json.load(open(output_path))
            assert actual["clusters"] == expected_clusters, (key, actual, expected_clusters)
            assert actual["identity_revision"] == expected_revision, (key, actual, expected_revision)
            cases += 1
assert cases == 1536, cases
print("[identity] all 1,536 cyclic edge-order/orientation cases match independent cluster/revision oracles")
PY

echo "[identity] determinism"
"$ROOT/build/rh_cli" identity --input "$T/a.json" --out "$T/a2.out" >/dev/null || fail "rerun"
cmp -s "$T/a.out" "$T/a2.out" || fail "identity output not deterministic"

echo "[identity] malformed input fails closed"
python3 - "$T/a.json" "$T/badnative.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["actor_count"] += 1
d["actor_kinds"].append("human")
d["actor_kind_sources"].append("provider")
d["actors"].append(dict(d["actors"][0]))
json.dump(d, open(sys.argv[2], "w", encoding="utf-8"), separators=(",", ":"))
PY
set +e
printf '{"schema":"rh-identity-input/2","actor_count":1,"links":[]}' > "$T/badschema.json"
"$ROOT/build/rh_cli" identity --input "$T/badschema.json" --out "$T/x" >/dev/null 2>&1; rc_schema=$?
printf '{"schema":"rh-identity-input/1","actor_count":2,"links":[{"a":0,"b":1,"state":"maybe"}]}' > "$T/badstate.json"
"$ROOT/build/rh_cli" identity --input "$T/badstate.json" --out "$T/x" >/dev/null 2>&1; rc_state=$?
printf '{"schema":"rh-identity-input/1","actor_count":2,"links":[{"a":0,"b":5,"state":"accepted"}]}' > "$T/badactor.json"
"$ROOT/build/rh_cli" identity --input "$T/badactor.json" --out "$T/x" >/dev/null 2>&1; rc_actor=$?
printf '{"schema":"rh-identity-input/1","actor_count":2,"links":[{"a":0,"b":1,"state":"accepted"}],"actor_kinds":["human","alien"]}' > "$T/badkind.json"
"$ROOT/build/rh_cli" identity --input "$T/badkind.json" --out "$T/x" >/dev/null 2>&1; rc_kind=$?
printf '{"schema":"rh-identity-input/1","actor_count":2,"links":[{"a":0,"b":1,"state":"accepted"}]}' > "$T/bad-revision.json"
"$ROOT/build/rh_cli" identity --input "$T/bad-revision.json" --out "$T/x" >/dev/null 2>&1; rc_revision=$?
printf '{"schema":"rh-identity-input/1","actor_count":2,"links":[{"a":0,"b":1,"state":"revoked","revision_added":0}]}' > "$T/bad-revoked-revision.json"
"$ROOT/build/rh_cli" identity --input "$T/bad-revoked-revision.json" --out "$T/x" >/dev/null 2>&1; rc_revoked_revision=$?
printf '{"schema":"rh-identity-input/1","actor_count":2,"links":[],"actor_kinds":["human","unresolved"],"actor_kind_sources":["provider","made-up"]}' > "$T/badkindsource.json"
"$ROOT/build/rh_cli" identity --input "$T/badkindsource.json" --out "$T/x" >/dev/null 2>&1; rc_kind_source=$?
printf '{"schema":"rh-identity-input/1","actor_count":2,"links":[],"actor_kinds":["human","unresolved"],"actor_kind_sources":["project"]}' > "$T/badkindsourcecount.json"
"$ROOT/build/rh_cli" identity --input "$T/badkindsourcecount.json" --out "$T/x" >/dev/null 2>&1; rc_kind_source_count=$?
printf '{"schema":"rh-identity-input/1","actor_count":2,"links":[],"actor_kinds":["human","unresolved"],"actor_kind_observed_at":[1]}' > "$T/badkindtimecount.json"
"$ROOT/build/rh_cli" identity --input "$T/badkindtimecount.json" --out "$T/x" >/dev/null 2>&1; rc_kind_time_count=$?
printf '{"schema":"rh-identity-input/1","actor_count":1,"links":[],"actor_kinds":["human"],"actor_kind_observed_at":[-1]}' > "$T/badkindtime.json"
"$ROOT/build/rh_cli" identity --input "$T/badkindtime.json" --out "$T/x" >/dev/null 2>&1; rc_kind_time=$?
printf '{"schema":"rh-identity-input/1","actor_count":1,"links":[],"actor_kind_observed_at":[1]}' > "$T/kindtimewithoutkind.json"
"$ROOT/build/rh_cli" identity --input "$T/kindtimewithoutkind.json" --out "$T/x" >/dev/null 2>&1; rc_kind_time_without_kind=$?
printf '{"schema":"rh-identity-input/1","actor_count":2,"links":[],"actor_kinds":["human","unresolved"],"actor_kind_evidence_refs":["evidence:one"]}' > "$T/badkindrefcount.json"
"$ROOT/build/rh_cli" identity --input "$T/badkindrefcount.json" --out "$T/x" >/dev/null 2>&1; rc_kind_ref_count=$?
printf '{"schema":"rh-identity-input/1","actor_count":1,"links":[],"actor_kinds":["human"],"actor_kind_evidence_refs":[""]}' > "$T/badkindref.json"
"$ROOT/build/rh_cli" identity --input "$T/badkindref.json" --out "$T/x" >/dev/null 2>&1; rc_kind_ref=$?
printf '{"schema":"rh-identity-input/1","actor_count":1,"links":[],"actor_kind_evidence_refs":["evidence:one"]}' > "$T/kindrefwithoutkind.json"
"$ROOT/build/rh_cli" identity --input "$T/kindrefwithoutkind.json" --out "$T/x" >/dev/null 2>&1; rc_kind_ref_without_kind=$?
"$ROOT/build/rh_cli" identity --input "$T/badnative.json" --out "$T/x" >/dev/null 2>&1; rc_native_duplicate=$?
"$ROOT/build/rh_cli" identity --input "$T/nope.json" --out "$T/x" >/dev/null 2>&1; rc_missing=$?
set -e
for rc in "$rc_schema" "$rc_state" "$rc_actor" "$rc_kind" "$rc_revision" "$rc_revoked_revision" "$rc_kind_source" "$rc_kind_source_count" "$rc_kind_time_count" "$rc_kind_time" "$rc_kind_time_without_kind" "$rc_kind_ref_count" "$rc_kind_ref" "$rc_kind_ref_without_kind" "$rc_native_duplicate" "$rc_missing"; do
  [[ "$rc" -eq 4 ]] || fail "malformed identity input must exit 4 (got $rc)"
done

echo "[identity] optional evidence-store verifies content-addressed actor evidence"
mkdir -p "$T/evidence"
printf 'actor-kind source evidence\n' > "$T/kind-evidence.txt"
evidence_name=$("$ROOT/build/rh_cli" store put --root "$T/evidence" --file "$T/kind-evidence.txt" | awk '{print $3}')
python3 - "$T/verified-input.json" "$evidence_name" <<'PY'
import json, sys
json.dump({"schema":"rh-identity-input/1","actor_count":1,"links":[],"actor_kinds":["human"],"actor_kind_evidence_refs":[sys.argv[2]]}, open(sys.argv[1], "w"), separators=(",", ":"))
PY
"$ROOT/build/rh_cli" identity --input "$T/verified-input.json" --out "$T/verified.out" --evidence-store "$T/evidence" >/dev/null || fail "verified evidence reference"
python3 - "$T/verified-input.json" "$T/verified.out" <<'PY'
import hashlib, json, sys
r = json.load(open(sys.argv[2] + ".evidence-verification.json"))
assert r["schema"] == "rh-identity-evidence-verification/1" and r["state"] == "verified", r
assert r["verified_reference_count"] == 1, r
assert r["source_input_sha256"] == hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest(), r
assert r["identity_output_sha256"] == hashlib.sha256(open(sys.argv[2], "rb").read()).hexdigest(), r
print("[identity] evidence digest + output binding OK")
PY
python3 - "$T/reviewed-link-input.json" "$evidence_name" <<'PY'
import json, sys
json.dump({"schema":"rh-identity-input/1","actor_count":2,"actors":[{"source":"github","source_instance":"github.com/acme","native_object_id":"1","display_name":"a","aliases":[]},{"source":"gitlab","source_instance":"gitlab.com/acme","native_object_id":"1","display_name":"b","aliases":[]}],"links":[{"a":0,"b":1,"state":"accepted","revision_added":1,"reviewed_by":"maintainer","reviewed_at":1700000000,"review_reason":"Verified shared ownership evidence","evidence_ref":sys.argv[2]}]}, open(sys.argv[1], "w"), separators=(",", ":"))
PY
"$ROOT/build/rh_cli" identity --input "$T/reviewed-link-input.json" --out "$T/reviewed-link.out" --evidence-store "$T/evidence" >/dev/null || fail "evidence-backed accepted identity link"
python3 - "$T/reviewed-link-input.json" "$T/reviewed-link.out" <<'PY'
import hashlib, json, sys
source, output = sys.argv[1:]
d = json.load(open(output + ".evidence-verification.json"))
assert d["verified_reference_count"] == 1 and d["reviewed_link_count"] == 1 and d["reviewed_cross_source_link_count"] == 1, d
n = json.load(open(output + ".identity-review-notices.json"))
assert n["schema"] == "rh-identity-review-notices/1" and n["scope"] == "restricted" and n["notice_count"] == 1, n
input_bytes = open(source, "rb").read()
output_bytes = open(output, "rb").read()
assert n["source_input_sha256"] == hashlib.sha256(input_bytes).hexdigest(), n
assert n["identity_output_sha256"] == hashlib.sha256(output_bytes).hexdigest(), n
notice = n["notices"][0]
assert notice == {"state":"accepted","actor_pair":[0,1],"reviewed_by":"maintainer","reviewed_at":1700000000,"evidence_ref":json.load(open(source))["links"][0]["evidence_ref"],"review_reason":"Verified shared ownership evidence"}, notice
print("[identity] cross-source review evidence + reviewer/time/reason OK")
PY
cp "$T/reviewed-link-input.json" "$T/reviewed-link-valid.json"
python3 - "$T/reviewed-link-valid.json" "$T/same-source-link.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["actors"][1]["source"] = d["actors"][0]["source"]
d["actors"][1]["source_instance"] = d["actors"][0]["source_instance"]
d["actors"][1]["native_object_id"] = "same-source-distinct-account"
d["links"][0].pop("review_reason")
json.dump(d, open(sys.argv[2], "w"), separators=(",", ":"))
PY
"$ROOT/build/rh_cli" identity --input "$T/same-source-link.json" --out "$T/same-source-link.out" --evidence-store "$T/evidence" >/dev/null || fail "same-source reviewed identity link"
python3 - "$T/same-source-link.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1] + ".evidence-verification.json"))
assert d["reviewed_link_count"] == 1 and d["reviewed_cross_source_link_count"] == 0, d
n = json.load(open(sys.argv[1] + ".identity-review-notices.json"))
assert n["notice_count"] == 0 and n["notices"] == [], n
print("[identity] same-source review does not require cross-source rationale")
PY
python3 - "$T/reviewed-link-valid.json" "$T" <<'PY'
import json, sys
source, root = sys.argv[1:]
for state in ("rejected", "revoked"):
    d = json.load(open(source)); d["links"][0]["state"] = state
    json.dump(d, open(f"{root}/{state}-cross-source.json", "w"), separators=(",", ":"))
PY
for review_state in rejected revoked; do
    "$ROOT/build/rh_cli" identity --input "$T/$review_state-cross-source.json" --out "$T/$review_state-cross-source.out" --evidence-store "$T/evidence" >/dev/null || fail "evidence-backed $review_state cross-source link"
    python3 - "$T/$review_state-cross-source.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1] + ".evidence-verification.json"))
assert d["reviewed_link_count"] == 1 and d["reviewed_cross_source_link_count"] == 1, d
PY
done
printf '[identity] reviewed rejected/revoked cross-source links\n'
python3 - "$T/reviewed-link-input.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p)); d["links"][0].pop("evidence_ref")
json.dump(d, open(p, "w"), separators=(",", ":"))
PY
set +e
"$ROOT/build/rh_cli" identity --input "$T/reviewed-link-input.json" --out "$T/unverified-link.out" --evidence-store "$T/evidence" >/dev/null 2>&1
rc_unverified_link=$?
set -e
[[ "$rc_unverified_link" -eq 4 && ! -f "$T/unverified-link.out" ]] || fail "reviewed identity link without evidence must fail closed"
python3 - "$T/reviewed-link-valid.json" "$T" <<'PY'
import json, sys
source, root = sys.argv[1:]
for name, field, value in (("missing-reviewer", "reviewed_by", None), ("negative-review-time", "reviewed_at", -1), ("missing-cross-source-reason", "review_reason", None)):
    d = json.load(open(source))
    if value is None:
        d["links"][0].pop(field)
    else:
        d["links"][0][field] = value
    json.dump(d, open(f"{root}/{name}.json", "w"), separators=(",", ":"))
PY
for invalid_review in missing-reviewer negative-review-time; do
    set +e
    "$ROOT/build/rh_cli" identity --input "$T/$invalid_review.json" --out "$T/$invalid_review.out" --evidence-store "$T/evidence" >/dev/null 2>&1
    rc_invalid_review=$?
    set -e
    [[ "$rc_invalid_review" -eq 4 && ! -f "$T/$invalid_review.out" ]] || fail "invalid reviewed identity metadata must fail closed: $invalid_review"
done
printf 'corrupt\n' > "$T/evidence/$evidence_name"
set +e
"$ROOT/build/rh_cli" identity --input "$T/verified-input.json" --out "$T/corrupt.out" --evidence-store "$T/evidence" >/dev/null 2>&1
rc_corrupt=$?
set -e
[[ "$rc_corrupt" -eq 4 && ! -f "$T/corrupt.out" ]] || fail "corrupt evidence must fail before identity publication"

echo "test_identity_cli OK"
