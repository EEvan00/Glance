import SwiftUI

struct BrightnessControlsView: View {
    @ObservedObject var controller: BrightnessController
    var onOpenDisplay: (() -> Void)? = nil
    @EnvironmentObject private var localization: Localization
    @State private var isAdjusting = false
    @State private var value = 0.0

    var body: some View {
        if controller.value != nil {
            HStack(spacing: onOpenDisplay == nil ? 4 : CompactPopupLayout.gap / 2) {
                Image(systemName: "sun.max.fill").font(.system(size: CompactPopupLayout.moduleIconSize, weight: .medium)).frame(width: onOpenDisplay == nil ? 22 : CompactPopupLayout.unit, height: 24)
                    .padding(.trailing, onOpenDisplay == nil ? 0 : CompactPopupLayout.gap / 2)
                CapsuleSlider(value: $value, label: localization.string(.brightnessTitle), onChange: { scalar, final in
                    controller.setValue(scalar, final: final)
                }, onEditingChanged: { isAdjusting = $0 }) { EmptyView() }
                if let onOpenDisplay {
                    Button(action: onOpenDisplay) {
                        PopupChevron(alignsToModuleEdge: true)
                            .frame(width: CompactPopupLayout.unit + CompactPopupLayout.gap / 2, alignment: .trailing)
                    }
                        .buttonStyle(.plain).accessibilityLabel(localization.string(.displayTitle))
                }
            }
            .onAppear { value = controller.value ?? 0 }
            .onChange(of: controller.value) { _, scalar in if !isAdjusting { value = scalar ?? 0 } }
        }
    }
}
