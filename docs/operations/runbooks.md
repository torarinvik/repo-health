# Operations runbooks (M07-13)

These are operational procedures for the reference implementation. They
describe what the code in this repository actually does today; they do not
claim capabilities that are still `planned`. Every runbook ends with what
must be recorded — an incident is not closed by memory.

The governing rule is the project's final rule: **never make the system
look more knowledgeable than its evidence allows.** During any incident,
unknown stays unknown; do not substitute a plausible number.

## 1. Provider outage or provider schema change

Trigger: collection for one source family starts failing, or a connector's
contract test fails against a captured payload.

1. Let the per-host quota/backoff in `src/rh_ops.elisa`
   (`rh_host_record_failure`) hold the host off; do not disable it to force
   traffic. Repeated failures raise the wait up to
   `max_backoff_seconds`.
2. Preserve the last committed cursor. Cursors are written only after a
   verified page commit (`src/rh_store.elisa`); an uncommitted page is
   re-fetched with one page of overlap, and record ids dedup.
3. Mark only the affected capability `stale`/`partial`; other capabilities
   for the same project stay observed. This is the M02 coverage
   propagation rule, enforced in `src/rh_query.elisa` scan-status
   breakdown. A missing review feed is not project abandonment.
4. Suppress coverage-derived notifications for the affected capability
   (`src/rh_notify.elisa` outage suppression). Service health (queue age,
   cursor lag, freshness) moves; project activity counters do not.
5. Capture one sanitized sample payload (no credentials, no personal
   fields beyond the register) and add it as a fixture plus a failing
   contract test. Fix, version the fix, and reconcile before declaring the
   source restored.
6. Record: source, capability, first/last failure, sample digest, cursor
   position, fixture added, reconcilation result.

## 2. Bad identity merge

Trigger: an accepted identity link is reported wrong, or a mass merge is
suspected.

1. Revoke the offending link. Accepted links are stored (not just
   clusters), so revocation recomputes the derived clusters and their
   revision; raw events keep their native account ids and are never
   rewritten (`src/rh_identity.elisa`).
2. Recompute cluster-sensitive results and publish them under the new
   identity revision. Results computed under the old revision are
   superseded, not silently edited (`src/rh_correction.elisa`).
3. Freeze person-sensitive publication for the affected subject until a
   human re-reviews it; never publish a trust or reputation score.
4. Add a regression fixture reproducing the bad merge and a test proving
   the derived result changes while the raw ledger does not.
5. Record: link id, direction, who revoked and why, old/new revision,
   superseded result ids, fixture added.

## 3. Corrupt or missing evidence / projection

Trigger: `rh_store_blob_verify` fails, a manifest digest check fails, or
`rh_backup_verify` reports corrupt/missing objects.

1. Stop any publication that would consume the affected evidence. In the
   backup/restore drill, `rh_backup_restore` already refuses to restore an
   object whose digest does not match its name.
2. Compare against the verified backup manifest (`rh_backup_write` /
   `rh_backup_verify`); restore from the last clean object set.
3. If no clean copy exists, re-fetch from the source under limits and
   write new evidence. Never substitute live bytes into a pinned report.
4. Mark affected reports `not_replayable` for the corrupted inputs, and
   keep the label until clean inputs are restored.
5. Note for reviewers: the current digest is FNV-1a. It detects
   accidental corruption; it is **not** a cryptographic signature and is
   not evidence of safety. Release signing is still pending (M07-04).
6. Record: object digest, manifest, backup used, restored/unavailable
   count, replayability change.

## 4. Credential exposure

Trigger: a token or key appears in logs, evidence, a command line, or a
committed file.

1. Revoke the credential at the provider first, then stop the affected
   jobs and cancel queued work; cancel refunds the host's quota token
   (`rh_host_cancel`).
2. Inspect logs and captured evidence for the secret; identify every
   payload that may contain it. `rh_git` sends no `Authorization` header in
   this slice and rejects userinfo in URLs, so a leak here would come from
   an operator mistake, not the collector.
3. Rotate, and add a secret-canary regression test before restoring
   service.
4. Do not redistribute the exposed payload; do not commit the credential
   to "remember" it.
5. Record: credential id, where exposed, revoked-at, payloads affected,
   regression test added.

## 5. Mass false alert

Trigger: a rule fires for many subjects at once, or a publication is
reported misleading.

1. Pause that rule *version*; do not delete its history. Preserve the
   inputs that produced the alerts.
2. Triage data vs design: was the evidence wrong, the metric definition
   wrong, or the wording wrong? These have different fixes and different
   people.
3. Retract or supersede with a written explanation (what changed, which
   subjects, what the corrected statement is). A retraction is not
   evidence the original measurement was a mistake for every subject.
4. Re-run in shadow mode before removing the pause. Add a volume circuit
   breaker if a single rule can flood.
5. Record: rule key+version, first/last alert, subject count, root cause,
   superseding publication id, shadow result.

## 6. Operator or source removal

Trigger: an operator, project, or platform asks us to stop collecting or
to remove their data, or a rights review changes.

1. Locate the rights entry in `ops/source-review-register.json` and its
   contact. Suspend collection for that source/subject.
2. Apply deletion/restriction to raw payloads, projections, caches, and
   exports. Where the raw byte store cannot be deleted by this build, the
   object is de-referenced and excluded from all publication, and that gap
   is recorded honestly.
3. Recompute affected metrics so removed subjects disappear from public
   aggregates (publication suppression gate, `src/rh_privacy.elisa`,
   withholds unknown/private members before any aggregate is published).
4. Record replayability limits: a report whose inputs were unretained is
   no longer replayable, and must say so.
5. Do not reconstruct the removed data from a mirror or cache to evade the
   request.
6. Record: request, authority, scope removed, projections recomputed,
   replayability labels changed.

## 7. Backup restore drill

Trigger: scheduled drill, or recovery after corruption/loss.

1. Restore into a **clean** directory (never over the live store).
2. Verify every object digest with `rh_backup_verify`; require
   `corrupt == 0` and `missing == 0` before trusting the set.
3. Restore with `rh_backup_restore`, which skips any object whose digest
   does not match.
4. Rebuild projections from the restored evidence and replay a sample
   report; compare against the pinned expected outputs.
5. State the restored/unavailable/unknown sets in writing. An unrestored
   backup is not evidence.
6. Record: backup manifest, present/missing/corrupt counts, restored
   count, sample replay result, date and operator.
