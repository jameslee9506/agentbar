import Foundation

/// The `agentbar` command of the shell: a script that runs this app's program with `--terminal`.
///
/// An app bundle is in no PATH, so the app writes the script on request. Its place is
/// `/usr/local/bin`, the one folder of every Mac's PATH that is meant for such commands. Where that
/// folder is root's, the system asks for an administrator's password.
struct CommandLineTool: Sendable {
    enum Failure: Error, Equatable {
        /// Another program has the command's name. It is never replaced.
        case taken
        case failed
    }

    static let path = "/usr/local/bin/agentbar"

    /// How the script begins: what tells this app's command from another program of its name.
    /// Changing it leaves the commands already installed unrecognized.
    private static let head = "#!/bin/sh\n# agentbar: the accounts of AgentBar in the terminal. Its settings remove this file.\n"

    let command: URL
    /// The program the command runs.
    let program: URL
    /// Runs a shell command as root once the system has asked for an administrator's password under
    /// `prompt`. False when the command failed; declining the password is no failure, as nothing was done.
    let elevate: @Sendable (_ shell: String, _ prompt: String) -> Bool

    /// The command for the app bundle this process runs from. `nil` outside a bundle, and for a
    /// downloaded app that macOS runs from a random path until it is moved: that path does not last.
    static var bundled: CommandLineTool? {
        let bundle = Bundle.main.bundleURL
        guard bundle.pathExtension == "app", !bundle.pathComponents.contains("AppTranslocation"),
              let program = Bundle.main.executableURL else { return nil }
        return CommandLineTool(command: URL(fileURLWithPath: path), program: program, elevate: asAdministrator)
    }

    var script: String {
        Self.head + "exec \(Self.quoted(program.path)) \(TerminalCommand.flag) \"$@\"\n"
    }

    /// Whether the command is this app's and runs this copy of it.
    var isInstalled: Bool { contents == script }

    func install() throws(Failure) {
        let taken = (try? FileManager.default.attributesOfItem(atPath: command.path)) != nil
        if taken, !isOurs { throw .taken }
        if FileManager.default.isWritableFile(atPath: directory.path) {
            do { try write() } catch { throw .failed }
        } else {
            // A new file takes the command's place in one step: a link there is replaced, never written through.
            let shell = "/bin/mkdir -p \(Self.quoted(directory.path))"
                + " && t=$(/usr/bin/mktemp \(Self.quoted(directory.appendingPathComponent(".agentbar.XXXXXX").path)))"
                + " && /usr/bin/printf %s \(Self.quoted(script)) > \"$t\" && /bin/chmod 755 \"$t\""
                + " && /bin/mv -f \"$t\" \(Self.quoted(command.path))"
            guard elevate(shell, "AgentBar wants to install the “agentbar” terminal command.") else { throw .failed }
        }
    }

    /// Removes a command this app wrote, whichever copy of the app it runs.
    func uninstall() throws(Failure) {
        guard isOurs else { return }
        if FileManager.default.isWritableFile(atPath: directory.path) {
            do { try FileManager.default.removeItem(at: command) } catch { throw .failed }
        } else {
            let shell = "/bin/rm -f \(Self.quoted(command.path))"
            guard elevate(shell, "AgentBar wants to remove the “agentbar” terminal command.") else { throw .failed }
        }
    }

    private var directory: URL { command.deletingLastPathComponent() }

    private var isOurs: Bool { contents?.hasPrefix(Self.head) == true }

    /// The start of the file at the command's path, which is all of a script of this app.
    private var contents: String? {
        guard let file = try? FileHandle(forReadingFrom: command) else { return nil }
        defer { try? file.close() }
        return (try? file.read(upToCount: 4096)).flatMap { String(data: $0, encoding: .utf8) }
    }

    private func write() throws {
        let temporary = directory.appendingPathComponent(".agentbar.\(ProcessInfo.processInfo.processIdentifier)")
        try? FileManager.default.removeItem(at: temporary)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try Data(script.utf8).write(to: temporary, options: .withoutOverwriting)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: temporary.path)
        guard rename(temporary.path, command.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
    }

    /// `text` in single quotes, for `sh`.
    private static func quoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func asAdministrator(shell: String, prompt: String) -> Bool {
        let process = Process()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        // The command and the prompt are arguments, so that no text of theirs is read as AppleScript.
        process.arguments = [
            "-e", "on run argv",
            "-e", "do shell script (item 1 of argv) with prompt (item 2 of argv) with administrator privileges",
            "-e", "end run",
            "--", shell, prompt,
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errors
        do { try process.run() } catch { return false }
        let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        // -128 is AppleScript's "user canceled".
        return process.terminationStatus == 0 || message.contains("(-128)")
    }
}
