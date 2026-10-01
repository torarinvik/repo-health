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
   superseded, not silently edited (`src/rh_correction.elisa`). For every
   superseded public projection snapshot, invalidate its content-addressed
   cache entry with `rh_cli ops delete --root <snapshot-root> --name <snapshot-id>`;
   the corrected run writes a new snapshot bound to the new identity revision.
   The downstream CLI test verifies the old snapshot is missing while the new
   revision's snapshot remains available.
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
5. Note for reviewers: the evidence object name uses FNV-1a. It detects
   accidental corruption; it is **not** a cryptographic signature and is
   not evidence of safety. Release packets can be signed with HMAC-SHA256
   (`rh_cli sign|verify`, M07-04), but that shared-key signature establishes
   integrity and key possession only; it does not establish code safety.
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
   contact. For a whole source instance, create a command based on
   `fixtures/postgres/request-source-stop-command.json`, replacing the source
   UUID, actor, reason, and request time, then run
   `rh_cli postgres --input <request-command.json> --out <stop-result.json>`
   with `RH_DATABASE_URL` configured; the command operation is
   `request_source_stop`. The active stop cancels queued work,
   fences leased workers, and rejects new runs, enqueues, and claims. It cannot
   interrupt a network request already in progress; fencing rejects that
   worker's later database writes. The named operator identity is recorded but
   authenticated by the deployment, not by this command.
2. After reviewing a withdrawal or resolving the request, base a resume
   command on `fixtures/postgres/resolve-source-stop-command.json` and run it
   through the same `rh_cli postgres --input ... --out ...` interface. Resume
   uses the `resolve_source_stop` operation and does not revive canceled work;
   enqueue a fresh collection run only when
   collection is authorized again. The named reviewer identity also requires
   deployment authentication.
3. For one content-addressed raw object, run
   `rh_cli ops delete --root <evidence-root> --name <16-hex-object>`.
   The command serializes with writers, rejects malformed keys, and treats an
   already-absent object as success. Apply the corresponding restriction to
   projections, caches, and exports separately; this command does not discover
   or invalidate those derived objects for you.
4. Recompute affected metrics so removed subjects disappear from public
   aggregates (publication suppression gate, `src/rh_privacy.elisa`,
   withholds unknown/private members before any aggregate is published).
5. Record replayability limits: a report whose inputs were unretained is
   no longer replayable, and must say so.
6. Do not reconstruct the removed data from a mirror or cache to evade the
   request.
7. Record: request, authority, source UUID if stopped, actor/reviewer identity
   and authentication source, stop/resume result, scope removed, projections recomputed,
   replayability labels changed.

## 7. Backup restore drill

Trigger: scheduled drill, or recovery after corruption/loss.

1. Set `RH_DATABASE_URL` in the operator environment and run
   `tools/backup-postgres.sh <evidence-root> <new-backup-directory>`. It runs
   `pg_dump` without placing the connection URL in its argument list,
   inventories and verifies evidence objects, exports the evidence bundle,
   creates the binding, and publishes the whole directory with one rename.
2. Before restoring, run `rh_cli ops verify-binding` with `--root`,
   `--manifest`, `--database`, and `--input <backup-binding>`; it rehashes the
   database dump and manifest and verifies every evidence object. Keep the
   database dump itself with the backup: the binding is an integrity index,
   not a claim that the snapshot is correct. Database dump hashing streams
   through a fixed-size buffer, including dumps larger than 64 MiB; evidence
   transfer bundles and other bounded inputs retain their separate 64 MiB cap.
3. Create a **new empty database** and choose a new evidence directory (never
   restore over live state). The restore tool refuses an existing evidence
   destination and checks the target database for user relations, routines,
   and custom types before it starts. Set `RH_RESTORE_DATABASE_URL` in the
   operator environment and run
   `tools/restore-postgres-backup.sh <backup-directory> <new-evidence-root>`.
   It validates the custom-format dump, imports evidence into a staging root,
   restores PostgreSQL in one transaction, then publishes the evidence root
   and verifies the pair binding again. A temporary owner-only libpq service
   file supplies the connection settings because `pg_restore` requires an
   explicit database target; the URL and credentials stay out of command
   arguments. `RH_PG_BACKUP_LIVE=1 tests/test_postgres_backup_live.sh` exercises
   the production drivers against PostgreSQL 16 and checks a restored row,
   evidence digest, report replay, and pair binding.
4. Rebuild projections from the restored database and evidence, then replay a sample
   report; compare against the pinned expected outputs.
6. State the restored/unavailable/unknown sets in writing. An unrestored
   backup is not evidence.
7. Record: backup manifest, binding, present/missing/corrupt counts, restored
   count, sample replay result, date and operator.

## 8. Moving evidence between hosts

1. Create a sorted backup manifest on the source host and verify that every
   listed blob is present and intact.
2. Export it with `rh_cli ops export --root <source-store> --manifest <manifest> --out <bundle>`.
   Export refuses missing or corrupt blobs and packages larger than the
   standard 64 MiB file bound.
3. Copy the bundle through the organization's authenticated and encrypted
   transfer channel.
4. Import it on the destination host with
   `rh_cli ops import --dest <destination-store> --input <bundle>`, then verify
   the imported object names.
5. If a filesystem error interrupts publication, rerun the same import. Each
   blob is published atomically and conflicting destination content is kept.

