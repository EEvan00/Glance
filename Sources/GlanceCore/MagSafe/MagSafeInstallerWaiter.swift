import Foundation

@MainActor
enum MagSafeInstallerWaiter {
    static func waitForCompletion(
        completed: () -> Bool,
        isInstallerRunning: () -> Bool,
        isCorrupt: () -> Bool = { false },
        attempts: Int = 300,
        pause: () async throws -> Void = { try await Task.sleep(for: .seconds(1)) }
    ) async throws {
        for _ in 0..<attempts {
            try Task.checkCancellation()
            if completed() { return }
            if !isInstallerRunning() { throw CocoaError(.userCancelled) }
            if isCorrupt() { throw CocoaError(.fileReadCorruptFile) }
            try await pause()
        }
        throw CocoaError(.userCancelled)
    }
}
