// Glance modifications by EEvan00, 2026. Original project notices: NOTICE.

enum FooterModuleCategory: String, CaseIterable, Identifiable {
    case information, tools, custom

    var id: String { rawValue }

    var titleKey: LocalizationKey {
        switch self {
        case .information: .footerInformation
        case .tools: .footerTools
        case .custom: .footerCustom
        }
    }
}

extension FooterModuleKind {
    var labelKey: LocalizationKey {
        switch self {
        case .weather: .weatherTitle
        case .date: .footerDate
        case .clock: .footerClock
        case .timer: .timerTitle
        case .screenshot: .compactScreenshot
        case .calculator: .quickCalculator
        case .notes: .quickNotes
        case .reminders: .quickReminders
        case .application: .quickApplication
        case .shortcut: .quickShortcut
        case .website: .footerWebsite
        case .file: .footerFile
        case .folder: .footerFolder
        case .downloads: .footerDownloads
        case .lockScreen: .footerLockScreen
        case .showDesktop: .footerShowDesktop
        case .keepAwake: .footerKeepAwake
        case .battery: .compactBattery
        case .performance: .performanceTitle
        case .output: .volumeOutputTitle
        case .wifi: .wifiTitle
        case .bluetooth: .bluetoothTitle
        case .codex: .utilityCodex
        case .claude: .utilityClaude
        }
    }

    var descriptionKey: LocalizationKey {
        switch self {
        case .weather: .footerDescriptionWeather
        case .date: .footerDescriptionDate
        case .clock: .footerDescriptionClock
        case .timer: .footerDescriptionTimer
        case .screenshot: .footerDescriptionScreenshot
        case .calculator: .footerDescriptionCalculator
        case .notes: .footerDescriptionNotes
        case .reminders: .footerDescriptionReminders
        case .application: .footerDescriptionApplication
        case .shortcut: .footerDescriptionShortcut
        case .website: .footerDescriptionWebsite
        case .file: .footerDescriptionFile
        case .folder: .footerDescriptionFolder
        case .downloads: .footerDescriptionDownloads
        case .lockScreen: .footerDescriptionLockScreen
        case .showDesktop: .footerDescriptionShowDesktop
        case .keepAwake: .footerKeepAwakeHelp
        case .battery: .footerDescriptionBattery
        case .performance: .footerDescriptionPerformance
        case .output: .footerDescriptionOutput
        case .wifi: .footerDescriptionWiFi
        case .bluetooth: .footerDescriptionBluetooth
        case .codex: .footerDescriptionCodex
        case .claude: .footerDescriptionClaude
        }
    }

    var symbol: String {
        switch self {
        case .weather: "cloud.sun.fill"
        case .date: "calendar"
        case .clock: "clock"
        case .timer: "timer"
        case .screenshot: "square.dashed"
        case .calculator: "plus.forwardslash.minus"
        case .notes: "note.text"
        case .reminders: "checklist"
        case .application: "app"
        case .shortcut: "square.stack.3d.up"
        case .website: "globe"
        case .file: "doc"
        case .folder: "folder"
        case .downloads: "arrow.down.circle"
        case .lockScreen: "lock.fill"
        case .showDesktop: "macwindow"
        case .keepAwake: "cup.and.saucer.fill"
        case .battery: "battery.100percent"
        case .performance: "cpu"
        case .output: "speaker.wave.2.fill"
        case .wifi: "wifi"
        case .bluetooth: "antenna.radiowaves.left.and.right"
        case .codex: "terminal"
        case .claude: "sparkles"
        }
    }

    var category: FooterModuleCategory {
        switch self {
        case .weather, .date, .clock, .battery, .performance, .output, .wifi, .bluetooth, .codex, .claude:
            .information
        case .timer, .screenshot, .calculator, .notes, .reminders, .downloads, .lockScreen, .showDesktop, .keepAwake:
            .tools
        case .application, .shortcut, .website, .file, .folder:
            .custom
        }
    }
}
