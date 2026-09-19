#!/usr/bin/env bash
# tools/release-packet.sh — emit a machine-readable release evidence packet
# (M07 beta checklist / M12 release packet) from the actual repository
# state. It reports only what the tree can back up: implemented metric
# definitions, the reviewed source register, milestone stages, and the
# local harness list. It never claims a capability that is not present.
#
# Usage: tools/release-packet.sh [out_dir] [label]
#   RH_PACKET_LABEL overrides label; default "unreleased".
# Deterministic for a given tree+label (no clock is embedded).
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${1:-$ROOT/build}"
LABEL="${2:-${RH_PACKET_LABEL:-unreleased}}"
mkdir -p "$OUT_DIR"

python3 - "$ROOT" "$OUT_DIR" "$LABEL" <<'PY'
import json, os, re, sys

root, out_dir, label = sys.argv[1], sys.argv[2], sys.argv[3]

def read(path):
    with open(path, "r", encoding="utf-8") as fh:
        return fh.read()

# --- implemented metrics from definitions -------------------------------
metrics = []
missing = []
mdef_dir = os.path.join(root, "metrics", "definitions")
for name in sorted(os.listdir(mdef_dir)):
    if not name.endswith(".json"):
        continue
    d = json.loads(read(os.path.join(mdef_dir, name)))
    if d.get("implementation_status") == "implemented":
        assert d.get("denominator_rule"), ("implemented metric without denominator", d.get("key"))
        assert d.get("fixture_references"), ("implemented metric without fixtures", d.get("key"))
        assert d.get("source_requirements"), ("implemented metric without source reqs", d.get("key"))
        metrics.append({
            "key": d["key"],
            "version": d["version"],
            "denominator_rule": d["denominator_rule"],
            "source_requirements": sorted(d["source_requirements"]),
            "fixture_references": sorted(d["fixture_references"]),
        })
    else:
        missing.append(d.get("key", name))

# --- reviewed sources ---------------------------------------------------
reg = json.loads(read(os.path.join(root, "ops", "source-review-register.json")))
sources = [{
    "id": s["id"],
    "kind": s["kind"],
    "capabilities": sorted(s["capabilities"]),
    "unauthorized": sorted(s["unauthorized"]),
    "unsupported": sorted(s["unsupported"]),
    "redistribution": s["redistribution"],
    "retention_days": s["retention_days"],
} for s in sorted(reg["sources"], key=lambda s: s["id"])]

# --- fixture coverage from the F001-F040 catalog ------------------------
fixtures = json.loads(read(os.path.join(root, "fixtures", "fixture-catalog.json")))
fix_counts = {"covered": 0, "partial": 0, "planned": 0}
planned_ids = []
for f in fixtures["fixtures"]:
    fix_counts[f["status"]] += 1
    if f["status"] == "planned":
        planned_ids.append(f["id"])

# --- milestone stages from STATUS --------------------------------------
status = read(os.path.join(root, "STATUS.md"))
stages = {}
for line in status.splitlines():
    m = re.match(r"\|\s*(M\d\d[^|]*?)\s*\|\s*`([a-z_]+)`", line)
    if m:
        stages[m.group(1).strip()] = m.group(2)

# --- local verification harnesses --------------------------------------
harnesses = sorted(n for n in os.listdir(os.path.join(root, "tests"))
                   if n.startswith("test_") and n.endswith(".sh"))

