import CryptoKit
import Foundation

struct KeychainCredentialReader: CredentialReading {
    let defaultHome: URL
    var readService: @Sendable (String) async -> Data? = Self.readKeychain

    static func service(for home: URL, defaultHome: URL) -> String {
        let base = "Claude Code-credentials"
        let path = home.path
        guard path != defaultHome.path else { return base }
        let digest = SHA256.hash(data: Data(path.utf8))
        return base + "-" + digest.prefix(4).map { String(format: "%02x", $0) }.joined()
    }

    func read(for home: URL) async -> OAuthCredential? {
        if let data = await readService(Self.service(for: home, defaultHome: defaultHome)),
           let credential = OAuthCredential.decode(data) {
            return credential
        }
        guard let data = try? Data(contentsOf: home.appendingPathComponent(".credentials.json")) else { return nil }
        return OAuthCredential.decode(data)
    }

    private static func readKeychain(service: String) async -> Data? {
        await Task.detached(priority: .utility) {
            let process = Process()
            let output = Pipe()
            let errors = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
            process.arguments = ["find-generic-password", "-s", service, "-w"]
            process.standardOutput = output
            process.standardError = errors
            do { try process.run() } catch { return nil }
            let drainErrors = Task.detached(priority: .utility) {
                _ = errors.fileHandleForReading.readDataToEndOfFile()
            }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            await drainErrors.value
            return process.terminationStatus == 0 ? data : nil
        }.value
    }
}
