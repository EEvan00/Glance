import SwiftUI

struct CodexUsageView: View {
    @ObservedObject var controller: CodexUsageController
    @EnvironmentObject private var localization: Localization
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: CompactPopupLayout.gap) {
                    Button(action: onBack) { PopupChevron(symbol: "chevron.backward") }
                        .buttonStyle(.plain).accessibilityLabel(localization.string(.commonBack))
                    Text("Codex").font(.headline)
                    Spacer()
                    if controller.isLoading { ProgressView().controlSize(.small) }
                }
                if let snapshot = controller.snapshot {
                    ForEach(snapshot.windows) { window in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(windowLabel(window, localization: localization)).font(.subheadline)
                                Spacer()
                                Text(remainingLabel(window, localization: localization)).monospacedDigit()
                            }
                            if let remaining = window.remainingPercent {
                                PopupProgressBar(percent: Double(remaining))
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(windowLabel(window, localization: localization))
                                .accessibilityValue(remainingLabel(window, localization: localization))
                            }
                            if let reset = window.resetsAt {
                                Text(localization.format(.codexResetFull, Date(timeIntervalSince1970: reset).formatted(date: .abbreviated, time: .shortened)))
                                    .font(.caption).foregroundStyle(.primary.opacity(0.78))
                            }
                        }
                    }
                } else {
                    Text(localization.string(controller.isLoading ? .codexLoading : .codexUnavailable)).foregroundStyle(.primary.opacity(0.78))
                }
                if controller.isUnavailable, controller.snapshot != nil {
                    Text(localization.string(.codexCached)).font(.caption).foregroundStyle(.primary.opacity(0.78))
                }
            }
            HStack {
                if let updated = controller.updatedAt {
                    Text(localization.format(.codexUpdated, updated.formatted(date: .omitted, time: .shortened)))
                        .font(.caption).foregroundStyle(.primary.opacity(0.78))
                }
                Spacer()
                Button { controller.refreshNow() } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(localization.string(.codexRefreshNow))
                .disabled(controller.isLoading)
            }
            .popupFooterInsets()
        }
    }
}

@MainActor
func remainingLabel(_ window: CodexUsageWindow, localization: Localization) -> String {
    guard let remaining = window.remainingPercent else { return "—" }
    return localization.format(.codexRemaining, remaining)
}

@MainActor
func windowLabel(_ window: CodexUsageWindow, localization: Localization) -> String {
    switch window.windowDurationMins {
    case 300: return localization.string(.codexFiveHours)
    case 10080: return localization.string(.codexWeekly)
    case .some(let minutes): return localization.format(.codexWindowMinutes, minutes)
    case .none: return window.id
    }
}
