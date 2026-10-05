import Foundation
import Combine

@MainActor
final class CodexUsageController: ObservableObject {
    @Published private(set) var snapshot: CodexUsageSnapshot?
    @Published private(set) var updatedAt: Date?
    @Published private(set) var isLoading = false
    @Published private(set) var isUnavailable = false
    private let connection = JSONLineProcess()
    private let executable: () -> URL?

    init(executable: @escaping () -> URL? = { CodexUsageController.executableURL() }) {
        self.executable = executable
    }
    private var isVisible = false

    static func executableURL() -> URL? {
        let candidates = [
            "/Applications/Codex.app/Contents/Resources/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "/opt/homebrew/bin/codex", "/usr/local/bin/codex"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }

    func setVisible(_ visible: Bool) {
        guard isVisible != visible else { return }
        isVisible = visible
        if visible {
            refreshNow()
        } else {
            connection.stop()
            isLoading = false
        }
    }

    func refreshNow() {
        guard isVisible, !isLoading else { return }
        guard let executable = executable() else { isUnavailable = true; return }
        isLoading = true
        do {
            try connection.start(executable: executable, arguments: ["app-server", "--stdio"], timeout: 15,
                onLine: { [weak self] in self?.receive($0) },
                onExit: { [weak self] _ in
                    guard let self, self.isLoading else { return }
                    self.connection.stop()
                    self.isLoading = false
                    self.isUnavailable = true
                })
            try connection.send(["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "status_trio_usage", "version": "1.0.0"]]])
        } catch { connection.stop(); isLoading = false; isUnavailable = true }
    }

    private func receive(_ data: Data) {
        guard isVisible, let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = message["id"] as? Int else { return }
        if message["error"] != nil {
            connection.stop(); isLoading = false; isUnavailable = true
            return
        }
        if id == 1 {
            do {
                try connection.send(["method": "initialized", "params": [:]])
                try connection.send(["id": 2, "method": "account/rateLimits/read"])
            } catch { connection.stop(); isLoading = false; isUnavailable = true }
        } else if id == 2 {
            if let result = message["result"] as? [String: Any],
               let encoded = try? JSONSerialization.data(withJSONObject: result),
               let decoded = try? CodexUsageSnapshot.decode(encoded), !decoded.windows.isEmpty {
                snapshot = decoded
                updatedAt = Date()
                isUnavailable = false
            } else { isUnavailable = true }
            isLoading = false
            connection.stop()
        }
    }
}
