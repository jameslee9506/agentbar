import AgentBarCore
@testable import CodexProvider
import Foundation
import Testing

struct CodexSessionTests {
    @Test(arguments: [false, true], ["task_complete", "turn_aborted"])
    func bootstrapAndTailMatchTerminalsToTheirStarts(_ rootHints: Bool, _ terminal: String) throws {
        let fixture = try CodexFixture()
        let home = try fixture.home()
        let file = try fixture.rollout(home, lines: [
            fixture.metadata(), fixture.event("task_started", turn: "active", root: rootHints ? "active" : nil),
        ])
        let processes = FakeCodexProcesses()
        processes.own([file])
        let account = fixture.account(home)
        var running = CodexSessionMonitor(accounts: [account], processes: processes, rollouts: CodexRolloutUsage())
        #expect(running.poll()[account.id]?.workingCount == 1)
        try fixture.append([fixture.event(terminal, turn: "other", root: rootHints ? "other" : nil)], to: file)
        var fresh = CodexSessionMonitor(accounts: [account], processes: processes, rollouts: CodexRolloutUsage())
        let expected = running.poll()
        #expect(expected[account.id]?.workingCount == 1)
        #expect(fresh.poll() == expected)
        try fixture.append([fixture.event(terminal, turn: "active", at: CodexFixture.date.addingTimeInterval(1), root: rootHints ? "active" : nil)], to: file)
        #expect(fresh.poll() == running.poll())
        #expect(fresh.poll()[account.id]?.workingCount == 0)
    }

    @Test func nestedAndIDLessTerminalsAgreeWithForwardReplay() throws {
        let fixture = try CodexFixture()
        let home = try fixture.home()
        let file = try fixture.rollout(home, lines: [fixture.metadata(), fixture.event("task_started", turn: "active", root: "active")])
        let processes = FakeCodexProcesses()
        processes.own([file])
        let account = fixture.account(home)
        var running = CodexSessionMonitor(accounts: [account], processes: processes, rollouts: CodexRolloutUsage())
        _ = running.poll()
        for event in [
            fixture.event("task_started", turn: "nested", root: "active"),
            fixture.event("turn_aborted", turn: nil),
            fixture.event("task_complete", turn: "nested", root: "active"),
            fixture.event("turn_aborted", turn: nil),
        ] {
            try fixture.append([event], to: file)
            var fresh = CodexSessionMonitor(accounts: [account], processes: processes, rollouts: CodexRolloutUsage())
            #expect(fresh.poll() == running.poll())
        }
        #expect(running.poll()[account.id]?.workingCount == 0)
    }

    @Test func terminalAppendsDoNotCancelAnIncompleteBootstrap() throws {
        let fixture = try CodexFixture()
        let home = try fixture.home()
        let file = try fixture.rollout(home, lines: [fixture.metadata(), fixture.event("task_started", turn: "active", root: "active")])
        let processes = FakeCodexProcesses()
        processes.own([file])
        let account = fixture.account(home)
        var running = CodexSessionMonitor(accounts: [account], processes: processes, rollouts: CodexRolloutUsage())
        _ = running.poll()
        try fixture.append([String(repeating: "{\"type\":\"response_item\",\"payload\":{\"content\":\"ignored\"}}\n", count: 30_000)], to: file)
        var fresh = CodexSessionMonitor(accounts: [account], processes: processes, rollouts: CodexRolloutUsage(), bootstrapBudget: .zero)
        _ = fresh.poll()
        try fixture.append([fixture.event("task_complete", turn: "other", root: "other")], to: file)
        #expect(fresh.poll() == running.poll())
        #expect(fresh.poll()[account.id]?.workingCount == 1)
    }

    @Test func completedRootBoundsAnIdleBootstrap() throws {
        let fixture = try CodexFixture()
        let home = try fixture.home()
        let file = try fixture.rollout(home, lines: [
            fixture.metadata(),
            String(repeating: "{\"type\":\"response_item\",\"payload\":{\"content\":\"ignored\"}}\n", count: 30_000),
            fixture.event("task_started", root: "turn"), fixture.event("task_complete", root: "turn"),
        ])
        let thread = try #require(CodexOwnedThread(file: file, home: home, rollouts: CodexRolloutUsage()))
        #expect(!thread.isSearching)
        #expect(thread.turns.running.isEmpty)
        #expect(thread.turns.endedAt == CodexFixture.date)
    }

