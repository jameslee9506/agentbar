import Foundation

protocol CodexLoginRenewing: Sendable {
    /// Asks the CLI to renew the login of `home`. The result is whatever `auth.json` holds afterwards.
    func renew(home: URL) async
}

/// Has the Codex CLI renew a login: `account/read` with `refreshToken` on its app server runs the
/// CLI's own refresh, which stores the tokens under the CLI's locks. Nothing is written from here.
struct CodexLoginRenewal: CodexLoginRenewing {
    /// The CLI to run, instead of the installed one.
    var executable: URL?
    var timeout: Duration = .seconds(30)

    func renew(home: URL) async {
        guard let executable = executable ?? Self.installed() else { return }
        let timeout = timeout
        await Task.detached(priority: .utility) {
            let process = Process()
            let requests = Pipe()
            let responses = Pipe()
            var environment = ProcessInfo.processInfo.environment
            environment["CODEX_HOME"] = home.path
            environment["PATH"] = Self.searchPath().joined(separator: ":")
            process.executableURL = executable
            process.arguments = ["app-server"]
            process.environment = environment
            process.currentDirectoryURL = FileManager.default.temporaryDirectory
            process.standardInput = requests
            process.standardOutput = responses
            process.standardError = FileHandle.nullDevice
            do { try process.run() } catch { return }
            let pid = process.processIdentifier
            let unanswered = Self.terminate(pid, after: timeout)
            let lines = [
                #"{"id":1,"method":"initialize","params":{"clientInfo":{"name":"agentbar","title":"AgentBar","version":"1.0"}}}"#,
                #"{"method":"initialized"}"#,
                #"{"id":2,"method":"account/read","params":{"refreshToken":true}}"#,
            ]
            try? requests.fileHandleForWriting.write(contentsOf: Data((lines.joined(separator: "\n") + "\n").utf8))
            Self.read(until: 2, from: responses.fileHandleForReading)
            // The answer comes after the tokens are stored. The server ends with its input, soon.
            try? requests.fileHandleForWriting.close()
            let lingering = Self.terminate(pid, after: .seconds(3))
            _ = try? responses.fileHandleForReading.readToEnd()
            process.waitUntilExit()
            unanswered.cancel()
            lingering.cancel()
        }.value
    }

    private static func terminate(_ pid: pid_t, after delay: Duration) -> Task<Void, Never> {
        Task.detached {
            try? await Task.sleep(for: delay)
            if !Task.isCancelled { kill(pid, SIGTERM) }
        }
    }

    /// Reads lines until the response to request `id`, or the end of the stream.
    private static func read(until id: Int, from handle: FileHandle) {
        var buffer = Data()
        while true {
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<newline]
                buffer.removeSubrange(buffer.startIndex...newline)
                let message = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any]
                if (message?["id"] as? NSNumber)?.intValue == id, message?["method"] == nil { return }
            }
        }
    }

    /// The directories of the environment, then the usual install locations: an app started from the
    /// Finder has only the system path.
    private static func searchPath() -> [String] {
        let listed = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let home = FileManager.default.homeDirectoryForCurrentUser
        return listed + ["/opt/homebrew/bin", "/usr/local/bin", home.appendingPathComponent(".local/bin").path]
    }

    static func installed() -> URL? {
        searchPath().lazy.map { URL(fileURLWithPath: $0).appendingPathComponent("codex") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
