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

    func resetCountdown(now: Date = Date()) -> String? {
        guard let resetsAt, resetsAt.isFinite else { return nil }
        let minutes = max(0, (resetsAt - now.timeIntervalSince1970) / 60)
        if minutes >= 1440 {
            return "\(Int(minutes / 1440))d \(Int(minutes.truncatingRemainder(dividingBy: 1440) / 60))h"
        }
        if minutes >= 60 {
            return "\(Int(minutes / 60))h \(Int(minutes.truncatingRemainder(dividingBy: 60)))m"
        }
        return "\(Int(ceil(minutes)))m"
    }
}

struct CodexUsageSnapshot: Equatable, Sendable {
    let windows: [CodexUsageWindow]

    // Popup summaries prefer the five-hour window, independent of API ordering.
    // Detail menus retain all windows in their original order.
    var preferredPopupWindow: CodexUsageWindow? {
        windows.first { $0.windowDurationMins == 300 } ?? windows.first
    }

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
