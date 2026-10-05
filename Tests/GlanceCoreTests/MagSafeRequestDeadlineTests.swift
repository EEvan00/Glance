import AppKit
import Testing
@testable import GlanceCore

@MainActor
struct MagSafeRequestDeadlineTests {
    @Test func missingHelperReplyFinishesRequestAndIgnoresLateReply() async throws {
        var result: Result<Bool, Error>?
        var request: MagSafeLEDXPCRequest?
        let operation = Task {
            do {
                let value: Bool = try await withCheckedThrowingContinuation { continuation in
                    request = MagSafeLEDXPCRequest(
                        connection: NSXPCConnection(machServiceName: "GlanceTests.Unused"),
                        continuation: continuation, timeout: 0.02)
                }
                result = .success(value)
            } catch { result = .failure(error) }
        }
        for _ in 0..<30 {
            if result != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(result != nil, "A helper that never replies must not leave the UI busy forever")
        if case .success = result { Issue.record("Missing reply should fail, not succeed") }
        // A late reply must neither change the timeout result nor resume twice.
        request?.finish(.success(true))
        await operation.value
    }
}
