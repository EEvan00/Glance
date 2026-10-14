import Foundation

enum FooterModuleKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case weather, date, clock, timer, screenshot, calculator, notes, reminders
    case application, shortcut, website, file, folder, downloads, lockScreen, showDesktop, keepAwake
    case battery, performance, output, wifi, bluetooth, codex, claude

    var id: String { rawValue }
    var allowsMultipleInstances: Bool {
        switch self {
        case .application, .shortcut, .website, .file, .folder: true
        default: false
        }
    }
    var utility: PopupUtility? {
        switch self {
        case .performance: .performance
        case .codex: .codex
        case .claude: .claude
        default: nil
        }
    }
}

struct FooterModule: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var kind: FooterModuleKind
    var width: Int
    var title: String
    var target: String

    init(id: UUID = UUID(), kind: FooterModuleKind, width: Int = 1, title: String = "", target: String = "") {
        self.id = id
        self.kind = kind
        self.width = width
        self.title = title
        self.target = target
    }

    private enum CodingKeys: String, CodingKey { case id, kind, width, title, target }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        kind = try values.decode(FooterModuleKind.self, forKey: .kind)
        width = try values.decode(Int.self, forKey: .width)
        title = try values.decodeIfPresent(String.self, forKey: .title) ?? ""
        target = try values.decodeIfPresent(String.self, forKey: .target) ?? ""
    }
}
