import SwiftUI

/// Uses the same artwork and network renderer as the popup's existing cards.
struct FooterModuleIcon: View {
    let kind: FooterModuleKind?
    let symbol: String
    var wifi: WiFiStatus? = nil

    var body: some View {
        Group {
            switch kind {
            case .bluetooth:
                if let image = NSImage(named: NSImage.bluetoothTemplateName) {
                    Image(nsImage: image).resizable().scaledToFit().frame(width: 14, height: 18)
                } else {
                    Image(systemName: symbol)
                }
            case .codex:
                UsageProviderIcon(provider: .codex, tint: .primary)
            case .claude:
                UsageProviderIcon(provider: .claude, tint: .primary)
            case .wifi:
                if let wifi {
                    Image(nsImage: StatusIconRenderer.popupWiFiImage(wifi: wifi, size: 18))
                        .renderingMode(.template)
                } else {
                    Image(systemName: "wifi")
                }
            default:
                Image(systemName: symbol)
            }
        }
        .font(.system(size: CompactPopupLayout.moduleIconSize, weight: .medium))
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }
}
