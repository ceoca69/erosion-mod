import Foundation
import Darwin

/// Read-only filesystem capability used by the System Paths section.
/// It deliberately does not request or grant sandbox extensions and never performs writes.
enum SystemReadOnlyAccess {
    static let roots: Set<String> = [
        "/System/Library",
        "/System/Developer",
        "/System/Cryptexes",
        // Cryptex entries such as /System/Cryptexes/OS are commonly
        // represented to Foundation as symlinks into the Preboot Cryptex
        // store. Keep those resolved paths inside the same read-only scope.
        "/private/preboot/Cryptexes",
        "/System/Volumes/Preboot/Cryptexes"
    ]

    static func isSystemPath(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return roots.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    static func canReadDirectory(_ url: URL) -> Bool {
        guard isSystemPath(url) else { return false }
        guard access(url.path, R_OK | X_OK) == 0 else { return false }
        guard let dir = opendir(url.path) else { return false }
        closedir(dir)
        return true
    }

    /// The system volume is treated as read-only by Erosion even if a future
    /// environment reports a writable POSIX bit. This is an application-level
    /// safety boundary for this viewer.
    static func isReadOnly(_ url: URL) -> Bool {
        isSystemPath(url)
    }
}
