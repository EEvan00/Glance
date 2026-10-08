import Foundation

struct MagSafeInstallerSessionState {
    private var hasSeenWindow = false
    private let initialWindowDeadline: Date

    init(startedAt: Date, initialWindowGrace: TimeInterval = 10) {
        initialWindowDeadline = startedAt.addingTimeInterval(initialWindowGrace)
    }

    mutating func isActive(processTerminated: Bool, hasWindow: Bool, now: Date) -> Bool {
        guard !processTerminated else { return false }
        if hasWindow { hasSeenWindow = true }
        return hasWindow || (!hasSeenWindow && now < initialWindowDeadline)
    }
}
