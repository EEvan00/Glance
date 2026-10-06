import SwiftUI

/// Compact horizontal arrows retain a larger hit area extending into the gaps.
struct PopupChevron: View {
    var symbol = "chevron.right"
    var alignsToModuleEdge = false
    var fitsSymbolWidth = false

    private var isHorizontal: Bool {
        symbol == "chevron.right" || symbol == "chevron.backward"
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: alignsToModuleEdge ? 12 : 11, weight: alignsToModuleEdge ? .medium : .semibold))
            .foregroundStyle(.secondary)
            .frame(width: isHorizontal ? (fitsSymbolWidth ? nil : (alignsToModuleEdge ? CompactPopupLayout.unit : 12)) : 28,
                   height: 24, alignment: alignsToModuleEdge ? .trailing : .center)
            .padding(.trailing, alignsToModuleEdge ? CompactPopupLayout.moduleTextInset : 0)
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
