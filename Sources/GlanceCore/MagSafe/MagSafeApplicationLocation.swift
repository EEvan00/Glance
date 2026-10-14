import Darwin
import Foundation

/// Tracks the original bundle, not a later replacement at the same path.
struct MagSafeApplicationLocation: Sendable {
    private let path: String
    private let device: dev_t
    private let inode: ino_t
    private let valid: Bool

    init(url: URL) {
        let url = url.standardizedFileURL.resolvingSymlinksInPath()
        path = url.path
        var info = stat()
        valid = !url.pathComponents.contains(where: { $0 == ".Trash" || $0 == ".Trashes" })
            && lstat(url.path, &info) == 0
        device = info.st_dev
        inode = info.st_ino
    }

    var isPresent: Bool {
        var info = stat()
        return valid && lstat(path, &info) == 0 && info.st_dev == device && info.st_ino == inode
    }
}
