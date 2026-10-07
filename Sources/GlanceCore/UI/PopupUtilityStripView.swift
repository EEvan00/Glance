import SwiftUI

/// Uses the existing controllers and detail menus; never starts a separate reader.
struct PopupUtilityStripView: View {
    let utility: PopupUtility
    @ObservedObject var performance: PerformanceController
    @ObservedObject var codexUsage: CodexUsageController
    @ObservedObject var claudeUsage: ClaudeUsageController
    let date: Date
    let onOpen: () -> Void
    @EnvironmentObject private var localization: Localization

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: CompactPopupLayout.gap) {
                switch utility {
                case .performance:
                    Image(systemName: "cpu").font(.system(size: CompactPopupLayout.moduleIconSize))
                        .frame(width: CompactPopupLayout.unit)
                    if let snapshot = performance.snapshot {
                        Text(localization.format(.performanceCPUShort, snapshot.cpuPercent.map { "\(Int($0.rounded()))%" } ?? "—"))
                            .frame(width: CompactPopupLayout.singlePlaybackPreviousLeading - CompactPopupLayout.unit - CompactPopupLayout.gap * 2, alignment: .leading)
                        PerformanceMemoryFields(percent: Int(snapshot.memoryPercent.rounded()),
                                                capacity: "\(memory(snapshot.usedMemory))/\(memory(snapshot.totalMemory)) GB")
                        Spacer(minLength: 0)
                        Text(pressure(snapshot.pressure)).foregroundStyle(.primary.opacity(0.78))
                            .frame(width: 44, alignment: .trailing)
                    } else {
                        Text(localization.string(.performanceUnavailable))
                        Spacer(minLength: 0)
                    }
                case .codex, .claude:
                    UsageProviderIcon(provider: utility == .codex ? .codex : .claude)
                        .frame(width: CompactPopupLayout.unit)
                    if let window = snapshot?.preferredPopupWindow, let remaining = window.remainingPercent {
                        PopupProgressBar(percent: Double(remaining))
                            .frame(minWidth: 24, maxWidth: .infinity)
                            .accessibilityHidden(true)
                        Text("\(remaining)%").fontWeight(.semibold)
                        Text(isUnavailable ? localization.string(.compactCached) : window.resetCountdown(now: date).map { "↻ " + $0 } ?? "—")
                            .foregroundStyle(.primary.opacity(0.78))
                    } else {
                        Text(localization.string(isLoading ? .compactLoading : .compactUnavailable))
                            .foregroundStyle(.primary.opacity(0.78))
                        Spacer(minLength: 0)
                    }
                }
            }
            .font(.system(size: 10)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
            .padding(.trailing, utility == .performance ? CompactPopupLayout.gap : CompactPopupLayout.moduleTextInset)
            .frame(maxWidth: .infinity).frame(height: CompactPopupLayout.unit)
            .contentShape(Rectangle()).systemModuleSurface()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(localization.string(utility.labelKey))
        .accessibilityValue(accessibilityValue)
    }
    private var accessibilityValue: String {
        if utility == .performance {
            guard let snapshot = performance.snapshot else { return localization.string(.performanceUnavailable) }
            return localization.format(.performanceCPUShort, snapshot.cpuPercent.map { "\(Int($0.rounded()))%" } ?? "—")
                + ", RAM \(Int(snapshot.memoryPercent.rounded()))%, \(memory(snapshot.usedMemory))/\(memory(snapshot.totalMemory)) GB, "
                + pressure(snapshot.pressure)
        }
        guard let window = snapshot?.preferredPopupWindow, let remaining = window.remainingPercent else {
            return localization.string(isLoading ? .compactLoading : .compactUnavailable)
        }
        return localization.format(.codexRemaining, remaining) + ", "
            + (isUnavailable ? localization.string(.compactCached) : window.resetCountdown(now: date) ?? "—")
    }
    private var snapshot: CodexUsageSnapshot? { utility == .codex ? codexUsage.snapshot : claudeUsage.snapshot }
    private var isUnavailable: Bool { utility == .codex ? codexUsage.isUnavailable : claudeUsage.isUnavailable }
    private var isLoading: Bool { utility == .codex ? codexUsage.isLoading : claudeUsage.isLoading }
    private func memory(_ bytes: UInt64) -> String {
        (Double(bytes) / 1_073_741_824).formatted(.number.precision(.fractionLength(0...1)))
    }
    private func pressure(_ pressure: PerformanceSnapshot.Pressure?) -> String {
        switch pressure {
        case .normal: localization.string(.performancePressureNormal)
        case .warning: localization.string(.performancePressureWarning)
        case .critical: localization.string(.performancePressureCritical)
        case nil: "—"
        }
    }
}

private struct MemoryTextBoundsKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] { [:] }
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

/// Column starts stay fixed; only the separator follows the midpoint between text edges.
private struct PerformanceMemoryFields: View {
    let percent: Int
    let capacity: String

    var body: some View {
        HStack(spacing: 0) {
            Text("RAM \(percent)%")
                .anchorPreference(key: MemoryTextBoundsKey.self, value: .bounds) { ["percent": $0] }
                .frame(width: 54, alignment: .leading)
            Color.clear.frame(width: 12)
            Text(capacity)
                .anchorPreference(key: MemoryTextBoundsKey.self, value: .bounds) { ["capacity": $0] }
                .frame(width: 54, alignment: .leading)
        }
        .frame(width: 120, height: CompactPopupLayout.unit)
        .overlayPreferenceValue(MemoryTextBoundsKey.self) { bounds in
            GeometryReader { geometry in
                if let percent = bounds["percent"], let capacity = bounds["capacity"] {
                    Text("·")
                        .position(x: (geometry[percent].maxX + geometry[capacity].minX) / 2,
                                  y: geometry.size.height / 2)
                        .accessibilityHidden(true)
                }
            }.allowsHitTesting(false)
        }
    }
}