packet = {
    "packet_version": "rh-release-packet/1",
    "release_label": label,
    "catalog": {
        "implemented": len(metrics),
        "candidate_target": 360,
        "not_yet_defined": len(missing),
        "note": "catalog expansion is tracked in M09; 360 is the architecture target, not a promise",
    },
    "milestone_stages": stages,
    "supported_sources": sources,
    "metrics": metrics,
    "missing_metric_keys": missing,
    "fixtures": {
        "total": len(fixtures["fixtures"]),
        "covered": fix_counts["covered"],
        "partial": fix_counts["partial"],
        "planned": fix_counts["planned"],
        "planned_ids": planned_ids,
        "note": "F001-F040; linted by tools/fixture-lint.sh",
    },
    "verification": {
        "local_suite": "tools/check.sh",
        "harnesses": harnesses,
        "run_required": "results are recorded by running tools/check.sh; this packet does not assert a pass",
    },
    "performance": {
        "manifest": "build/bench-manifest.json",
        "note": "dataset digests and counts are deterministic; timings are machine-specific and are not asserted by tests",
    },
    "security_scope": [
        "transport/SSRF guard with post-DNS address check (S002)",
        "parser hardening for JSON/semver/lockfiles (M07-03)",
        "publication suppression gate, not anonymization (S007)",
        "backup/restore refuses corrupt objects (M07-10)",
        "store verification is FNV-1a integrity, not a signature (M07-04)",
        "SHA-256 + HMAC-SHA256 signing/verification (M07-04); symmetric key held separately from workers",
        "verification proves integrity + key possession, not code safety (S011)",
        "policy decisions are four-valued and bound to subject/context/artifact/policy/time digests; unknown never becomes permission (M06)",
    ],
    "limitations": [
        "HTTP listener serves a report directory read-only on loopback (M06-01) with a server-rendered accessible report page at /_report.html (M06-03); a dynamic site and cursor-paginated query API over the store are not yet implemented",
        "release signing uses a shared HMAC key (integrity + key possession), not a public-key signature; third parties cannot verify without the key",
        "notification dedup/cooldown/ack/resolution state can be persisted to a file (--state); policy exception state (--state, rh-policy-state/1) and the correction revision/watermark ledger (--state, rh-corrections-state/1) persist to files too, so approvals survive restarts and correction replay is idempotent; none of these are yet wired to the content-addressed store (M06 durable store persistence pending)",
        "no independent threat-model review or opt-in pilot yet (M07-01, M07 beta)",
        "metric catalog is %d of a 360 target; breadth follows correctness (M09)" % len(metrics),
        "forge normalizers span GitHub, GitLab, Gitea, Forgejo and Bitbucket Cloud (payload-shape fixtures; no live forge API calls); review workflows span mbox/patch series and Gerrit changes (fixtures, no live Gerrit); native VCS: Mercurial, Subversion and Fossil have bounded --repo collectors with retained source/stderr evidence (the local gate uses controlled shims because the tools are absent); non-PR workflow is subject-level patch-series grouping with trailer roles; release-only sources report releases/artifacts with no history; Python/PEP 440 version semantics has a prototype requirements.txt parser; dependency parsers span Cargo, npm, PyPI and Go (declared-requirement subsets, no live registry calls); one inventory format is pinned (CycloneDX) plus SPDX 2.3; distribution data, archives and further ecosystems/inventory formats are not yet implemented (M08)",
        "fixture coverage is %d covered / %d partial / %d planned of F001-F040 (all covered when the suite is green)"
        % (fix_counts["covered"], fix_counts["partial"], fix_counts["planned"]),
    ],
    "rights": "see ops/source-review-register.json; revalidate per connector before enabling",
}

json_path = os.path.join(out_dir, "release-packet.json")
with open(json_path, "w", encoding="utf-8") as fh:
    json.dump(packet, fh, indent=2, sort_keys=True)
    fh.write("\n")

md = []
md.append("# Release evidence packet: %s\n" % label)
md.append("`packet_version`: `rh-release-packet/1`\n")
md.append("## Catalog\n")
md.append("- implemented metrics: **%d** (target 360; %d not yet defined)"
          % (len(metrics), len(missing)))
md.append("- metric keys: " + ", ".join("`%s@%s`" % (m["key"], m["version"]) for m in metrics) + "\n")
md.append("## Fixture coverage (F001-F040)\n")
md.append("- covered: **%d**, partial: %d, planned: %d"
          % (fix_counts["covered"], fix_counts["partial"], fix_counts["planned"]))
md.append("- planned ids: " + (", ".join(planned_ids) or "none") + "\n")
md.append("## Milestone stages\n")
for k in sorted(stages):
    md.append("- %s: `%s`" % (k, stages[k]))
md.append("\n## Supported sources\n")
for s in sources:
    md.append("- `%s` (%s): %s; unauthorized=%s; unsupported=%s; rights=%s/%dd"
              % (s["id"], s["kind"], ",".join(s["capabilities"]),
                 ",".join(s["unauthorized"]) or "none",
                 ",".join(s["unsupported"]) or "none",
                 s["redistribution"], s["retention_days"]))
md.append("\n## Verification\n")
md.append("- local suite: `tools/check.sh`")
md.append("- harnesses: " + ", ".join("`tests/%s`" % h for h in harnesses))
md.append("- this packet does not assert test results; run the suite and attach output\n")
md.append("## Performance\n")
md.append("- manifest: `%s`" % packet["performance"]["manifest"])
md.append("- " + packet["performance"]["note"] + "\n")
md.append("## Security scope\n")
for item in packet["security_scope"]:
    md.append("- " + item)
md.append("\n## Known limitations\n")
for item in packet["limitations"]:
    md.append("- " + item)
md.append("")
with open(os.path.join(out_dir, "release-packet.md"), "w", encoding="utf-8") as fh:
    fh.write("\n".join(md))

print("release-packet OK: %s (%d metrics, %d sources)"
      % (json_path, len(metrics), len(sources)))
PY

# M07-04 optional signing: only when RH_SIGNING_KEY_FILE names a key. The
# key is never read from the repository and never embedded in the packet.
# Without a key the packet is emitted unsigned and marked as such.
KEY="${RH_SIGNING_KEY_FILE:-}"
if [[ -n "$KEY" && -s "$KEY" ]]; then
  if [[ -x "$ROOT/build/rh_cli" ]]; then
    "$ROOT/build/rh_cli" sign --key "$KEY" --subject "$OUT_DIR/release-packet.json" --sig "$OUT_DIR/release-packet.sig"
  else
    echo "release-packet: WARNING rh_cli not built; packet left unsigned" >&2
  fi
else
  echo "release-packet: no RH_SIGNING_KEY_FILE; packet is unsigned (integrity only)" >&2
fi
