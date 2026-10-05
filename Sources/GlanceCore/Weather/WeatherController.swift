import Foundation
import Combine

@MainActor
final class WeatherController: ObservableObject {
    @Published private(set) var snapshot: WeatherSnapshot?
    @Published private(set) var updatedAt: Date?
    @Published private(set) var isUnavailable = false
    @Published private(set) var isLoading = false
    private let connection = JSONLineProcess()
    private let executable: URL
    private var shortcutName = ""
    private var lastAttempt: Date?
    private var visible = false
    // Exclusively main-actor owned while alive; deinit only removes this request's temporary file.
    nonisolated(unsafe) private var outputFile: URL?

    init(executable: URL = URL(fileURLWithPath: "/usr/bin/shortcuts")) {
        self.executable = executable
    }

    static func shouldRefresh(shortcutName: String, lastAttempt: Date?, now: Date) -> Bool {
        !shortcutName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (lastAttempt.map { now.timeIntervalSince($0) >= 900 } ?? true)
    }

    func setVisible(_ visible: Bool, shortcutName rawName: String) {
        self.visible = visible
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        if shortcutName != name {
            stopRequest()
            shortcutName = name; snapshot = nil; updatedAt = nil; lastAttempt = nil; isUnavailable = false
        }
        guard visible else {
            if isLoading { lastAttempt = nil }
            stopRequest()
            return
        }
        guard !isLoading, Self.shouldRefresh(shortcutName: shortcutName, lastAttempt: lastAttempt, now: Date()) else { return }
        lastAttempt = Date()
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("glance-weather-\(UUID().uuidString).txt")
        outputFile = file
        isLoading = true
        do {
            try connection.start(executable: executable, arguments: ["run", shortcutName, "--output-type", "public.plain-text", "--output-path", file.path], timeout: 20, keepsInputOpen: false,
                onLine: { _ in }, onExit: { [weak self] status in
                    guard let self, self.visible, self.outputFile == file else { return }
                    defer { self.stopRequest() }
                    guard status == 0,
                          let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
                          let size = attributes[.size] as? NSNumber, size.intValue <= 4096,
                          let data = try? Data(contentsOf: file),
                          let text = String(data: data, encoding: .utf8),
                          let snapshot = WeatherSnapshot.fromShortcut(text) else {
                        self.snapshot = nil; self.updatedAt = nil; self.lastAttempt = nil; self.isUnavailable = true
                        return
                    }
                    self.snapshot = snapshot
                    self.updatedAt = Date()
                    self.isUnavailable = false
                })
        } catch {
            stopRequest(); snapshot = nil; updatedAt = nil; lastAttempt = nil; isUnavailable = true
        }
    }

    private func stopRequest() {
        connection.stop()
        isLoading = false
        if let file = outputFile {
            try? FileManager.default.removeItem(at: file)
            // The owned child is forcibly stopped within 0.5s; cover an atomic write racing cancellation.
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
                try? FileManager.default.removeItem(at: file)
            }
        }
        outputFile = nil
    }

    deinit {
        if let outputFile { try? FileManager.default.removeItem(at: outputFile) }
    }
}
