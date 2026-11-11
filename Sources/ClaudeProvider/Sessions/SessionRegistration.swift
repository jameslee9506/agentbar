import Foundation

struct SessionRegistration: Decodable {
    let pid: Int32
    let procStart: String
    let pidDomain: String?
    let cwd: String?
    let status: String?
    let statusUpdatedAt: Double?

    static func read(_ file: URL, within history: HistoryDirectory) -> Self? {
        guard file.pathExtension == "json", let filenamePID = Int32(file.deletingPathExtension().lastPathComponent),
              let resolved = history.resolve(file),
              let size = try? resolved.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 64 * 1024,
              let data = try? Data(contentsOf: resolved),
              let value = try? JSONDecoder().decode(Self.self, from: data),
              value.pid == filenamePID, value.pid > 0,
              value.pidDomain == nil || value.pidDomain == "darwin"
        else { return nil }
        return value
    }
}
