import AgentBarCore
import Foundation

struct AccountDiscovery: Sendable {
    let root: URL
    let credentials: any CredentialReading

    func accounts() async -> [Account] {
        let candidates = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey]
        )) ?? []
        var accounts: [Account] = []
        for home in candidates.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = home.lastPathComponent
            guard name == ".claude" || name.hasPrefix(".claude-"),
                  (try? home.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            else { continue }
            let identity = IdentityDocument.read(home: home)?.oauthAccount
            let displayPlan = identity?.planDisplayName.flatMap { $0.isEmpty ? nil : $0 }
            let hasIdentityAndPlan = identity?.isKnown == true
                && (displayPlan != nil || identity?.organizationRateLimitTier != nil)
            let credential = hasIdentityAndPlan ? nil : await credentials.read(for: home)
            guard identity?.isKnown == true || credential != nil else { continue }
            let plan = displayPlan
                ?? Self.humanizedPlan(identity?.organizationRateLimitTier ?? credential?.rateLimitTier
                    ?? credential?.subscriptionType ?? identity?.organizationType)
            accounts.append(Account(
                id: AccountID(provider: .claude, home: name),
                name: name == ".claude" ? "claude" : String(name.dropFirst(".claude-".count)),
                home: home, email: identity?.emailAddress, plan: plan
            ))
        }
        return accounts.sorted { ($0.name, $0.id) < ($1.name, $1.id) }
    }

    static func humanizedPlan(_ value: String?) -> String? {
        guard var value, !value.isEmpty else { return nil }
        for prefix in ["default_", "claude_"] where value.hasPrefix(prefix) {
            value.removeFirst(prefix.count)
        }
        return value.split(separator: "_").map { word in
            word.first?.isNumber == true ? String(word) : word.capitalized
        }.joined(separator: " ")
    }
}
