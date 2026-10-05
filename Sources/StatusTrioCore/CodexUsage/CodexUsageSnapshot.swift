import Foundation

struct CodexUsageWindow: Identifiable, Equatable, Sendable {
    let id: String
    let usedPercent: Double?
    let windowDurationMins: Int?
    let resetsAt: TimeInterval?

    var remainingPercent: Int? {
        guard let usedPercent, usedPercent.isFinite else { return nil }
        return Int(min(100, max(0, 100 - usedPercent)).rounded())
    }
}

struct CodexUsageSnapshot: Equatable, Sendable {
    let windows: [CodexUsageWindow]

    static func decode(_ data: Data) throws -> Self {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.coderReadCorrupt)
        }
        let buckets = root["rateLimitsByLimitId"] as? [String: [String: Any]]
            ?? ["codex": root["rateLimits"] as? [String: Any] ?? [:]]
        var windows: [CodexUsageWindow] = []
        for bucket in buckets.keys.sorted() {
            for key in ["primary", "secondary"] {
                guard let window = buckets[bucket]?[key] as? [String: Any] else { continue }
                windows.append(CodexUsageWindow(
                    id: "\(bucket).\(key)",
                    usedPercent: window["usedPercent"] as? Double,
                    windowDurationMins: window["windowDurationMins"] as? Int,
                    resetsAt: window["resetsAt"] as? Double
                ))
            }
        }
        return Self(windows: windows)
    }
}
