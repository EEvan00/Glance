import SwiftUI

struct PerformanceDetailsView: View {
    @ObservedObject var controller: PerformanceController
    @EnvironmentObject private var localization: Localization
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button(action: onBack) { PopupChevron(symbol: "chevron.backward") }
                    .buttonStyle(.plain).accessibilityLabel(localization.string(.commonBack))
                Text(localization.string(.performanceTitle)).font(.headline)
                Spacer()
            }
            if let snapshot = controller.snapshot {
                row(.performanceCPU, value: snapshot.cpuPercent.map { "\(Int($0.rounded()))%" } ?? "—")
                row(.performanceMemory, value: "\(bytes(snapshot.usedMemory)) / \(bytes(snapshot.totalMemory))")
                PopupProgressBar(percent: snapshot.memoryPercent)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(localization.string(.performanceMemory))
                    .accessibilityValue("\(Int(snapshot.memoryPercent.rounded()))%")
                row(.performancePressure, value: pressure(snapshot.pressure))
                Text(localization.string(.performanceMemoryHelp)).font(.caption).foregroundStyle(.secondary).lineLimit(nil).fixedSize(horizontal: false, vertical: true)
            } else {
                Text(localization.string(.performanceUnavailable)).foregroundStyle(.secondary).lineLimit(nil).fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 0) {
                PopupDivider()
                Button(localization.string(.performanceOpenActivityMonitor)) { controller.openActivityMonitor() }
                    .buttonStyle(.plain).popupFooterInsets()
            }
        }
    }

    private func row(_ key: LocalizationKey, value: String) -> some View {
        HStack {
            Text(localization.string(key)).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }.font(.subheadline)
    }
    private func bytes(_ value: UInt64) -> String { ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .memory) }
    private func pressure(_ value: PerformanceSnapshot.Pressure?) -> String {
        let key: LocalizationKey
        switch value {
        case .normal: key = .performancePressureNormal
        case .warning: key = .performancePressureWarning
        case .critical: key = .performancePressureCritical
        case nil: return "—"
        }
        return localization.string(key)
    }
}
