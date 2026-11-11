import Foundation

struct TemporaryDirectory: Sendable {
    let url: URL

    init() throws {
        let root = ProcessInfo.processInfo.environment["AGENTBAR_TEST_TEMP_ROOT"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory
        url = root.appendingPathComponent("AgentBarTests-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}
