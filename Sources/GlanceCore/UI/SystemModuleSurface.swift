import SwiftUI

enum CompactPopupLayout {
    static let unit: CGFloat = 24
    static let singlePlaybackControlSpacing: CGFloat = 6
    static var singlePlaybackPreviousLeading: CGFloat {
        (span(10) - (unit * 3 + singlePlaybackControlSpacing * 2)) / 2
    }
    static let moduleIconSize: CGFloat = 14
    static let gap: CGFloat = 4
    static func span(_ count: Int) -> CGFloat { unit * CGFloat(count) + gap * CGFloat(max(0, count - 1)) }
    static var cardRowHeight: CGFloat { (span(3) - borderWidth) / 2 }
    static let contentInset: CGFloat = 8
    static let moduleTextInset: CGFloat = 6
    static let borderWidth: CGFloat = 0.7
}

extension View {
    /// The panel adds four points below this row, matching its eight-point top inset.
    func popupFooterInsets() -> some View {
        padding(.top, CompactPopupLayout.contentInset)
            .padding(.bottom, CompactPopupLayout.gap)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    func popupBottomShadow(isEnabled: Bool = true) -> some View {
        shadow(color: .black.opacity(isEnabled ? 0.14 : 0), radius: 3, y: 2)
    }

    func systemModuleSurface(cornerRadius: CGFloat = 8) -> some View {
        modifier(SystemModuleSurface(cornerRadius: cornerRadius))
    }
}

private struct SystemModuleSurface: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    private var borderColors: [Color] {
        colorScheme == .dark
            ? [.white.opacity(0.22), .white.opacity(0.04)]
            : [.black.opacity(0.16), .black.opacity(0.08)]
    }

    func body(content: Content) -> some View {
        content
            .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: cornerRadius, style: .circular))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .circular)
                    .strokeBorder(LinearGradient(colors: borderColors, startPoint: .top, endPoint: .bottom), lineWidth: CompactPopupLayout.borderWidth)
                    .allowsHitTesting(false)
            }
            .popupBottomShadow()
    }
}

struct PopupDivider: View {
    var body: some View {
        Rectangle()
            .fill(.primary.opacity(0.30))
            .frame(height: CompactPopupLayout.borderWidth)
            .accessibilityHidden(true)
    }
}
