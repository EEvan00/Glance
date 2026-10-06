import SwiftUI

struct PopupProgressBar: View {
    static let trackColor = Color.white.opacity(0.18)
    static let fillColor = Color.white.opacity(0.88)
    let percent: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Self.trackColor)
                Capsule().fill(Self.fillColor)
                    .frame(width: geometry.size.width * CGFloat(min(max(percent, 0), 100)) / 100)
            }
        }.frame(height: 6)
    }
}
