@testable import CodexProvider
import Foundation

actor FakeCodexTransport: CodexUsageTransport {
    let status: Int
    let headers: [String: String]
    let body: Data
    let fails: Bool
    private(set) var calls = 0
    private(set) var requestValid = false

    init(status: Int = 200, headers: [String: String] = [:], body: String = "{\"rate_limit\":{\"primary_window\":{\"used_percent\":25,\"limit_window_seconds\":604800}}}", fails: Bool = false) {
        self.status = status
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
        if fails { throw URLError(.timedOut) }
        return (body, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!)
    }
}
