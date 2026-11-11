import Foundation

struct UsageResponse: Sendable {
    let status: Int
    let headers: [String: String]
    let data: Data
}
