import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct FooterModuleConfigurationView: View {
    @ObservedObject var store: SettingsStore
    let module: FooterModule
    let remainingSlots: Int
    let canMoveLeft: Bool
    let canMoveRight: Bool
    let update: (FooterModule) -> Void
    let resize: (Int) -> Void
    let move: (Int) -> Void
    let remove: () -> Void
    @EnvironmentObject private var localization: Localization
    @StateObject private var shortcuts = ShortcutInstallationController()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Menu {
                    ForEach(FooterModuleCategory.allCases) { category in
                        Menu(localization.string(category.titleKey)) {
                            ForEach(FooterModuleKind.allCases.filter { $0.category == category }) { kind in
                                Button(localization.string(kind.labelKey)) {
                                    update(replacement(kind))
                                }
                                .disabled(kind == module.kind || !canReplace(with: kind))
                            }
                        }
                    }
                } label: {
                    Label {
                        Text(module.displayName(localization: localization)).font(.headline).lineLimit(1)
                    } icon: {
                        FooterModuleIcon(kind: module.kind, symbol: module.kind.symbol)
                    }
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.visible)
                .fixedSize()
                Spacer()
                Button { move(-1) } label: { Image(systemName: "arrow.left") }
                    .help(localization.string(.footerMoveLeft)).accessibilityLabel(localization.string(.footerMoveLeft))
                    .disabled(!canMoveLeft)
                Button { move(1) } label: { Image(systemName: "arrow.right") }
                    .help(localization.string(.footerMoveRight)).accessibilityLabel(localization.string(.footerMoveRight))
                    .disabled(!canMoveRight)
                Button(role: .destructive, action: remove) { Image(systemName: "trash") }
                    .help(localization.string(.footerRemove)).accessibilityLabel(localization.string(.footerRemove))
            }
            Text(localization.string(module.kind.descriptionKey)).font(.caption).foregroundStyle(.secondary)
            HStack {
                Text(localization.string(.footerSize))
                Spacer()
                ForEach(1...2, id: \.self) { width in
                    Button {
                        resize(width)
                    } label: {
                        VStack(spacing: 5) {
                            FooterModuleTile(width: width, content: FooterTileContent(symbol: module.kind.symbol,
                                text: module.displayName(localization: localization), help: module.displayName(localization: localization), kind: module.kind))
                            Label(localization.string(width == 1 ? .footerOneSlot : .footerTwoSlots),
                                  systemImage: module.width == width ? "checkmark.circle.fill" : "circle")
                        }
                    }
                    .disabled(width > module.width && remainingSlots == 0)
                }
            }
            if module.kind == .clock || module.kind == .weather {
                Divider()
                FooterModulePreferencesView(kind: module.kind, store: store)
            }
            if module.kind.allowsMultipleInstances {
                LabeledContent(localization.string(.footerName)) {
                    TextField(localization.string(module.kind.labelKey), text: valueBinding(\.title))
                        .textFieldStyle(.roundedBorder)
                }
                targetEditor
            }
        }
        .controlSize(.small)
        .padding(12)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
        .onAppear { if module.kind == .shortcut { shortcuts.refresh() } }
        .onChange(of: module.kind) { _, kind in
            shortcuts.stop()
            if kind == .shortcut { shortcuts.refresh() }
        }
        .onDisappear { shortcuts.stop() }
    }

    private func replacement(_ kind: FooterModuleKind) -> FooterModule {
        FooterModule(id: module.id, kind: kind, width: module.width)
    }

    private func canReplace(with kind: FooterModuleKind) -> Bool {
        guard FooterActionController.isSystemActionAvailable(kind) else { return false }
        var layout = store.footerLayout
        return layout.update(replacement(kind))
    }

    @ViewBuilder private var targetEditor: some View {
        if module.kind == .shortcut {
            LabeledContent(localization.string(.quickShortcut)) {
                HStack {
                    Picker(localization.string(.quickChooseShortcut), selection: valueBinding(\.target)) {
                        Text(localization.string(.quickChooseShortcut)).tag("")
                        ForEach(shortcutNames, id: \.self) { name in Text(name).tag(name) }
                    }.labelsHidden()
                    Button { shortcuts.refresh() } label: { Image(systemName: "arrow.clockwise") }
                        .help(localization.string(.codexRefreshNow))
                        .accessibilityLabel(localization.string(.codexRefreshNow)).disabled(shortcuts.isLoading)
                }
            }
            if shortcuts.isLoading { ProgressView().controlSize(.small) }
            if shortcuts.failed {
                Text(localization.string(.shortcutDiscoveryFailed)).font(.caption).foregroundStyle(.secondary)
            }
        } else {
            LabeledContent(localization.string(.footerTarget)) {
                HStack {
                    TextField(module.kind == .website ? "https://example.com" : localization.string(.footerChoose),
                              text: valueBinding(\.target))
                        .textFieldStyle(.roundedBorder)
                    if module.kind != .website {
                        Button(localization.string(.footerChoose)) { chooseTarget() }
                    }
                }
            }
        }
    }

    private var shortcutNames: [String] {
        var names = shortcuts.installed ?? []
        if !module.target.isEmpty { names.insert(module.target) }
        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func valueBinding(_ keyPath: WritableKeyPath<FooterModule, String>) -> Binding<String> {
        Binding(get: { module[keyPath: keyPath] }, set: { value in
            var changed = module
            changed[keyPath: keyPath] = value
            update(changed)
        })
    }

    private func chooseTarget() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = module.kind == .folder
        panel.canChooseFiles = module.kind != .folder
        if module.kind == .application {
            panel.allowedContentTypes = [.applicationBundle]
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
        }
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            var changed = module
            changed.target = url.path
            update(changed)
        }
    }
}