    @Test func sharedSessionFoldsALiveGrandchildWithAMissingIntermediateParent() throws {
        let fixture = try CodexFixture()
        let home = try fixture.home()
        let root = try fixture.rollout(home, name: "root", lines: [
            fixture.row("session_meta", ["id": "root", "session_id": "tree", "cwd": "/projects/root"]),
            fixture.event("task_complete"),
        ])
        let child = try fixture.rollout(home, name: "grandchild", lines: [
            fixture.metadata("grandchild", parent: "missing-parent", boundary: 10, session: "tree"),
            fixture.event("task_started", ordinal: 11),
        ])
        let parent = try fixture.rollout(home, name: "parent", lines: [fixture.metadata("missing-parent", parent: "root", session: "tree")])
        let old = home.appendingPathComponent("sessions/2000/01/01/parent.jsonl")
        try FileManager.default.createDirectory(at: old.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: parent, to: old)
        for index in 0..<12 { _ = try fixture.rollout(home, name: "recent-\(index)", lines: [fixture.metadata("recent-\(index)")]) }
        let processes = FakeCodexProcesses()
        processes.own([root, child], mode: "app-server")
        let account = fixture.account(home)
        var monitor = CodexSessionMonitor(accounts: [account], processes: processes, rollouts: CodexRolloutUsage())
        let activity = try #require(monitor.poll()[account.id])
        #expect(activity.sessions.count == 1)
        #expect(activity.workingCount == 1)
        #expect(activity.sessions.first?.id == "tree")
        #expect(activity.sessions.first?.directory == "/projects/root")
        processes.own([child], mode: "app-server")
        #expect(monitor.poll()[account.id]?.sessions.first?.id == "tree")
    }

    @Test func execOwnershipAndExitOverrideStaleTurnStarts() throws {
        let fixture = try CodexFixture()
        let home = try fixture.home()
        let file = try fixture.rollout(home, lines: [fixture.metadata(), fixture.event("task_started")])
        let processes = FakeCodexProcesses()
        processes.own([file])
        var monitor = CodexSessionMonitor(accounts: [fixture.account(home)], processes: processes, rollouts: CodexRolloutUsage())
        let activity = monitor.poll()[fixture.account(home).id]
        #expect(activity?.workingCount == 1)
        #expect(activity?.sessions.first?.directory == "/projects/example")
        #expect(activity?.sessions.first?.since == CodexFixture.date)
        processes.remove()
        #expect(monitor.poll()[fixture.account(home).id] == AccountActivity.none)
        processes.own([file], start: CodexFixture.date.addingTimeInterval(60))
        #expect(monitor.poll()[fixture.account(home).id]?.workingCount == 0)
    }

    @Test func daemonOwnsSeveralThreadsAndChildrenFoldIntoRoots() throws {
        let fixture = try CodexFixture()
        let home = try fixture.home()
        let root = try fixture.rollout(home, name: "root", lines: [fixture.metadata("root", session: "root"), fixture.event("task_complete")])
        let other = try fixture.rollout(home, name: "other", lines: [fixture.metadata("other", session: "other"), fixture.event("task_started", at: CodexFixture.date.addingTimeInterval(-5))])
        let child = try fixture.rollout(home, name: "child", lines: [
            fixture.metadata("child", parent: "root", boundary: 10, session: "root"), fixture.metadata("root", session: "root"),
            fixture.event("task_started", turn: "inherited", ordinal: 3),
            fixture.event("task_started", turn: "child-turn", ordinal: 11),
        ])
        let processes = FakeCodexProcesses()
        processes.own([root, other, child], mode: "app-server")
        // An additional owner of a root does not create another session.
        processes.own([root], pid: 43)
        var monitor = CodexSessionMonitor(accounts: [fixture.account(home)], processes: processes, rollouts: CodexRolloutUsage())
        let activity = try #require(monitor.poll()[fixture.account(home).id])
        #expect(activity.sessions.count == 2)
        #expect(activity.workingCount == 2)
        #expect(activity.sessions.first?.id == "root")
        try fixture.append([fixture.event("turn_aborted", turn: "child-turn", at: CodexFixture.date.addingTimeInterval(1), ordinal: 12)], to: child)
        let ended = try #require(monitor.poll()[fixture.account(home).id])
        #expect(ended.workingCount == 1)
        #expect(ended.sessions.first?.id == "other")
        #expect(ended.sessions.last?.since == CodexFixture.date.addingTimeInterval(1))
    }

    @Test func matchingCompletionAndIDLessAbortEndTurns() throws {
        let fixture = try CodexFixture()
        let home = try fixture.home()
        let file = try fixture.rollout(home, lines: [fixture.metadata(), fixture.event("task_started")])
        let processes = FakeCodexProcesses()
        processes.own([file])
        var monitor = CodexSessionMonitor(accounts: [fixture.account(home)], processes: processes, rollouts: CodexRolloutUsage())
        #expect(monitor.poll()[fixture.account(home).id]?.isWorking == true)
        try fixture.append([fixture.event("task_complete", turn: "other-turn")], to: file)
        #expect(monitor.poll()[fixture.account(home).id]?.isWorking == true)
        try fixture.append([fixture.event("task_complete", at: CodexFixture.date.addingTimeInterval(1))], to: file)
        #expect(monitor.poll()[fixture.account(home).id]?.isWorking == false)
        try fixture.append([fixture.event("task_started", turn: "again", at: CodexFixture.date.addingTimeInterval(2))], to: file)
        #expect(monitor.poll()[fixture.account(home).id]?.isWorking == true)
        try fixture.append([fixture.event("turn_aborted", turn: nil, at: CodexFixture.date.addingTimeInterval(3))], to: file)
        #expect(monitor.poll()[fixture.account(home).id]?.sessions.first?.since == CodexFixture.date.addingTimeInterval(3))
        #expect(monitor.poll()[fixture.account(home).id]?.isWorking == false)
    }

