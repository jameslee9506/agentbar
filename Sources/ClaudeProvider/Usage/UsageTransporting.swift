import Foundation

protocol UsageTransporting: Sendable {
    func send(_ request: URLRequest) async throws -> UsageResponse
}

