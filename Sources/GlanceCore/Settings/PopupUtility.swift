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
