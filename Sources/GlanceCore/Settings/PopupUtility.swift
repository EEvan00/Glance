import Foundation

enum PopupUtility: String, CaseIterable, Identifiable, Sendable {
    case performance, codex, claude
    var id: String { rawValue }
    var labelKey: LocalizationKey {
        switch self {
        case .performance: .performanceTitle
        case .codex: .utilityCodex
        case .claude: .utilityClaude
        }
    }
}

/// Optional full-width rows above the footer, independent of the card choice.
enum PopupUtilityRow: String, CaseIterable, Identifiable, Sendable {
    case none, performance, codex, claude
    var id: String { rawValue }
    var utility: PopupUtility? {
        self == .none ? nil : PopupUtility(rawValue: rawValue)
    }
    var labelKey: LocalizationKey { utility?.labelKey ?? .compactOff }
}
