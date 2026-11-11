import Darwin
import Foundation

struct TranscriptFileStamp: Codable, Equatable, Sendable {
    struct Identity: Hashable, Sendable {
        let device: Int32
        let inode: UInt64
    }
    let device: Int32
    let inode: UInt64
    let size: UInt64
    let modifiedSeconds: Int64
    let modifiedNanoseconds: Int64
    let changedSeconds: Int64
    let changedNanoseconds: Int64

    var identity: Identity { Identity(device: device, inode: inode) }
    var modifiedAt: Date {
        Date(timeIntervalSince1970: Double(modifiedSeconds) + Double(modifiedNanoseconds) / 1_000_000_000)
    }

    static func read(_ file: URL) -> Self? {
        var info = stat()
        guard file.withUnsafeFileSystemRepresentation({ path in
            guard let path else { return false }
            return lstat(path, &info) == 0
        }), info.st_mode & S_IFMT == S_IFREG, info.st_size >= 0 else { return nil }
        return Self(device: info.st_dev, inode: info.st_ino, size: UInt64(info.st_size),
                    modifiedSeconds: Int64(info.st_mtimespec.tv_sec), modifiedNanoseconds: Int64(info.st_mtimespec.tv_nsec),
                    changedSeconds: Int64(info.st_ctimespec.tv_sec), changedNanoseconds: Int64(info.st_ctimespec.tv_nsec))
    }
}
