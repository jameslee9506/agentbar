import AgentBarCore
import Foundation

struct CodexAccounts: Sendable {
    let root: URL

    func accounts() -> [Account] {
        let homes = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey]
        )) ?? []
        return homes.compactMap { home in
            let name = home.lastPathComponent
            guard name == ".codex" || (name.hasPrefix(".codex-") && name.count > 7),
                  (try? home.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  let credential = CodexCredential.read(home: home)
            else { return nil }
            return Account(
                id: AccountID(provider: .codex, home: name),
                name: name == ".codex" ? "codex" : String(name.dropFirst(7)),
                home: home, email: credential.email, plan: credential.plan
            )
        }.sorted { ($0.name, $0.id.home) < ($1.name, $1.id.home) }
    }
}
