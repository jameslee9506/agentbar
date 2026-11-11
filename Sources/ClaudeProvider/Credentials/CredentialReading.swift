import Foundation

protocol CredentialReading: Sendable {
    func read(for home: URL) async -> OAuthCredential?
}
