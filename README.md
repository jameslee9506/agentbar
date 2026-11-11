# AgentBar

A macOS menu bar app that shows the subscription usage and live sessions of every Claude Code and
Codex account on this Mac.

- **Accounts** are discovered from the local config homes: `~/.claude`, `~/.claude-*`, `~/.codex`,
  `~/.codex-*`.
- **Usage**: each account's rate-limit windows and when they reset.
- **Activity**: which accounts are working right now and in how many sessions, updated within a
  second or two. The mark of a working account keeps turning.
- **Statistics**: tokens per day, by account or by model, for 7, 30, or 90 days.
- **Menu bar**: one item per account or a single combined item, dimmed while it has no working
  session. Accounts can be hidden.

AgentBar reads account data without changing the config homes or the Keychain and never refreshes
tokens. An account whose token has expired keeps showing its last known usage until that CLI runs
again. Usage and statistics caches stay in `~/Library/Caches/AgentBar`; credentials are not cached.
There is no telemetry. Network requests send the local access token only to its provider's usage
endpoint; redirects are blocked.

This is an independent project, not affiliated with or endorsed by Anthropic or OpenAI.

## Provider compatibility

Live usage calls provider-specific OAuth endpoints. Their availability and permitted use depend on
the providers' policies. Anthropic restricts third-party use of subscription credentials; permission
for this usage-monitoring integration has not been established. See its
[credential-use policy](https://code.claude.com/docs/en/legal-and-compliance#authentication-and-credential-use).
The MIT license does not grant access to provider services or permission to use their trademarks.

## Build and run

Requires macOS 14 or later and Swift 6.

```sh
Scripts/build-app.sh
open build/AgentBar.app
```

To keep it, copy `build/AgentBar.app` to `/Applications` and turn on "Launch at login" in its settings.

## Development

SwiftPM only, with no third-party package dependencies. `AgentBarCore` defines the provider contract
and shared OS utilities. `ClaudeProvider` and `CodexProvider` implement it independently; `AgentBar`
contains the app, and `AgentBarProbe` provides command-line diagnostics.

```sh
swift test
swift run AgentBar --demo
swift run AgentBar --snapshot build/snapshots
swift run -c release agentbar-probe --offline
```

Tests and snapshots use synthetic data. The probe reads real local accounts; its output includes
account labels, paths, session directories, and partially masked emails. Review it before sharing.
Provider data sources are documented in the
[Claude provider](Sources/ClaudeProvider/README.md) and
[Codex provider](Sources/CodexProvider/README.md) READMEs.

## License

[MIT](LICENSE). Provider icon sources and trademark restrictions are listed in
[Third-party notices](THIRD_PARTY_NOTICES.md).
