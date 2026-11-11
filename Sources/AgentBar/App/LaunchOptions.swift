import Foundation

struct LaunchOptions {
    let demo: Bool
    let log: Bool
    let snapshotDirectory: URL?

    init(arguments: [String]) throws {
        log = arguments.contains("--log")
        if let index = arguments.firstIndex(of: "--snapshot") {
            guard arguments.indices.contains(index + 1), !arguments[index + 1].hasPrefix("--") else {
                throw CocoaError(.fileNoSuchFile)
            }
            snapshotDirectory = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        } else {
            snapshotDirectory = nil
        }
        demo = arguments.contains("--demo") || snapshotDirectory != nil
    }
}
