import SwiftUI

struct FooterTileContent {
    var symbol: String
    var text: String
    var help: String
    var textOnly = false
    var isActive = false
    var showsHelp = true
    var kind: FooterModuleKind? = nil
    var wifi: WiFiStatus? = nil
}

/// Shared by the actual footer and its inert editor preview.
struct FooterModuleTile: View {
    let width: Int
    let content: FooterTileContent

    var body: some View {
        Group {
            if content.showsHelp {
                tile.help(Text(content.help))
            } else {
                tile
            }
        }
    }

    private var tile: some View {
        HStack(spacing: 3) {
            if width == 1 || !content.textOnly {
                FooterModuleIcon(kind: content.kind, symbol: content.symbol, wifi: content.wifi)
            }
            if width == 2 {
                Text(content.text).font(.system(size: 11)).monospacedDigit().lineLimit(1)
                    .frame(width: content.kind == .performance ? 31 : nil, alignment: .leading)
            }
        }
        .foregroundStyle(content.isActive ? Color.accentColor : Color.primary)
        .frame(width: CompactPopupLayout.span(width), height: CompactPopupLayout.unit)
        .clipped()
        .systemModuleSurface()
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.help)
    }
}

struct FooterModulesView: View {
    let layout: FooterLayout
    let content: (FooterModule) -> FooterTileContent
    let activate: (FooterModule) -> Void
    let openSettings: () -> Void
    let quit: () -> Void
    @EnvironmentObject private var localization: Localization

    var body: some View {
        HStack(spacing: CompactPopupLayout.gap) {
            Button(action: openSettings) {
                FooterModuleTile(width: 1, content: FooterTileContent(symbol: "gearshape", text: "", help: localization.string(.compactSettings)))
            }.buttonStyle(.plain)
            HStack(spacing: CompactPopupLayout.gap) {
                ForEach(layout.modules) { module in
                    Button { activate(module) } label: {
                        FooterModuleTile(width: module.width, content: content(module))
                    }.buttonStyle(.plain)
                }
            }
            .frame(width: CompactPopupLayout.span(8), height: CompactPopupLayout.unit, alignment: .leading)
            Button(action: quit) {
                FooterModuleTile(width: 1, content: FooterTileContent(symbol: "xmark.circle", text: "", help: localization.string(.compactQuit)))
            }.buttonStyle(.plain)
        }
    }
}

extension FooterModule {
    @MainActor func displayName(localization: Localization) -> String {
        if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return title }
        if !target.isEmpty {
            switch kind {
            case .application: return URL(fileURLWithPath: target).deletingPathExtension().lastPathComponent
            case .file, .folder: return URL(fileURLWithPath: target).lastPathComponent
            case .shortcut: return target
            default: break
            }
        }
        return localization.string(kind.labelKey)
    }
}
