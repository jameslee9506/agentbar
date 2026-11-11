import AgentBarCore
import Darwin
import Foundation
import Testing

struct ProcessInspectorTests {
    @Test func inspectsChildProcessAndDetectsExit() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let inputURL = directory.url.appendingPathComponent("input.txt")
        try Data("synthetic input".utf8).write(to: inputURL)
        let input = try FileHandle(forReadingFrom: inputURL)
        defer { try? input.close() }
        let executable = directory.url.appendingPathComponent("sleep")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/sleep"), to: executable)

        let child = Process()
        child.executableURL = executable
        child.arguments = ["30"]
        child.environment = ["AGENTBAR_TEST_VALUE": "synthetic=value", "PATH": "/usr/bin:/bin"]
        child.currentDirectoryURL = directory.url
        child.standardInput = input
        try child.run()
        defer {
            if child.isRunning { child.terminate() }
            child.waitUntilExit()
        }

        let inspector = SystemProcessInspector()
        let pid = child.processIdentifier
        let summary = try #require(inspector.summaries().first { $0.pid == pid })
        #expect(summary.parentPID == getpid())
        #expect(summary.name == "sleep")
        let process = try #require(inspector.details(for: pid))
        #expect(process.pid == pid)
        #expect(process.parentPID == getpid())
        #expect(process.arguments.last == "30")
        #expect(process.environment["AGENTBAR_TEST_VALUE"] == "synthetic=value")
        #expect(URL(fileURLWithPath: process.executablePath).resolvingSymlinksInPath() == executable.resolvingSymlinksInPath())
        let workingDirectory = try #require(process.workingDirectory)
        #expect(URL(fileURLWithPath: workingDirectory).resolvingSymlinksInPath().path == directory.url.resolvingSymlinksInPath().path)
        #expect(process.startTime == summary.startTime)
        let openPaths = inspector.openFilePaths(of: pid).map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
        #expect(openPaths.contains(inputURL.resolvingSymlinksInPath().path))
        #expect(inspector.isAlive(pid, startedAt: process.startTime))
        #expect(!inspector.isAlive(pid, startedAt: process.startTime.addingTimeInterval(-1)))

        child.terminate()
        child.waitUntilExit()
        #expect(!inspector.isAlive(pid, startedAt: process.startTime))
        #expect(inspector.details(for: pid) == nil)
        #expect(inspector.openFilePaths(of: pid).isEmpty)
    }

    @Test func rejectsInvalidProcessIdentifiers() {
        let inspector = SystemProcessInspector()
        for pid in [Int32(-1), 0, Int32.max] {
            #expect(inspector.details(for: pid) == nil)
            #expect(inspector.openFilePaths(of: pid).isEmpty)
            #expect(!inspector.isAlive(pid))
        }
    }
}
