import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct QuickActionSettingsView: View {
    @ObservedObject var store: SettingsStore
    @EnvironmentObject private var localization: Localization
    @StateObject private var shortcuts = ShortcutInstallationController()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            actionPicker(.quickFirstSlot, selection: $store.firstQuickAction, other: store.secondQuickAction)
            actionPicker(.quickSecondSlot, selection: $store.secondQuickAction, other: store.firstQuickAction)
            if contains(.application) {
                PreferenceRow(label: .quickApplication, placesControlInline: true) {
                    Button {
                        let panel = NSOpenPanel()
                        panel.allowedContentTypes = [.applicationBundle]
                        panel.allowsMultipleSelection = false
                        panel.canChooseDirectories = false
                        panel.directoryURL = URL(fileURLWithPath: "/Applications")
                        panel.begin { response in
                            if response == .OK, let url = panel.url { store.quickActionApplicationPath = url.path }
                        }
                    } label: {
                        Text(store.quickActionApplicationPath.isEmpty
                             ? localization.string(.quickChooseApplication)
                             : URL(fileURLWithPath: store.quickActionApplicationPath).deletingPathExtension().lastPathComponent)
                            .lineLimit(1).truncationMode(.middle)
                    }.frame(maxWidth: 220)
                }
            }
            if contains(.shortcut) {
                PreferenceRow(label: .quickShortcut) {
                    HStack {
                        Picker(localization.string(.quickShortcut), selection: $store.quickActionShortcutName) {
                            Text(localization.string(.quickChooseShortcut)).tag("")
                            ForEach(shortcutNames, id: \.self) { Text($0).tag($0) }
                        }.labelsHidden()
                        Button { shortcuts.refresh() } label: { Image(systemName: "arrow.clockwise") }
                            .help(localization.string(.codexRefreshNow)).disabled(shortcuts.isLoading)
                    }
                    if shortcuts.isLoading { ProgressView().controlSize(.small) }
                    if shortcuts.failed {
                        Text(localization.string(.shortcutDiscoveryFailed)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if contains(.screenshot) {
                Text(localization.string(.settingsScreenshotSystemHelp)).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { if contains(.shortcut) { shortcuts.refresh() } }
        .onChange(of: store.firstQuickAction) { _, _ in if contains(.shortcut) { shortcuts.refresh() } }
        .onChange(of: store.secondQuickAction) { _, _ in if contains(.shortcut) { shortcuts.refresh() } }
        .onDisappear { shortcuts.stop() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if contains(.shortcut) { shortcuts.refresh() }
        }
    }
    private func contains(_ action: PopupQuickAction) -> Bool {
        store.firstQuickAction == action || store.secondQuickAction == action
    }
    private var shortcutNames: [String] {
        var names = shortcuts.installed ?? []
        if !store.quickActionShortcutName.isEmpty { names.insert(store.quickActionShortcutName) }
        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    private func actionPicker(_ key: LocalizationKey, selection: Binding<PopupQuickAction>, other: PopupQuickAction) -> some View {
        PreferenceRow(label: key, placesControlInline: true) {
            Picker(localization.string(key), selection: selection) {
                ForEach(PopupQuickAction.allCases.filter { $0 != other }) { action in
                    Text(localization.string(action.labelKey)).tag(action)
                }
            }.labelsHidden().frame(width: 220)
        }
    }
}
