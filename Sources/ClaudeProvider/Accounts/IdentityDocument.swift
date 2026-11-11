import Foundation

struct IdentityDocument: Decodable {
    struct Identity: Decodable {
        let accountUuid: String?
        let emailAddress: String?
        let planDisplayName: String?
        let organizationRateLimitTier: String?
        let organizationType: String?

        var isKnown: Bool {
            accountUuid?.isEmpty == false || emailAddress?.isEmpty == false
        }
    }

    struct CachedUsage: Decodable {
        let fetchedAtMs: Double
        let accountUuid: String
        let utilization: UsagePayload
    }

    let oauthAccount: Identity?
    let cachedUsageUtilization: CachedUsage?

    private enum CodingKeys: CodingKey { case oauthAccount, cachedUsageUtilization }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        oauthAccount = try? container.decode(Identity.self, forKey: .oauthAccount)
        cachedUsageUtilization = try? container.decode(CachedUsage.self, forKey: .cachedUsageUtilization)
    }

    static func read(home: URL) -> Self? {
        let file = home.lastPathComponent == ".claude"
            ? home.deletingLastPathComponent().appendingPathComponent(".claude.json")
            : home.appendingPathComponent(".claude.json")
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
}
