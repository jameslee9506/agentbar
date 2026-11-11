import Foundation

struct OAuthCredential: Decodable, Sendable {
    let accessToken: String
    let expiresAt: Double?
    let subscriptionType: String?
    let rateLimitTier: String?

    var expiration: Date? { expiresAt.map { Date(timeIntervalSince1970: $0 / 1_000) } }

    func isExpired(at date: Date) -> Bool {
        expiration.map { $0 <= date } ?? false
    }

    static func decode(_ data: Data) -> Self? {
        struct Envelope: Decodable { let claudeAiOauth: OAuthCredential }
        guard let credential = try? JSONDecoder().decode(Envelope.self, from: data).claudeAiOauth,
              !credential.accessToken.isEmpty
        else { return nil }
        return credential
    }
}
