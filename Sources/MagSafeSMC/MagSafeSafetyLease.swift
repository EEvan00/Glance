import Foundation

/// A bounded off request: a vanished client cannot leave the LED disabled.
/// All state and SMC writes share one lock so expiry cannot race a new command.
public final class MagSafeSafetyLease: @unchecked Sendable {
    private let lock = NSLock()
    private let duration: TimeInterval
    private let now: @Sendable () -> TimeInterval
    private let apply: @Sendable (MagSafeLEDCommand) -> Bool
    private var deadline: TimeInterval?
    private var shuttingDown = false

    public init(
        duration: TimeInterval = 30,
        now: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        apply: @escaping @Sendable (MagSafeLEDCommand) -> Bool
    ) {
        self.duration = duration
        self.now = now
        self.apply = apply
    }

    public var needsRestoration: Bool {
        lock.lock()
        defer { lock.unlock() }
        return deadline != nil
    }

    public func set(_ command: MagSafeLEDCommand) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !shuttingDown else { return false }
        if command == .off {
            // A failed readback may follow a successful hardware write.
            deadline = now() + duration
        }
        let succeeded = apply(command)
        if command == .system, succeeded { deadline = nil }
        return succeeded
    }

    public func renew() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !shuttingDown, let deadline, now() < deadline else { return false }
        self.deadline = now() + duration
        return true
    }

    @discardableResult
    public func expireIfNeeded() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let deadline, now() >= deadline else { return false }
        if apply(.system) {
            self.deadline = nil
            return true
        }
        // Retain failed restoration for the next watchdog tick.
        return false
    }

    public func restore() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard deadline != nil else { return true }
        guard apply(.system) else { return false }
        deadline = nil
        return true
    }

    public func shutdown() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        // Seal before restoring: a queued XPC request must not turn the LED off
        // between the final restore and process exit.
        shuttingDown = true
        guard deadline != nil else { return true }
        guard apply(.system) else { return false }
        deadline = nil
        return true
    }
}
