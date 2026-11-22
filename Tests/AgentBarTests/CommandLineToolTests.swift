@testable import AgentBar
import Foundation
import Testing

@MainActor
struct CommandLineToolTests {
    @Test func theCommandRunsTheProgramInTheTerminalWithItsArguments() throws {
        let folder = try Folder()
        defer { folder.remove() }
        // A program that says how it was run, at a path the shell must not read as anything else.
        let program = folder.url.appendingPathComponent("It's mine/Agent Bar")
        try FileManager.default.createDirectory(at: program.deletingLastPathComponent(), withIntermediateDirectories: true)
        try folder.write("#!/bin/sh\nprintf '%s|' \"$@\"\n", to: program, mode: 0o755)
        let tool = folder.tool(program: program)
        #expect(!tool.isInstalled)
        try tool.install()
        #expect(tool.isInstalled)
        #expect(try FileManager.default.attributesOfItem(atPath: tool.command.path)[.posixPermissions] as? Int == 0o755)
        #expect(try run(tool.command, "claude", "two words", "--all") == "--terminal|claude|two words|--all|")
        // Installing again changes nothing, and no temporary file stays behind.
        try tool.install()
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.bin.path) == ["agentbar"])
        try tool.uninstall()
        #expect(!tool.isInstalled)
        #expect(!FileManager.default.fileExists(atPath: tool.command.path))
        try tool.uninstall()
    }

    @Test func anotherProgramOfThatNameIsNeitherReplacedNorRemoved() throws {
        let folder = try Folder()
        defer { folder.remove() }
        let tool = folder.tool()
        let other = "#!/bin/sh\necho another agentbar\n"
        try folder.write(other, to: tool.command, mode: 0o755)
        #expect(!tool.isInstalled)
        #expect(throws: CommandLineTool.Failure.taken) { try tool.install() }
        try tool.uninstall()
        #expect(try String(contentsOf: tool.command, encoding: .utf8) == other)
        // A link that leads nowhere has the name too.
        try FileManager.default.removeItem(at: tool.command)
        try FileManager.default.createSymbolicLink(at: tool.command, withDestinationURL: folder.url.appendingPathComponent("gone"))
        #expect(throws: CommandLineTool.Failure.taken) { try tool.install() }
    }

    @Test func theCommandOfAnotherCopyOfTheAppIsReplacedAndRemoved() throws {
        let folder = try Folder()
        defer { folder.remove() }
        let moved = folder.tool(program: URL(fileURLWithPath: "/synthetic/Old/AgentBar.app/Contents/MacOS/AgentBar"))
        let tool = folder.tool()
        try moved.install()
        #expect(moved.isInstalled)
        #expect(!tool.isInstalled)
        try tool.install()
        #expect(tool.isInstalled)
        #expect(!moved.isInstalled)
        try moved.uninstall()
        #expect(!tool.isInstalled)
    }

    @Test func aFolderOfRootIsWrittenByAnAdministrator() throws {
        let folder = try Folder()
        defer { folder.remove() }
        let asked = Asked()
        // Stands in for the administrator: runs the command once the folder can be written.
        let tool = folder.tool { shell, prompt in
            asked.record(prompt)
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.bin.path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.bin.path) }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", shell]
            guard (try? process.run()) != nil else { return false }
            process.waitUntilExit()
            return process.terminationStatus == 0
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.bin.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.bin.path) }
        try tool.install()
        #expect(tool.isInstalled)
        #expect(try String(contentsOf: tool.command, encoding: .utf8) == tool.script)
        #expect(try FileManager.default.attributesOfItem(atPath: tool.command.path)[.posixPermissions] as? Int == 0o755)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.bin.path) == ["agentbar"])
        try tool.uninstall()
        #expect(!FileManager.default.fileExists(atPath: tool.command.path))
        #expect(asked.prompts == [
            "AgentBar wants to install the “agentbar” terminal command.",
            "AgentBar wants to remove the “agentbar” terminal command.",
        ])
        // An administrator's command that fails is a failure; nothing asks where nothing is to do.
        let refused = folder.tool { _, _ in false }
        #expect(throws: CommandLineTool.Failure.failed) { try refused.install() }
        try refused.uninstall()
    }

    @Test func theSettingFollowsWhatIsInstalledAndSaysWhatWentWrong() async throws {
        let folder = try Folder()
        defer { folder.remove() }
        let tool = folder.tool()
        let state = CommandLineToolState(tool: tool)
        #expect(state.isAvailable && !state.isInstalled)
        state.setInstalled(true)
        #expect(state.isChanging)
        #expect(await TestWait.until { !state.isChanging })
        #expect(state.isInstalled && state.problem == nil)
        // Removed outside the app.
        try FileManager.default.removeItem(at: tool.command)
        state.refresh()
        #expect(!state.isInstalled)
        try folder.write("another program", to: tool.command, mode: 0o755)
        state.setInstalled(true)
        #expect(await TestWait.until { !state.isChanging })
        #expect(!state.isInstalled)
        #expect(state.problem == "Another program is already installed as “agentbar”.")

        let preview = CommandLineToolState(tool: nil)
        preview.setInstalled(true)
        #expect(!preview.isAvailable && !preview.isInstalled && !preview.isChanging)
    }

    private func run(_ command: URL, _ arguments: String...) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = command
        process.arguments = arguments
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}

/// A folder that stands in for `/usr/local`.
private struct Folder: Sendable {
    let url: URL
    var bin: URL { url.appendingPathComponent("bin") }

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("AgentBarTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url.appendingPathComponent("bin"), withIntermediateDirectories: true)
    }

    /// The command in this folder. Nothing asks for an administrator unless `elevate` stands in for one.
    func tool(
        program: URL = URL(fileURLWithPath: "/synthetic/AgentBar.app/Contents/MacOS/AgentBar"),
        elevate: @escaping @Sendable (String, String) -> Bool = { _, _ in false }
    ) -> CommandLineTool {
        CommandLineTool(command: bin.appendingPathComponent("agentbar"), program: program, elevate: elevate)
    }

    func write(_ text: String, to file: URL, mode: Int) throws {
        try Data(text.utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: file.path)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}

private final class Asked: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []

    var prompts: [String] { lock.withLock { recorded } }
    func record(_ prompt: String) { lock.withLock { recorded.append(prompt) } }
}
