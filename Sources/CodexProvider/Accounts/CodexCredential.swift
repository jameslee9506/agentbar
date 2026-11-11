import CryptoKit
import Foundation

struct CodexCredential {
    let accessToken: String
    let accountID: String
    let email: String?
    let plan: String?
    let expiresAt: Date?
    let fileModifiedAt: Date
    let accountDigest: String
    let userDigest: String?

    var identity: String { accountDigest + "." + (userDigest ?? "") }

    static func read(home: URL) -> Self? {
        let file = home.appendingPathComponent("auth.json")
        guard let data = try? Data(contentsOf: file), data.count <= 1024 * 1024,
              let auth = try? JSONDecoder().decode(Auth.self, from: data),
              auth.auth_mode == nil || auth.auth_mode == "chatgpt",
              let token = nonempty(auth.tokens?.access_token)
        else { return nil }
        let access = claims(token)
        let id = claims(auth.tokens?.id_token)
        let accessAuth = access?["https://api.openai.com/auth"] as? [String: Any]
        let idAuth = id?["https://api.openai.com/auth"] as? [String: Any]
        guard let accountID = nonempty(auth.tokens?.account_id)
            ?? nonempty(accessAuth?["chatgpt_account_id"] as? String)
            ?? nonempty(idAuth?["chatgpt_account_id"] as? String)
        else { return nil }
        let profile = access?["https://api.openai.com/profile"] as? [String: Any]
        let plan = nonempty(accessAuth?["chatgpt_plan_type"] as? String)
            ?? nonempty(idAuth?["chatgpt_plan_type"] as? String)
        let userID = nonempty(accessAuth?["chatgpt_user_id"] as? String)
            ?? nonempty(idAuth?["chatgpt_user_id"] as? String)
        return Self(
            accessToken: token, accountID: accountID,
            email: nonempty(id?["email"] as? String) ?? nonempty(profile?["email"] as? String),
            plan: plan.map { $0.prefix(1).uppercased() + $0.dropFirst() },
            expiresAt: (access?["exp"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) },
            fileModifiedAt: (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast,
            accountDigest: digest(accountID), userDigest: userID.map(digest)
        )
    }

    static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func claims(_ token: String?) -> [String: Any]? {
        guard let token else { return nil }
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var encoded = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let data = Data(base64Encoded: encoded) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }

    // Deliberately excludes refresh tokens and API keys from the decoded credential.
    private struct Auth: Decodable {
        let auth_mode: String?
        let tokens: Tokens?
        struct Tokens: Decodable {
            let access_token: String?
            let id_token: String?
            let account_id: String?
        }
    }
}
