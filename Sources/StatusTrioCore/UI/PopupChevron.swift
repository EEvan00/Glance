import SwiftUI

/// Compact horizontal arrows retain a larger hit area extending into the gaps.
struct PopupChevron: View {
    var symbol = "chevron.right"

    private var isHorizontal: Bool {
        symbol == "chevron.right" || symbol == "chevron.backward"
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: isHorizontal ? 12 : 28, height: 24)
            .contentShape(ChevronHitArea(expands: isHorizontal))
    }
}

private struct ChevronHitArea: Shape {
    let expands: Bool

    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX - (expands ? 4 : 0), y: rect.minY - (expands ? 2 : 0),
                    width: rect.width + (expands ? 8 : 0), height: rect.height + (expands ? 4 : 0)))
    }
}
