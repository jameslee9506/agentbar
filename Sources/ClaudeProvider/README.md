# ClaudeProvider

Discovers immediate `.claude` and `.claude-*` directories containing an OAuth identity
or readable OAuth credential. Each home stays a separate account. Default identity
is `~/.claude.json`; custom identity is `<home>/.claude.json`.

Credentials come from captured `/usr/bin/security find-generic-password` output,
then `<home>/.credentials.json`. The default service is `Claude Code-credentials`;
custom services append `-` and the first eight lowercase SHA-256 hex characters
of the absolute home path. Custom homes never try the default service.
Only access-token, expiry, and plan fields are decoded. Credentials are not cached.
Usage uses `GET https://api.anthropic.com/api/oauth/usage`. Credentials are reread
for every fetch. Local expiry skips HTTP; 401 permits one retry only with a changed,
unexpired token. No token refresh is performed. 429 returns the Retry-After delay.
Absent windows remain absent; `is_active` does not suppress a quota.
Usage caching requires an account UUID. Startup selects the newer successful
DiskCache snapshot or UUID-matched `cachedUsageUtilization`, keeping its fetch time.

Sessions come from `<home>/sessions/<pid>.json`, matched to live Claude process
start times in UTC. Only `busy` means working; other statuses and unregistered
processes are idle. Unregistered processes use `CLAUDE_CONFIG_DIR` or the default
home when readable environment data omits that variable. Unreadable environments
do not imply the default home. Each process counts once, independent of subagents.
Native version-named binaries also run `ugrep`; argv distinguishes these tools.
DirectoryWatcher handles registry changes; one two-second process poll per stream
detects exits. Cancellation or releasing the stream stops its watchers and poll.
History paths resolving outside the home's own projects or sessions are ignored.

Statistics stream `<home>/projects/**/*.jsonl` through JSONLines. Requests deduplicate
across all files by `message.id`, regardless of request or session IDs. Rows without
a message ID use row UUID, then file identity and position. Complete rows win;
main rows win over sidechain copies, then later timestamps and append positions win.
Synthetic models are omitted. Input, output, cache read, and cache creation stay
separate; nested token breakdowns are not added again. Days use the local calendar.

Each home has one atomic, versioned DiskCache file under a `claude.` key. It holds
128-bit request hashes, packed winners, interned models, daily totals, and file
checkpoints. Checksums cover all state. Warm reads reuse totals; appends resume
at complete newlines. Rewrites, deletions, range changes, and invalid caches rebuild.
JSONLines bounds buffers and line lifetimes. Concurrent calls share one home scan.
