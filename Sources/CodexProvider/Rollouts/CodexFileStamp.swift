import Darwin
import Foundation

struct CodexFileStamp: Codable, Equatable, Sendable {
    let device: Int32
    let inode: UInt64
    let size: UInt64
    let modifiedSeconds: Int
    let modifiedNanoseconds: Int

    var modifiedAt: Date { Date(timeIntervalSince1970: Double(modifiedSeconds) + Double(modifiedNanoseconds) / 1_000_000_000) }

    init(device: Int32, inode: UInt64, size: UInt64, modifiedSeconds: Int, modifiedNanoseconds: Int) {
        self.device = device
        self.inode = inode
        self.size = size
        self.modifiedSeconds = modifiedSeconds
        self.modifiedNanoseconds = modifiedNanoseconds
    }

    init?(_ url: URL) {
        var info = stat()
        guard stat(url.path, &info) == 0 else { return nil }
        self.init(info)
    }

    init?(_ info: stat) {
        guard info.st_size >= 0, info.st_mode & S_IFMT == S_IFREG else { return nil }
        device = info.st_dev
        inode = info.st_ino
        size = UInt64(info.st_size)
        modifiedSeconds = info.st_mtimespec.tv_sec
        modifiedNanoseconds = info.st_mtimespec.tv_nsec
    }
}
