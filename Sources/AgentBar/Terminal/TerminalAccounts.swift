import AgentBarCore
import Foundation

/// Reads accounts once, for a command that prints them and exits.
enum TerminalAccounts {
    /// Usage read this recently is shown as it is: the app waits as long between two requests.
    static let freshness: TimeInterval = 60

    static func discover(_ providers: [any AccountProvider]) async -> [Account] {
        await withTaskGroup(of: [Account].self) { group in
            for provider in providers {
                group.addTask { await provider.accounts() }
            }
            return await group.reduce(into: []) { $0 += $1 }
        }
    }

    /// The usage, sessions, and tokens of `accounts`, in their order. Usage that cannot be read now
    /// stays as it was last known, with the error.
    static func load(
        _ accounts: [Account], from providers: [any AccountProvider],
        now: @escaping @Sendable () -> Date = Date.init, activityTimeout: Duration = .seconds(3)
    ) async -> [AccountState] {
        await withTaskGroup(of: Part.self) { group in
            for provider in providers {
                let own = accounts.filter { $0.id.provider == provider.kind }
                guard !own.isEmpty else { continue }
                group.addTask { .activity(await activity(of: own, from: provider, timeout: activityTimeout)) }
                for account in own {
                    group.addTask { .state(await state(of: account, from: provider, now: now)) }
                }
            }
            var states: [AccountID: AccountState] = [:]
            var activity: [AccountID: AccountActivity] = [:]
            for await part in group {
                switch part {
                case .state(let state): states[state.id] = state
                case .activity(let found): activity.merge(found) { $1 }
                }
            }
            return accounts.compactMap { account in
                var state = states[account.id]
                state?.activity = activity[account.id] ?? .none
                return state
            }
        }
    }

    private enum Part: Sendable {
        case state(AccountState)
        case activity([AccountID: AccountActivity])
    }

    private static func state(
        of account: Account, from provider: any AccountProvider, now: @Sendable () -> Date
    ) async -> AccountState {
        var state = AccountState(account: account)
        // The range the app loads, so that its statistics cache serves this read too.
        async let statistics = provider.statistics(for: account, days: 90)
        let cached = await provider.cachedUsage(for: account)
        if let cached, now().timeIntervalSince(cached.capturedAt) < freshness {
            state.usage = cached
            state.lastSuccessfulRefresh = cached.capturedAt
        } else {
            do {
                state.usage = try await provider.usage(for: account)
                state.lastSuccessfulRefresh = now()
            } catch {
                state.usage = cached
                state.usageError = error
            }
        }
        state.statistics = await statistics
        return state
    }

    /// The sessions open now: the first state the provider emits, or none when it takes too long.
    private static func activity(
        of accounts: [Account], from provider: any AccountProvider, timeout: Duration
    ) async -> [AccountID: AccountActivity] {
        let stream = provider.activity(for: accounts)
        return await withTaskGroup(of: [AccountID: AccountActivity]?.self) { group in
            group.addTask {
                for await state in stream { return state }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? [:]
        }
    }
}
