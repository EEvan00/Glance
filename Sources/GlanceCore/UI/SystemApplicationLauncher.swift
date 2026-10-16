import AppKit

/// Launch system apps through Launch Services, including their launch constraints.
@MainActor
enum SystemApplicationLauncher {
    static func open(_ url: URL, arguments: [String] = []) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = arguments
        // Mission Control must receive the desktop argument on every invocation.
        configuration.createsNewApplicationInstance = !arguments.isEmpty
        try await awaitCompletion { reply in
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { @Sendable _, error in
                reply(error)
            }
        }
    }

    static func awaitCompletion(_ start: (@escaping @Sendable (Error?) -> Void) -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // Workspace replies on its own queue. Capture only the Sendable
            // continuation, never MainActor state or NSRunningApplication.
            start { @Sendable error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }
}
