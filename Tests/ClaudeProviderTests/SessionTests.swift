import AgentBarCore
@testable import ClaudeProvider
import Foundation
import Testing

struct SessionTests {
    @Test func registryLinksCannotBorrowAnotherHomesActivity() throws {
        let space = try TestSpace()
        let account = try space.account()
        let other = try space.account(".claude-other")
        let processes = TestProcesses()
        let unknown = testProcess(101, home: other.home)
        let bound = testProcess(102, home: account.home)
        processes.set([unknown.0, bound.0], details: [bound.1])
        try registry(space, account: other, pid: 101, status: "busy")
        try registry(space, account: other, pid: 102, status: "busy")
        let root = account.home.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for pid in [101, 102] {
            try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("\(pid).json"),
                withDestinationURL: other.home.appendingPathComponent("sessions/\(pid).json"))
        }
        var scanner = SessionScanner(root: space.root, processes: processes)
        let linkedFiles = try #require(scanner.snapshot(accounts: [account])[account.id])
        #expect(linkedFiles.sessions.count == 1)
        #expect(linkedFiles.workingCount == 0) // The bound process still counts as unregistered and idle.
        try FileManager.default.removeItem(at: root)
        try FileManager.default.createSymbolicLink(at: root, withDestinationURL: other.home.appendingPathComponent("sessions"))
        let linkedRoot = try #require(scanner.snapshot(accounts: [account])[account.id])
        #expect(linkedRoot == linkedFiles)
        let both = scanner.snapshot(accounts: [account, other])
        #expect(both[account.id]?.workingCount == 0)
        #expect(both[other.id]?.workingCount == 1)
    }

    @Test func nativeVersionNamedExecutablesAreClaudeButUnrelatedVersionsAreNot() throws {
        let space = try TestSpace()
        let account = try space.account()
        let processes = TestProcesses()
        let summaries = [ProcessSummary(pid: 101, parentPID: 1, name: "2.1.321", startTime: testNow),
                         ProcessSummary(pid: 102, parentPID: 1, name: "2.1.321", startTime: testNow),
                         ProcessSummary(pid: 103, parentPID: 1, name: "not-claude", startTime: testNow),
                         ProcessSummary(pid: 104, parentPID: 101, name: "2.1.321", startTime: testNow),
                         ProcessSummary(pid: 105, parentPID: 101, name: "2.1.321", startTime: testNow)]
        let details = [
            RunningProcess(pid: 101, parentPID: 1, executablePath: "/synthetic/.local/share/claude/versions/2.1.321",
                           arguments: ["claude"], environment: ["CLAUDE_CONFIG_DIR": account.home.path],
                           workingDirectory: "/synthetic/project", startTime: testNow),
            RunningProcess(pid: 102, parentPID: 1, executablePath: "/synthetic/other/versions/2.1.321",
                           arguments: ["other"], environment: ["CLAUDE_CONFIG_DIR": account.home.path],
                           workingDirectory: "/synthetic/project", startTime: testNow),
            RunningProcess(pid: 104, parentPID: 101, executablePath: "/synthetic/.local/share/claude/versions/2.1.321",
                           arguments: ["ugrep", "--hidden"], environment: ["CLAUDE_CONFIG_DIR": account.home.path],
                           workingDirectory: "/synthetic/project", startTime: testNow),
            RunningProcess(pid: 105, parentPID: 101, executablePath: "/synthetic/.local/share/claude/versions/2.1.321",
                           arguments: ["claude", "mcp", "serve"], environment: ["CLAUDE_CONFIG_DIR": account.home.path],
                           workingDirectory: "/synthetic/project", startTime: testNow)
        ]
        processes.set(summaries, details: details)
        try registry(space, account: account, pid: 101, status: "busy")
        try registry(space, account: account, pid: 102, status: "busy")
        var scanner = SessionScanner(root: space.root, processes: processes)
        let result = scanner.snapshot(accounts: [account])
        #expect(result[account.id]?.sessions.count == 1)
        #expect(result[account.id]?.workingCount == 1)
    }

    @Test func validatesPIDStartAndHomeWithoutCountingToolsOrStaleFiles() throws {
        let space = try TestSpace()
        let account = try space.account()
        let work = try space.account(".claude-work")
        let processes = TestProcesses()
        let pairs = [testProcess(101, home: account.home), testProcess(102, home: account.home),
                     testProcess(103, home: account.home), testProcess(104, home: account.home, name: "node"),
                     testProcess(105, home: work.home), testProcess(106, home: account.home)]
        processes.set(pairs.map(\.0), details: pairs.map(\.1))
        try registry(space, account: account, pid: 101, status: "busy", since: testNow.addingTimeInterval(-6 * 86_400))
        try registry(space, account: account, pid: 102, status: "shell")
        try registry(space, account: account, pid: 103, status: "busy", start: testNow.addingTimeInterval(-1))
        try registry(space, account: account, pid: 104, status: "busy")
        try registry(space, account: account, pid: 105, status: "busy") // Wrong home.
        try registry(space, account: account, pid: 999, status: "busy") // Dead process.
        try registry(space, account: work, pid: 105, status: "unknown")
        try space.write(["pid": 999, "procStart": startString(testNow), "status": "busy"],
                        to: account.home.appendingPathComponent("sessions/106.json")) // Filename mismatch.
        try Data("ignored-peer-credential".utf8).write(to: account.home.appendingPathComponent("sessions/101.test.key"))
        var scanner = SessionScanner(root: space.root, processes: processes)
        let result = scanner.snapshot(accounts: [account, work])
        let activity = try #require(result[account.id])
        #expect(activity.sessions.count == 4)
        #expect(activity.workingCount == 1)
        #expect(activity.sessions.first?.state == .working)
        #expect(activity.sessions.first?.since == testNow.addingTimeInterval(-6 * 86_400))
        #expect(activity.sessions.first?.directory == "/synthetic/registry-project")
        #expect(result[work.id]?.sessions.count == 1)
        #expect(result[work.id]?.workingCount == 0)
        processes.set([])
        #expect(scanner.snapshot(accounts: [account, work]).values.allSatisfy { $0.sessions.isEmpty })
    }

    @Test func defaultUnregisteredProcessAndUnreadableEnvironment() throws {
        let space = try TestSpace()
        let account = try space.account()
        let processes = TestProcesses()
        let first = testProcess(101, home: account.home)
        let second = testProcess(102, home: account.home)
        let defaultProcess = RunningProcess(pid: 101, parentPID: 1, executablePath: "/synthetic/claude", arguments: ["claude"],
            environment: ["HOME": space.root.path], workingDirectory: "/synthetic/default-project", startTime: testNow)
        processes.set([first.0, second.0], details: [defaultProcess])
        var scanner = SessionScanner(root: space.root, processes: processes)
        let result = scanner.snapshot(accounts: [account])
        #expect(result[account.id]?.sessions.count == 1)
        #expect(result[account.id]?.sessions.first?.directory == "/synthetic/default-project")
        #expect(result[account.id]?.sessions.first?.state == .idle)
        try registry(space, account: account, pid: 102, status: "busy")
        #expect(scanner.snapshot(accounts: [account])[account.id]?.sessions.count == 2)
    }

    @Test func registryChangesEmitOnceAndCancellationStopsPolling() async throws {
        let space = try TestSpace()
        let account = try space.account()
        let processes = TestProcesses()
        let pair = testProcess(101, home: account.home)
        processes.set([pair.0], details: [pair.1])
        try registry(space, account: account, pid: 101, status: "idle")
        let monitor = SessionMonitor(root: space.root, processes: processes, pollInterval: .milliseconds(100))
        let states = SessionStates()
        let consumer = Task {
            for await state in monitor.activity(for: [account]) { await states.append(state) }
        }
        #expect(await eventually { await states.count == 1 })
        let firstID = await states.last?[account.id]?.sessions.first?.id
        try registry(space, account: account, pid: 101, status: "busy", since: testNow.addingTimeInterval(1))
        #expect(await eventually { await states.last?[account.id]?.isWorking == true })
        #expect(await states.last?[account.id]?.sessions.first?.id == firstID)
        try await Task.sleep(for: .milliseconds(250))
        #expect(await states.count == 2)
        processes.set([])
        #expect(await eventually { await states.last?[account.id]?.sessions.isEmpty == true })
        consumer.cancel()
        await consumer.value
        try await Task.sleep(for: .milliseconds(50))
        let calls = processes.calls
        try await Task.sleep(for: .milliseconds(250))
        #expect(processes.calls == calls)
    }

    @Test func directoryEventsUpdateBeforeNextProcessPoll() async throws {
        let space = try TestSpace()
        let account = try space.account()
        let processes = TestProcesses()
        let pair = testProcess(101, home: account.home)
        processes.set([pair.0], details: [pair.1])
        try registry(space, account: account, pid: 101, status: "idle")
        let monitor = SessionMonitor(root: space.root, processes: processes, pollInterval: .seconds(2))
        let states = SessionStates()
        let consumer = Task {
            for await state in monitor.activity(for: [account]) { await states.append(state) }
        }
        defer { consumer.cancel() }
        #expect(await eventually { await states.count == 1 })
        try registry(space, account: account, pid: 101, status: "busy")
        #expect(await eventually { await states.last?[account.id]?.isWorking == true })
        #expect(processes.calls == 1)
        consumer.cancel()
        await consumer.value
    }

    @Test func returningAfterInitialStateReleasesMonitor() async throws {
        let space = try TestSpace()
        let account = try space.account()
        let processes = TestProcesses()
        let monitor = SessionMonitor(root: space.root, processes: processes, pollInterval: .milliseconds(50))
        let state = await initialState(monitor, accounts: [account])
        #expect(state[account.id] == AccountActivity.none)
        try await Task.sleep(for: .milliseconds(100))
        let calls = processes.calls
        try await Task.sleep(for: .milliseconds(150))
        #expect(processes.calls == calls)
    }

    private func registry(_ space: TestSpace, account: Account, pid: Int32, status: String,
                          start: Date = testNow, since: Date = testNow) throws {
        try space.write(["pid": pid, "procStart": startString(start), "pidDomain": "darwin", "status": status,
                         "sessionId": "synthetic-session", "cwd": "/synthetic/registry-project",
                         "startedAt": start.addingTimeInterval(3).timeIntervalSince1970 * 1_000,
                         "statusUpdatedAt": since.timeIntervalSince1970 * 1_000],
                        to: account.home.appendingPathComponent("sessions/\(pid).json"))
    }

    private func startString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        return formatter.string(from: date)
    }

    private func initialState(_ monitor: SessionMonitor, accounts: [Account]) async -> [AccountID: AccountActivity] {
        for await state in monitor.activity(for: accounts) { return state }
        return [:]
    }

    private func eventually(_ condition: () async -> Bool) async -> Bool {
        for _ in 0..<50 {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return false
    }
}

private actor SessionStates {
    private var values: [[AccountID: AccountActivity]] = []
    var count: Int { values.count }
    var last: [AccountID: AccountActivity]? { values.last }
    func append(_ state: [AccountID: AccountActivity]) { values.append(state) }
}
