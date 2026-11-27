import CryptoKit
import Foundation

enum CredentialRenewal: Sendable {
    case renewed(OAuthCredential)
    /// The service refused the refresh token, or none is stored: the account has to sign in again.
    case rejected
    /// Nothing was decided: the request failed, or a CLI is renewing the login right now.
    case unavailable
}

protocol CredentialRenewing: Sendable {
    /// Replaces the login of `home` whose access token is `stale`.
    func renew(_ stale: OAuthCredential, for home: URL) async -> CredentialRenewal
}

/// Renews a login the way its CLI does: under the CLI's refresh lock, as the CLI's OAuth client, and
/// saved where the CLI keeps it. The service replaces the refresh token with every renewal, so the
/// new one has to reach the CLI or the account is signed out.
actor LoginRenewal: CredentialRenewing {
    private let store: any CredentialStoring
    private let transport: any UsageTransporting
    private let clock: @Sendable () -> Date
    private let lockWait: Duration
    private var running: [String: Task<CredentialRenewal, Never>] = [:]
    /// Renewed logins the store has not accepted yet. They are saved before anything else is tried.
    private var unsaved: [String: StoredLogin] = [:]
    /// Digests of refresh tokens the service refused, so they are not sent again.
    private var refused: Set<String> = []

    init(store: any CredentialStoring, transport: any UsageTransporting,
         clock: @escaping @Sendable () -> Date, lockWait: Duration = .seconds(1)) {
        self.store = store
        self.transport = transport
        self.clock = clock
        self.lockWait = lockWait
    }

    func renew(_ stale: OAuthCredential, for home: URL) async -> CredentialRenewal {
        let key = home.standardizedFileURL.path
        if let task = running[key] { return await task.value }
        // Unstructured on purpose: a cancelled caller must not abandon tokens the service just issued.
        let task = Task { await self.locked(stale, home: home, key: key) }
        running[key] = task
        let renewal = await task.value
        running[key] = nil
        return renewal
    }

    private func locked(_ stale: OAuthCredential, home: URL, key: String) async -> CredentialRenewal {
        var lock = RefreshLock.acquire(home: home)
        for _ in 0..<5 where lock == nil {
            try? await Task.sleep(for: lockWait)
            lock = RefreshLock.acquire(home: home)
        }
        guard let lock else { return .unavailable }
        defer { lock.release() }
        return await renewal(of: stale, home: home, key: key)
    }

    private func renewal(of stale: OAuthCredential, home: URL, key: String) async -> CredentialRenewal {
        var stored = unsaved[key]
        if let pending = stored {
            if await store.save(pending.document, to: pending.place) { unsaved[key] = nil }
        } else {
            stored = await store.load(for: home)
        }
        guard let stored, let login = StoredTokens(stored.document) else { return .rejected }
        if login.credential.accessToken != stale.accessToken, !login.credential.isExpired(at: clock()) {
            return .renewed(login.credential)
        }
        guard let refreshToken = login.refreshToken else { return .rejected }
        let digest = SHA256.hash(data: Data(refreshToken.utf8)).map { String(format: "%02x", $0) }.joined()
        guard !refused.contains(digest) else { return .rejected }

        guard let response = try? await transport.send(login.request) else { return .unavailable }
        guard response.status == 200 else {
            guard StoredTokens.isRefusal(response) else { return .unavailable }
            refused.insert(digest)
            return .rejected
        }

        // Like the CLI, save only over the login that was renewed: a different refresh token in its
        // place belongs to a newer sign-in.
        var base = stored
        if unsaved[key] == nil, let current = await store.load(for: home), current.place == stored.place,
           let other = StoredTokens(current.document) {
            guard other.refreshToken == refreshToken else {
                return other.credential.isExpired(at: clock()) ? .unavailable : .renewed(other.credential)
            }
            base = current
        }
        guard let document = StoredTokens.document(base.document, renewedBy: response.data,
                                                   replacing: refreshToken, at: clock()),
              let credential = OAuthCredential.decode(document)
        else { return .unavailable }
        for attempt in 0..<3 {
            if attempt > 0 { try? await Task.sleep(for: .milliseconds(100 * attempt)) }
            if await store.save(document, to: stored.place) {
                unsaved[key] = nil
                return .renewed(credential)
            }
        }
        unsaved[key] = StoredLogin(document: document, place: stored.place)
        return .renewed(credential)
    }
}

/// What renewal needs from a stored login, read without disturbing the rest of the document.
private struct StoredTokens {
    let credential: OAuthCredential
    let refreshToken: String?
    private let scopes: [String]
    private let clientID: String?

    init?(_ document: Data) {
        guard let credential = OAuthCredential.decode(document),
              let login = Self.object(document)?["claudeAiOauth"] as? [String: Any]
        else { return nil }
        self.credential = credential
        refreshToken = (login["refreshToken"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        scopes = login["scopes"] as? [String] ?? []
        clientID = login["clientId"] as? String
    }

    var request: URLRequest {
        var body = ["grant_type": "refresh_token", "refresh_token": refreshToken ?? "",
                    "client_id": clientID ?? "9d1c250a-e61b-44d9-88ed-5944d1962f5e"]
        if !scopes.isEmpty { body["scope"] = scopes.joined(separator: " ") }
        var request = URLRequest(url: URL(string: "https://platform.claude.com/v1/oauth/token")!)
        request.httpMethod = "POST"
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("AgentBar/1.0", forHTTPHeaderField: "User-Agent")
        return request
    }

    static func isRefusal(_ response: UsageResponse) -> Bool {
        guard response.status == 400 || response.status == 401, let error = object(response.data)?["error"] else { return false }
        let detail = error as? [String: Any]
        return [error as? String, detail?["code"] as? String, detail?["type"] as? String].contains("invalid_grant")
    }

    /// The stored document with the tokens of a renewal response, every other field kept.
    static func document(_ document: Data, renewedBy response: Data, replacing refreshToken: String, at now: Date) -> Data? {
        guard let reply = object(response),
              let accessToken = reply["access_token"] as? String, !accessToken.isEmpty,
              let lifetime = seconds(reply["expires_in"]),
              var stored = object(document), var login = stored["claudeAiOauth"] as? [String: Any]
        else { return nil }
        let milliseconds = now.timeIntervalSince1970 * 1_000
        login["accessToken"] = accessToken
        login["refreshToken"] = (reply["refresh_token"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? refreshToken
        login["expiresAt"] = Int64(milliseconds + lifetime * 1_000)
        if let lifetime = seconds(reply["refresh_token_expires_in"]) {
            login["refreshTokenExpiresAt"] = Int64(milliseconds + lifetime * 1_000)
        }
        if let scopes = (reply["scope"] as? String)?.split(separator: " ").map(String.init), !scopes.isEmpty {
            login["scopes"] = scopes
        }
        stored["claudeAiOauth"] = login
        return try? JSONSerialization.data(withJSONObject: stored, options: [.withoutEscapingSlashes])
    }

    /// A lifetime in seconds, when the response states a plausible one.
    private static func seconds(_ value: Any?) -> Double? {
        guard let seconds = (value as? NSNumber)?.doubleValue, seconds > 0, seconds < 1e9 else { return nil }
        return seconds
    }

    private static func object(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
