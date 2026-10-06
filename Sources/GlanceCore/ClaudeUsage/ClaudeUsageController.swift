import Foundation
import Combine

@MainActor
final class ClaudeUsageController: ObservableObject {
    @Published private(set) var snapshot: CodexUsageSnapshot?
    @Published private(set) var updatedAt: Date?
    @Published private(set) var isUnavailable = false
    @Published private(set) var isLoading = false
    @Published private(set) var setupFailed = false
    private var isVisible = false
    private let cacheURL: URL

    init(cacheURL: URL = ClaudeUsageIntegration.cacheURL) { self.cacheURL = cacheURL }

    func setVisible(_ visible: Bool) {
        guard visible != isVisible else { return }
        isVisible = visible
        if visible { refreshNow() }
    }

    func refreshNow() {
        guard isVisible else { return }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: cacheURL.path)
            guard (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= 65536 else { throw CocoaError(.fileReadTooLarge) }
            let data = try Data(contentsOf: cacheURL)
            let result = try Self.decode(data, now: Date())
            snapshot = result.snapshot
            updatedAt = result.updatedAt
            isUnavailable = Date().timeIntervalSince(result.updatedAt) > 900
        } catch { snapshot = nil; updatedAt = nil; isUnavailable = true }
    }

    func connect() {
        do { try ClaudeUsageIntegration.install(); setupFailed = false }
        catch { setupFailed = true }
        refreshNow()
    }

    static func decode(_ data: Data, now: Date) throws -> (snapshot: CodexUsageSnapshot, updatedAt: Date) {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let updated = root["updated_at"] as? Double, updated.isFinite,
              updated > 0, updated <= now.timeIntervalSince1970 + 60,
              let limits = root["rate_limits"] as? [String: Any] else { throw CocoaError(.coderReadCorrupt) }
        let windows = [("five_hour", 300), ("seven_day", 10080)].compactMap { key, duration -> CodexUsageWindow? in
            guard let value = limits[key] as? [String: Any],
                  let used = value["used_percentage"] as? Double, used.isFinite, (0...100).contains(used),
                  let reset = value["resets_at"] as? Double, reset.isFinite, reset > now.timeIntervalSince1970 else { return nil }
            return CodexUsageWindow(id: "claude.\(key)", usedPercent: used, windowDurationMins: duration, resetsAt: reset)
        }
        guard !windows.isEmpty else { throw CocoaError(.coderReadCorrupt) }
        return (CodexUsageSnapshot(windows: windows), Date(timeIntervalSince1970: updated))
    }
}
