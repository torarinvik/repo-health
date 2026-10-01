#!/usr/bin/env python3
"""Exercise findings-policy exception scope using the shared policy verifier."""
import hashlib
import hmac
import json
import pathlib
import subprocess
import sys

cli = pathlib.Path(sys.argv[1])
work = pathlib.Path(sys.argv[2])
findings = work / "findings.json"
transformations = work / "findings.json.transformations.json"
bindings = work / "bindings.json"
base_policy = json.loads((work / "policy-deny.json").read_bytes())
base_result = json.loads((work / "deny.json").read_bytes())
key = bytes.fromhex("aa" * 32)
keyring = work / "approvers.json"
keyring.write_text(json.dumps({
    "schema": "rh-policy-approver-keys/1",
    "approvers": [{"id": "maintainer-17", "key": key.hex()}],
}, separators=(",", ":")) + "\n")
keyring.chmod(0o600)

exception = {
    "rule_id": 7,
    "subject_id": 42,
    "digest": base_result["binding"]["findings_sha256"][:16],
    "context_digest": base_result["binding"]["rule_context_digest"],
    "expires_at": 1700000120,
    "state": "approved",
    "approved_by": "maintainer-17",
    "reason": "temporary reviewed finding waiver",
}

def signed_policy(rule, row):
    message = (
        "rh-policy-approval/1\n%d\n%d\n%s\n%s\n%d\n%d:%s\n%d:%s"
        % (
            row["rule_id"], row["subject_id"], row["digest"].lower(),
            row["context_digest"].lower(), row["expires_at"],
            len(row["approved_by"].encode()), row["approved_by"],
            len(row["reason"].encode()), row["reason"],
        )
    ).encode()
    row["approval_signature"] = hmac.new(key, message, hashlib.sha256).hexdigest()
    return {**base_policy, "rules": [rule], "exceptions": [row]}

def write_policy(name, rule=None, row=None):
    path = work / name
    path.write_text(json.dumps(signed_policy(rule or base_policy["rules"][0], row or dict(exception)), separators=(",", ":")) + "\n")
    return path

def invoke(policy, out, with_keyring):
    command = [
        str(cli), "findings-policy", "--findings", str(findings),
        "--transformations", str(transformations), "--policy", str(policy),
        "--bindings", str(bindings), "--subject-id", "42", "--now", "1700000060",
    ]
    if with_keyring:
        command += ["--approver-keys", str(keyring)]
    command += ["--out", str(out)]
    return subprocess.run(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode

print("[findings-policy] signed waivers require a private keyring and exact rule scope")
policy = write_policy("signed-policy.json")
missing_key_output = work / "no-keyring.json"
assert invoke(policy, missing_key_output, False) == 4 and not missing_key_output.exists()

valid_output = work / "excepted.json"
assert invoke(policy, valid_output, True) == 0
valid = json.loads(valid_output.read_bytes())
row = valid["rule_results"][0]
assert valid["decision"] == "allow" and row["decision"] == "allow"
assert row["excepted"] is True and row["fired"] is False
assert valid["binding"]["rule_context_digest"] == base_result["binding"]["rule_context_digest"]
print("[findings-policy] valid signature authorizes only the matching scoped rule")

expired = dict(exception, expires_at=1700000060)
expired_policy = write_policy("expired-policy.json", row=expired)
expired_output = work / "expired-exception.json"
assert invoke(expired_policy, expired_output, True) == 0
expired_result = json.loads(expired_output.read_bytes())
assert expired_result["decision"] == "deny"
assert expired_result["rule_results"][0]["excepted"] is False
print("[findings-policy] expired waiver does not suppress the local rule")

changed_rule = dict(base_policy["rules"][0], on_violation="warn")
changed_policy = write_policy("changed-rules-policy.json", rule=changed_rule)
changed_output = work / "changed-rules.json"
assert invoke(changed_policy, changed_output, True) == 0
changed = json.loads(changed_output.read_bytes())
assert changed["decision"] == "warn" and changed["rule_results"][0]["excepted"] is False
print("[findings-policy] waiver does not survive a local rule change")

tampered = json.loads(policy.read_bytes())
tampered["exceptions"][0]["reason"] += " changed"
tampered_path = work / "tampered-policy.json"
tampered_path.write_text(json.dumps(tampered, separators=(",", ":")) + "\n")
tampered_output = work / "tampered-exception.json"
assert invoke(tampered_path, tampered_output, True) == 4 and not tampered_output.exists()
print("[findings-policy] a modified signed waiver fails closed")
