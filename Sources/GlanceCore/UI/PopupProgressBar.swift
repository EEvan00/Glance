import SwiftUI

enum PopupTrackStyle {
    static func color(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.12)
    }
}

struct PopupProgressBar: View {
    @Environment(\.colorScheme) private var colorScheme
    static let fillColor = Color.white.opacity(0.88)
    let percent: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(PopupTrackStyle.color(for: colorScheme))
                Capsule().fill(Self.fillColor)
                    .frame(width: geometry.size.width * CGFloat(min(max(percent, 0), 100)) / 100)
            }
        }.frame(height: 6)
    }
}
