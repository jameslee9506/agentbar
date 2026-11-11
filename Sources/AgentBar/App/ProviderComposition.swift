import AgentBarCore
import ClaudeProvider
import CodexProvider

enum ProviderComposition {
    static func make(demo: Bool) -> [any AccountProvider] {
        if demo { return [DemoProvider(kind: .claude), DemoProvider(kind: .codex)] }
        return [ClaudeProvider(), CodexProvider()]
    }
}
