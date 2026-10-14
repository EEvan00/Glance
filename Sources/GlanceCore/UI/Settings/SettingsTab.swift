import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    static var visibleCases: [SettingsTab] {
        allCases.filter { $0 != .updates }
    }
    case basics
    case menuBar
    case footerModules
    case audio
    case battery
    case updates
    case about

    var id: Self { self }

    var titleKey: LocalizationKey {
        switch self {
        case .basics: .settingsTabBasics
        case .menuBar: .settingsTabMenuBar
        case .footerModules: .footerModulesTitle
        case .audio: .settingsTabAudio
        case .battery: .settingsTabBattery
        case .updates: .settingsUpdatesTitle
        case .about: .settingsTabAbout
        }
    }

    var systemImage: String {
        switch self {
        case .basics: "gearshape"
        case .menuBar: "menubar.rectangle"
        case .footerModules: "square.grid.3x1.below.line.grid.1x2"
        case .audio: "hifispeaker"
        case .battery: "battery.100percent"
        case .updates: "arrow.triangle.2.circlepath"
        case .about: "info.circle"
        }
    }

    var tint: Color {
        switch self {
        case .basics: .blue
        case .menuBar: .indigo
        case .footerModules: .purple
        case .audio: .cyan
        case .battery: .green
        case .updates: .orange
        case .about: .gray
        }
    }
}
