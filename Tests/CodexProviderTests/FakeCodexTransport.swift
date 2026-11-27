@testable import CodexProvider
import Foundation

actor FakeCodexTransport: CodexUsageTransport {
    let status: Int
    let headers: [String: String]
    let body: Data
    let fails: Bool
    private(set) var calls = 0
    private(set) var requestValid = false
    private(set) var tokens: [String] = []
    private var first: [Int]

    /// `first` statuses answer the first requests, then `status` answers the rest.
    init(status: Int = 200, first: [Int] = [], headers: [String: String] = [:], body: String = "{\"rate_limit\":{\"primary_window\":{\"used_percent\":25,\"limit_window_seconds\":604800}}}", fails: Bool = false) {
        self.status = status
        self.first = first
        self.headers = headers
        self.body = Data(body.utf8)
        self.fails = fails
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        calls += 1
        requestValid = request.url?.absoluteString == "https://chatgpt.com/backend-api/wham/usage"
            && request.httpMethod == "GET"
            && request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ") == true
            && request.value(forHTTPHeaderField: "ChatGPT-Account-Id") != nil
            && request.value(forHTTPHeaderField: "User-Agent") == "AgentBar/0.1"
        tokens.append(request.value(forHTTPHeaderField: "Authorization") ?? "")
        if fails { throw URLError(.timedOut) }
        let status = first.isEmpty ? status : first.removeFirst()
        return (body, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!)
    }
}

/// Stands in for the CLI: counts the requests and does what the test says to the home.
actor FakeCodexRenewal: CodexLoginRenewing {
    private(set) var calls = 0
    private let action: @Sendable (URL) -> Void

    init(_ action: @escaping @Sendable (URL) -> Void = { _ in }) { self.action = action }

    func renew(home: URL) {
        calls += 1
        action(home)
    }
}
