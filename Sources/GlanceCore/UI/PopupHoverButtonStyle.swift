import SwiftUI

/// Shared pointer feedback for buttons in the status popup.
struct PopupHoverButtonStyle: ButtonStyle {
    var fullWidth = false
    func makeBody(configuration: Configuration) -> some View {
        PopupHoverButton(configuration: configuration, fullWidth: fullWidth)
    }
}

private struct PopupHoverButton: View {
    let configuration: ButtonStyleConfiguration
    let fullWidth: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .frame(maxWidth: fullWidth ? .infinity : nil, alignment: .leading)
            .foregroundStyle(.primary)
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(isEnabled && (isHovered || configuration.isPressed) ? 0.12 : 0))
                    .padding(.horizontal, -4)
                    .padding(.vertical, -3)
                    .allowsHitTesting(false)
            }
            .onHover { isHovered = $0 }
    }
}