The `rh-evidence-transfer/1` package preserves arbitrary bytes and checks every
blob against its FNV-1a-64 name before publishing. FNV detects accidental
corruption; the package does not authenticate its sender or encrypt its
contents. Protect it in transit and at rest with the chosen transport.

## 9. Advisory mismatch

Trigger: a user disputes an advisory match, an expected advisory is missing,
or a provider result disagrees with the local version/range evaluation.

1. Preserve the report, submitted package coordinate/version or commit, graph
   node mapping, exact OSV request and response evidence, page cursors, and
   captured full advisory record when hydration was requested. Record the
   input, response, and transformation digests before changing anything.
2. Establish which stage differs: package identity mapping, OSV's server-side
   query, returned advisory aliases/affected ranges, local range evaluation,
   or graph-to-query positional mapping. OSV package/version matching is
   fuzzy; the submitted coordinate alone does not prove an exact match.
3. Treat unsupported range forms, commit queries without implemented
   Git-range matching, skipped/over-cap graph nodes, incomplete pagination,
   and incomplete hydration as unknown or partial. Do not translate them into
   `affected` or `not_affected`. Capture a new bounded query only when the
   required coordinate or evidence is missing; it does not rewrite the old
   report's pinned inputs.
4. Replay the local matcher against the retained full advisory response and
   exact dependency graph. If a parser or mapping defect is confirmed, add
   the smallest response/graph pair as a regression fixture, correct and
   version the mapping, then produce a new report. Keep the original result
   available for audit and supersede it with an explanation; do not edit its
   evidence in place.
5. Re-evaluate any dependent policy decision and publication. An advisory
   match describes affected-version evidence, not runtime exploitability.
   Withdraw or correct downstream findings only for the subjects and report
   revisions supported by the replay.
6. Record: disputed subject and submitted context, original report ID, OSV
   response and transformation digests, query completeness, stage/root cause,
   fixture and parser version, superseding report/policy IDs, and remaining
   unknowns.

## 10. Privacy release and overlap history

Trigger: publishing repeated aggregate cells, changing the cohort definition,
or enabling `public_member_tokens` for a history that previously had no tokens.

1. Keep the `--history` file in an owner-only location and use the same
   deployment secret for every publication scope whose populations must be
   compared. Generate each token as lowercase HMAC-SHA256 over a domain-separated
   stable internal contributor ID. Do not use raw IDs or unkeyed hashes; tokens
   are still linkable pseudonymous data.
2. Provide one token for every public contributor in that cell, sorted
   lexicographically, and ensure the number of tokens equals `public_count`.
   Never include authorized, private, or unknown-visibility subjects in this
   field; those cells are withheld independently.
3. Review `overlap_check` on every published result. `checked_no_overlap` means
   the supplied tokens had no intersection with comparable prior populations;
   `same_population` means the stable cell ID and exact token set match;
   `overlap_suppressed` and `incomplete_history` withhold the count. A
   `not_provided` or `history_disabled` state does not establish overlap
   protection.
4. Do not rotate the token key while reusing the same history. A key change
   makes existing members appear unrelated. Stop publication and create a new,
   separately reviewed history epoch if the key must change; resetting history
   can enable differencing and does not make earlier releases disappear.
5. Record the history path/epoch, key identifier (never the key), input and
   output digests, release decisions, and any suppressed cells. Suppression is
   not formal anonymity, and overlap checking does not replace a broader
   disclosure review.

## 11. Bounded worker scheduling

`tools/worker-daemon.sh` keeps a digest and `next_rotation_cursor` beside its
plan, protected by an advisory lock on the output path. It carries the cursor
into refreshed `rh-worker-input/1` when the producer has not supplied
`rotation_cursor`, and serializes daemons that share the same output. Replaying
an unchanged input after restart is skipped. Direct callers of `rh_cli worker
tick` should persist and pass the cursor themselves; without one, the pass
seeds its starting position from `now` for compatibility. Keep the cursor with
the stable source ordering; when that ordering changes, reset it to zero. This
proves same-host, same-output scheduling behavior. At the database boundary,
graph-query claims return `empty` with
`reason=load_shed_collection_backlog` while collection jobs are queued or have
an active lease, and generic claims rank collection work ahead of graph
queries. Fairness across hosts or database workers still needs deployment
validation.

## 12. Notification webhook delivery

Use `rh_cli notify-deliver` only with the durable `--state` file or
`--state-store` directory for the notification policy input. Keep the
`rh-notify-transport-config/1` endpoint map in operator-controlled storage and
restrict access to it; endpoint URLs are excluded from the public result, but
the configuration itself can contain sensitive routing details. The policy
input remains authoritative for destination authorization and upstream
subscription, and no webhook is sent for suppressed, unauthorized,
unconfigured, or delivery-capped events.

The sender accepts public HTTPS endpoints, validates and pins the complete DNS
answer set, disables redirects and proxy use, and bounds response size and
time. A 2xx response advances cooldown state. Other outcomes leave the event
retryable. Receivers should deduplicate the stable `Idempotency-Key`, because a
crash after remote acceptance and before local state publication can cause a
retry. This transport does not add endpoint authentication or provider-specific
message adapters; use only endpoints whose exposure model is acceptable for
the minimal notification fields it sends.

Record: input and transport-config digests, destination ID, delivery counts,
HTTP outcomes, state-store revision, and any retry or receiver-side
deduplication result. Do not copy endpoint URLs or webhook credentials into
incident notes.