    @Test func backwardBootstrapContinuesOnUnchangedFilesWithoutDelayingOtherThreads() throws {
        let fixture = try CodexFixture()
        let home = try fixture.home()
        let file = try fixture.rollout(home, lines: [fixture.metadata(), fixture.event("task_started"), String(repeating: "{\"type\":\"response_item\",\"payload\":{\"content\":\"ignored\"}}\n", count: 30_000)])
        let other = try fixture.rollout(home, name: "other", lines: [fixture.metadata("other", session: "other"), fixture.event("task_started")])
        let processes = FakeCodexProcesses()
        processes.own([file, other])
        var monitor = CodexSessionMonitor(accounts: [fixture.account(home)], processes: processes, rollouts: CodexRolloutUsage(), bootstrapBudget: .zero)
        let initial = try #require(monitor.poll()[fixture.account(home).id])
        #expect(initial.sessions.first { $0.id == "other" }?.state == .working)
        #expect(initial.workingCount == 1)
        #expect(monitor.poll()[fixture.account(home).id]?.workingCount == 2)
        try fixture.append([fixture.event("task_complete", at: CodexFixture.date.addingTimeInterval(1))], to: file)
        #expect(monitor.poll()[fixture.account(home).id]?.workingCount == 1)
        processes.remove()
        #expect(monitor.poll()[fixture.account(home).id]?.sessions.isEmpty == true)
    }

    @Test func streamEmitsChangesOnlyAndCancellationStopsPolling() async throws {
        let fixture = try CodexFixture()
        let home = try fixture.home()
        let file = try fixture.rollout(home, lines: [fixture.metadata(), fixture.event("task_started")])
        let processes = FakeCodexProcesses()
        processes.own([file])
        let recorder = ActivityRecorder()
        let stream = fixture.provider(processes: processes).activity(for: [fixture.account(home)])
        let consumer = Task {
            for await state in stream { await recorder.add(state) }
        }
        try await Task.sleep(for: .milliseconds(150))
        #expect(await recorder.count == 1)
        #expect(processes.pollCount >= 2)
        processes.remove()
        try await Task.sleep(for: .milliseconds(100))
        #expect(await recorder.count == 2)
        consumer.cancel()
        await consumer.value
        try await Task.sleep(for: .milliseconds(40))
        let stopped = processes.pollCount
        try await Task.sleep(for: .milliseconds(80))
        #expect(processes.pollCount == stopped)
    }

    @Test(arguments: ["task_complete", "turn_aborted"])
    func backwardBootstrapMatchesTheMostRecentTurn(_ ending: String) throws {
        let fixture = try CodexFixture()
        let home = try fixture.home()
        let endedAt = CodexFixture.date.addingTimeInterval(1)
        let file = try fixture.rollout(home, lines: [
            fixture.metadata(), fixture.event("task_started"), fixture.event(ending, at: endedAt),
            String(repeating: "{\"type\":\"response_item\",\"payload\":{\"content\":\"ignored\"}}\n", count: 30_000),
        ])
        let processes = FakeCodexProcesses()
        processes.own([file])
        var monitor = CodexSessionMonitor(accounts: [fixture.account(home)], processes: processes, rollouts: CodexRolloutUsage(), bootstrapBudget: .zero)
        _ = monitor.poll()
        let finished = try #require(monitor.poll()[fixture.account(home).id]?.sessions.first)
        #expect(finished.state == .idle)
        #expect(finished.since == endedAt)
        try fixture.append([String(fixture.event("task_started", turn: "next", at: endedAt.addingTimeInterval(1)).dropLast())], to: file)
        #expect(monitor.poll()[fixture.account(home).id]?.workingCount == 0)
        try fixture.append(["\n"], to: file)
        #expect(monitor.poll()[fixture.account(home).id]?.workingCount == 1)
    }

    @Test func endingIterationReleasesTheMonitor() async throws {
        let fixture = try CodexFixture()
        let home = try fixture.home()
        let file = try fixture.rollout(home, lines: [fixture.metadata()])
        let processes = FakeCodexProcesses()
        processes.own([file])
        let provider = fixture.provider(processes: processes)
        await takeFirst(provider: provider, account: fixture.account(home))
        try await Task.sleep(for: .milliseconds(50))
        let stopped = processes.pollCount
        try await Task.sleep(for: .milliseconds(100))
        #expect(processes.pollCount == stopped)
    }

    private func takeFirst(provider: CodexProvider, account: Account) async {
        for await _ in provider.activity(for: [account]) { break }
    }

    private actor ActivityRecorder {
        var count = 0
        func add(_ state: [AccountID: AccountActivity]) { count += 1 }
    }
}
