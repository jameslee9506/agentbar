import CryptoKit
import Foundation

/// A login as the CLI keeps it: the whole document, and the place it came from.
struct StoredLogin: Sendable {
    enum Place: Sendable, Equatable {
        case keychain(service: String)
        case file(URL)
    }

    let document: Data
    let place: Place
}

protocol CredentialStoring: Sendable {
    func load(for home: URL) async -> StoredLogin?
    func save(_ document: Data, to place: StoredLogin.Place) async -> Bool
}

/// The Keychain item of a home, then its `.credentials.json`: the places of the CLI, in its order.
struct CredentialStore: CredentialReading, CredentialStoring {
    let defaultHome: URL
    var readService: @Sendable (String) async -> Data? = Self.readKeychain
    var writeService: @Sendable (String, Data) async -> Bool = Self.writeKeychain

    static func service(for home: URL, defaultHome: URL) -> String {
        let base = "Claude Code-credentials"
        let path = home.path
        guard path != defaultHome.path else { return base }
        let digest = SHA256.hash(data: Data(path.utf8))
        return base + "-" + digest.prefix(4).map { String(format: "%02x", $0) }.joined()
    }

    func read(for home: URL) async -> OAuthCredential? {
        await load(for: home).flatMap { OAuthCredential.decode($0.document) }
    }

    func load(for home: URL) async -> StoredLogin? {
        let service = Self.service(for: home, defaultHome: defaultHome)
        if let data = await readService(service), OAuthCredential.decode(data) != nil {
            return StoredLogin(document: data, place: .keychain(service: service))
        }
        let file = home.appendingPathComponent(".credentials.json")
        guard let data = try? Data(contentsOf: file), OAuthCredential.decode(data) != nil else { return nil }
        return StoredLogin(document: data, place: .file(file))
    }

    func save(_ document: Data, to place: StoredLogin.Place) async -> Bool {
        switch place {
        case .keychain(let service): await writeService(service, document)
        case .file(let file): Self.writeFile(document, to: file)
        }
    }

    /// The account name the CLI gives its Keychain items.
    static var keychainAccount: String {
        let name = ProcessInfo.processInfo.environment["USER"].flatMap { $0.isEmpty ? nil : $0 } ?? NSUserName()
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        return !name.isEmpty && name.unicodeScalars.allSatisfy(allowed.contains) ? name : "claude-code-user"
    }

    private static func readKeychain(service: String) async -> Data? {
        let result = await security(["find-generic-password", "-a", keychainAccount, "-s", service, "-w"])
        return result?.status == 0 ? result?.output : nil
    }

    /// Replaces the item the way the CLI does. The secret goes over standard input, out of the process
    /// table, while it fits one line of `security -i`.
    private static func writeKeychain(service: String, document: Data) async -> Bool {
        let account = keychainAccount
        let hex = document.map { String(format: "%02x", $0) }.joined()
        let command = "add-generic-password -U -a \"\(account)\" -s \"\(service)\" -X \"\(hex)\"\n"
        let result = command.utf8.count <= 4_032
            ? await security(["-i"], input: Data(command.utf8))
            : await security(["add-generic-password", "-U", "-a", account, "-s", service, "-X", hex])
        return result?.status == 0
    }

    private static func writeFile(_ document: Data, to file: URL) -> Bool {
        let temporary = file.deletingLastPathComponent().appendingPathComponent(".credentials.json." + UUID().uuidString)
        guard FileManager.default.createFile(atPath: temporary.path, contents: document,
                                             attributes: [.posixPermissions: 0o600]) else { return false }
        guard rename(temporary.path, file.path) == 0 else {
            try? FileManager.default.removeItem(at: temporary)
            return false
        }
        return true
    }

    private static func security(_ arguments: [String], input: Data? = nil) async -> (status: Int32, output: Data)? {
        await Task.detached(priority: .utility) {
            let process = Process()
            let commands = Pipe()
            let output = Pipe()
            let errors = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
            process.arguments = arguments
            if input != nil { process.standardInput = commands }
            process.standardOutput = output
            process.standardError = errors
            do { try process.run() } catch { return nil }
            if let input {
                try? commands.fileHandleForWriting.write(contentsOf: input)
                try? commands.fileHandleForWriting.close()
            }
            let drainErrors = Task.detached(priority: .utility) {
                _ = errors.fileHandleForReading.readDataToEndOfFile()
            }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            await drainErrors.value
            return (process.terminationStatus, data)
        }.value
    }
}
