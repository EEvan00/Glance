import SwiftUI

struct CompactVolumeControlsView: View {
    @ObservedObject var store: SystemStatusStore
    @EnvironmentObject private var localization: Localization
    var onOpenOutput: (() -> Void)? = nil
    @State private var value = 0.0
    @State private var isAdjusting = false
    @State private var lastWrite = Date.distantPast

    var body: some View {
        HStack(spacing: onOpenOutput == nil ? 4 : CompactPopupLayout.gap / 2) {
            Button { store.toggleMute() } label: {
                Image(systemName: store.liveVolume.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: CompactPopupLayout.moduleIconSize, weight: .medium)).frame(width: onOpenOutput == nil ? 22 : CompactPopupLayout.unit, height: 24)
                    .padding(.trailing, onOpenOutput == nil ? 0 : CompactPopupLayout.gap / 2)
                    .offset(x: onOpenOutput == nil ? 0 : 1)
            }
            .buttonStyle(.plain).disabled(!store.isVolumeControlAvailable)
            .accessibilityLabel(localization.string(store.liveVolume.isMuted ? .volumeUnmuted : .volumeMuted))
            CapsuleSlider(value: $value, label: localization.string(.volumeAccessibilityLabel),
                          isEnabled: store.isVolumeControlAvailable, onChange: { scalar, final in
                let now = Date()
                if final || now.timeIntervalSince(lastWrite) >= 1.0 / 30 {
                    lastWrite = now
                    store.setVolume(scalar)
                }
            }, onEditingChanged: { isAdjusting = $0 }) {
                EmptyView()
            }
            .contextMenu {
                if let onOpenOutput { Button(localization.string(.volumeOutputTitle), action: onOpenOutput) }
                Button(localization.string(store.liveVolume.isMuted ? .volumeUnmuted : .volumeMuted)) { store.toggleMute() }
            }
            .accessibilityAction(named: Text(localization.string(store.liveVolume.isMuted ? .volumeUnmuted : .volumeMuted))) { store.toggleMute() }
            if let onOpenOutput {
                Button(action: onOpenOutput) {
                        PopupChevron(alignsToModuleEdge: true)
                            .frame(width: CompactPopupLayout.unit + CompactPopupLayout.gap / 2, alignment: .trailing)
                    }
                    .buttonStyle(.plain).accessibilityLabel(localization.string(.volumeOutputTitle))
            }
        }
        .onAppear { value = store.liveVolume.scalar ?? 0 }
        .onChange(of: store.liveVolume.scalar) { _, scalar in if !isAdjusting { value = scalar ?? 0 } }
    }
}
