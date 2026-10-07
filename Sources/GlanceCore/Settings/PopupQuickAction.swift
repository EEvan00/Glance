import Foundation

enum PopupQuickAction: String, CaseIterable, Identifiable, Sendable {
    case timer, screenshot, calculator, notes, reminders, shortcut, application
    var id: String { rawValue }
    var labelKey: LocalizationKey {
        switch self {
        case .timer: .timerTitle
        case .screenshot: .compactScreenshot
        case .calculator: .quickCalculator
        case .notes: .quickNotes
        case .reminders: .quickReminders
        case .shortcut: .quickShortcut
        case .application: .quickApplication
        }
    }
    var symbol: String {
        switch self {
        case .timer: "timer"
        case .screenshot: "square.dashed"
        case .calculator: "plus.forwardslash.minus"
        case .notes: "note.text"
        case .reminders: "checklist"
        case .shortcut: "square.stack.3d.up"
        case .application: "app"
        }
    }
    func launchURL(applicationPath: String, shortcutName: String) -> URL? {
        switch self {
        case .calculator: URL(fileURLWithPath: "/System/Applications/Calculator.app")
        case .notes: URL(fileURLWithPath: "/System/Applications/Notes.app")
        case .reminders: URL(fileURLWithPath: "/System/Applications/Reminders.app")
        case .application:
            applicationPath.isEmpty ? nil : URL(fileURLWithPath: applicationPath)
        case .shortcut:
            shortcutName.isEmpty ? nil : Self.shortcutURL(name: shortcutName)
        case .timer, .screenshot: nil
        }
    }
    static func shortcutURL(name: String) -> URL? {
        var url = URLComponents(string: "shortcuts://run-shortcut")
        url?.queryItems = [URLQueryItem(name: "name", value: name)]
        return url?.url
    }
}
