# CodexProvider

Accounts are immediate `.codex` and `.codex-*` homes with subscription credentials
in `auth.json`. JWT claims supply display metadata. Each home stays separate.
Credentials are reread for usage; refresh tokens are never decoded or used.

Live usage comes from `GET https://chatgpt.com/backend-api/wham/usage`.
Only successful quota snapshots are cached, under an account identity digest.
Local `event_msg/token_count.rate_limits` snapshots use their event timestamps;
creator metadata must agree with the current account when present.
Offline lookup inspects owned rollouts and the newest session date directories.
Merged rollout snapshots use their oldest bucket's timestamp, with main limits first.
History inspection runs outside the usage actor; tails and statistics update snapshots.

Sessions require a live native Codex process holding a rollout open.
A daemon can own several threads. A tree's shared `session_id` folds its subagents.
Only unmatched owned turn starts imply working; terminals match by `turn_id`.
Bootstrap searches backward in bounded steps to a matched, completed root turn;
other threads keep polling while long searches continue. Then only appended
complete lines are read. Ownership disappearing removes the thread.

Statistics scan modified rollout files in `sessions` and `archived_sessions`.
Response records are authoritative per turn and deduplicated by thread/response.
Models come from turn contexts. Turns without response records are counted approximately.
Cumulative deltas reconcile copied counters and retain compaction highs.
The first metadata row owns identity; inherited fork prefixes are excluded.
Ambiguous legacy forks and regressing counters are conservatively undercounted.
Input excludes cache reads; output includes reasoning. Event instants use local days.

The shared `JSONLines` reader bounds memory and skips oversized lines.
Resolved rollout paths must stay inside their home's own history roots.
Checkpoints retain daily/model aggregates, turn state, and 128-bit dedup hashes.
Response usage records and string identities are never retained in the index.
Copied histories use transient winner selectors and a second streaming pass.
One checksummed binary payload per home is saved atomically through `DiskCache`
under a `codex.*` key. Invalid formats rebuild; deleted and out-of-range files
are pruned. Calendar changes rebuild day buckets.
FSEvents and inode/size/mtime checks find changes; append resumes at the last LF.
Statistics workers share scans per home; one scan runs at a time across homes.
All source files, processes, and credentials are observed read-only.
