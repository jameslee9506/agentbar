import AgentBarCore
@testable import CodexProvider
import Foundation
import Testing

struct CodexUsageConcurrencyTests {
    @Test func historyInspectionDoesNotBlockAnotherAccountsLiveRequest() async throws {
        let fixture = try CodexFixture()
        let home = try fixture.home()
        let other = try fixture.home(".codex-other")
        try fixture.auth(home)
        try fixture.auth(other)
        let processes = BlockingProcesses()
        defer { processes.release() }
        let transport = FakeCodexTransport()
        let service = CodexUsageService(transport: transport, clock: { CodexFixture.date }, cache: DiskCache(directory: fixture.cache), rollouts: CodexRolloutUsage(), processes: processes)
        let cached = Task { await service.cachedUsage(for: fixture.account(home)) }
        let alsoCached = Task { await service.cachedUsage(for: fixture.account(home)) }
        let startDeadline = ContinuousClock.now.advanced(by: .seconds(1))
        while !processes.blocked && ContinuousClock.now < startDeadline { try await Task.sleep(for: .milliseconds(5)) }
        #expect(processes.blocked)
        let completed = ResultBox()
        let live = Task {
            let snapshot = try await service.usage(for: fixture.account(other))
            completed.store(snapshot)
            return snapshot
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while completed.value == nil && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        #expect(completed.value?.windows.first?.usedPercent == 25)
        #expect(processes.blocked)
        #expect(processes.pollCount == 1)
        processes.release()
        _ = try await live.value
        _ = await cached.value
        _ = await alsoCached.value
    }

    private final class ResultBox: @unchecked Sendable {
        private let lock = NSLock()
        private var result: UsageSnapshot?
        var value: UsageSnapshot? { lock.withLock { result } }
        func store(_ result: UsageSnapshot) { lock.withLock { self.result = result } }
    }

    private final class BlockingProcesses: ProcessListing, @unchecked Sendable {
        private let lock = NSLock()
        private let gate = DispatchSemaphore(value: 0)
        private var waiting = false
        private var calls = 0
        var blocked: Bool { lock.withLock { waiting } }
        var pollCount: Int { lock.withLock { calls } }
        func summaries() -> [ProcessSummary] {
            lock.withLock { waiting = true; calls += 1 }
            _ = gate.wait(timeout: .now() + 5)
            lock.withLock { waiting = false }
            return []
        }
        func release() { gate.signal() }
        func details(for pid: Int32) -> RunningProcess? { nil }
        func openFilePaths(of pid: Int32) -> [String] { [] }
        func isAlive(_ pid: Int32, startedAt: Date?) -> Bool { false }
    }
}
