import SwiftUI

struct FooterModulesSettingsPane: View {
    @ObservedObject var store: SettingsStore
    var snapshot: StatusSnapshot = .placeholder
    @EnvironmentObject private var localization: Localization
    @State private var selection: UUID?
    @State private var query = ""
    @State private var undoLayout: FooterLayout?
    @State private var dropTarget: String?
    @State private var configurationScrollRequest = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            editorHeader
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)
            Divider()
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 16) {
                        configuration
                            .id("footer-configuration")
                        if selection != nil { Divider() }
                        HStack {
                            Text(localization.string(.footerLibrary)).font(.headline)
                            Spacer()
                            TextField(localization.string(.footerSearch), text: $query)
                                .textFieldStyle(.roundedBorder).frame(width: 175)
                        }
                        ForEach(FooterModuleCategory.allCases) { category in
                            let kinds = matchingKinds(category)
                            if !kinds.isEmpty {
                                Text(localization.string(category.titleKey)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                VStack(spacing: 8) {
                                    ForEach(kinds) { kind in libraryRow(kind) }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .onChange(of: configurationScrollRequest) { _, _ in
                    proxy.scrollTo("footer-configuration", anchor: .top)
                }
            }
        }
        .frame(width: SettingsTabViewController.contentWidth,
               height: SettingsTabViewController.maximumContentHeight,
               alignment: .topLeading)
    }

    private var editorHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(localization.string(.footerModulesTitle)).font(.headline)
                Spacer()
                Text(localization.format(.footerUsage, store.footerLayout.usedSlots))
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            preview.frame(maxWidth: .infinity).padding(.vertical, 8)
            HStack {
                Button(localization.string(.footerClear)) { replace(FooterLayout(modules: [])); selection = nil }
                    .disabled(store.footerLayout.modules.isEmpty)
                Button(localization.string(.footerRestore)) { replace(.defaultLayout); selection = nil }
                Spacer()
                Button(localization.string(.footerUndo)) {
                    guard let previous = undoLayout else { return }
                    store.footerLayout = previous
                    undoLayout = nil
                    reconcileSelection()
                }.disabled(undoLayout == nil)
            }.controlSize(.small)
        }
    }

    @ViewBuilder
    private var configuration: some View {
        if let module = store.footerLayout.modules.first(where: { $0.id == selection }),
           let index = store.footerLayout.modules.firstIndex(where: { $0.id == module.id }) {
            FooterModuleConfigurationView(store: store, module: module, remainingSlots: store.footerLayout.remainingSlots,
                canMoveLeft: index > 0, canMoveRight: index < store.footerLayout.modules.count - 1,
                update: { changed in edit { $0.update(changed) } },
                resize: { width in edit { $0.resize(id: module.id, width: width) } },
                move: { offset in edit { $0.move(id: module.id, to: index + offset) } },
                remove: { edit { $0.remove(id: module.id) }; selection = nil })
                .id(module.id)
        }
    }

    private var preview: some View {
        HStack(spacing: CompactPopupLayout.gap) {
            fixedTile("gearshape", key: .compactSettings)
            HStack(spacing: CompactPopupLayout.gap) {
                ForEach(store.footerLayout.modules) { module in
                    FooterModuleTile(width: module.width, content: previewContent(module))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(selection == module.id ? Color.accentColor : .clear, lineWidth: 2)
                            }
                            .overlay {
                                if dropTarget == module.id.uuidString {
                                    RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [3]))
                                }
                            }
                    // Keep drag initiation on the tile rather than a Button's
                    // mouse tracking. A completed click still selects the module.
                    .contentShape(Rectangle())
                    .onTapGesture { select(module.id) }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { select(module.id) }
                    .draggable("module:\(module.id)")
                    .dropDestination(for: String.self) { items, _ in
                        drop(items, onto: module.id)
                    } isTargeted: { targeted in
                        dropTarget = targeted ? module.id.uuidString : nil
                    }
                }
                ForEach(0..<store.footerLayout.remainingSlots, id: \.self) { slot in
                    emptySlot(slot)
                }
            }
            .frame(width: CompactPopupLayout.span(8), height: CompactPopupLayout.unit, alignment: .leading)
            fixedTile("xmark.circle", key: .compactQuit)
        }
    }

    private func emptySlot(_ slot: Int) -> some View {
        FooterSlotMenu(
            groups: FooterModuleCategory.allCases.map { category in
                FooterSlotMenu.Group(title: localization.string(category.titleKey),
                    items: FooterModuleKind.allCases.filter { $0.category == category }.map { kind in
                        FooterSlotMenu.Item(kind: kind, title: localization.string(kind.labelKey),
                                            enabled: canAdd(kind, width: 1))
                    })
            },
            label: localization.string(.footerAdd),
            targeted: dropTarget == "empty-\(slot)",
            select: { add($0, width: 1) })
        .frame(width: CompactPopupLayout.unit, height: CompactPopupLayout.unit)
        .help(localization.string(.footerAdd))
        .accessibilityLabel(localization.string(.footerAdd))
        .dropDestination(for: String.self) { items, _ in drop(items, onto: nil) } isTargeted: { targeted in
            dropTarget = targeted ? "empty-\(slot)" : nil
        }
    }

    private func fixedTile(_ symbol: String, key: LocalizationKey) -> some View {
        FooterModuleTile(width: 1, content: FooterTileContent(symbol: symbol, text: "",
            help: localization.string(key) + " · " + localization.string(.footerFixed)))
            .opacity(0.55)
    }

    private func previewContent(_ module: FooterModule) -> FooterTileContent {
        let name = module.displayName(localization: localization)
        var content = FooterTileContent(symbol: module.kind.symbol, text: name, help: name)
        content.kind = module.kind
        if module.kind == .date {
            content.text = FooterClockFormatting.date(Date(), locale: localization.resolvedLanguage.locale, chinese: localization.resolvedLanguage.isChinese)
            content.textOnly = true
            content.help = FooterClockFormatting.detailedDate(Date(), locale: localization.resolvedLanguage.locale)
        } else if module.kind == .clock {
            content.text = FooterClockFormatting.time(Date(), uses24HourClock: store.uses24HourClock, showsSeconds: store.showsClockSeconds)
            content.textOnly = true
            content.help = content.text
        } else if module.kind == .weather {
            content.symbol = "cloud"
            content.text = "—"
        } else if module.kind == .battery {
            content.symbol = snapshot.battery.isChargingPaused ? "powerplug.portrait.fill" : "battery.100"
            content.text = snapshot.battery.rawPercentage.map { _ in "\(snapshot.battery.percentage)%" } ?? "—"
        } else if module.kind == .wifi {
            content.wifi = snapshot.wifi
        }
        return content
    }

    private func libraryRow(_ kind: FooterModuleKind) -> some View {
        HStack(spacing: 8) {
            FooterModuleIcon(kind: kind, symbol: kind.symbol).frame(width: 20).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(localization.string(kind.labelKey)).lineLimit(1)
                Text(localization.string(kind.descriptionKey))
                    .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if !FooterActionController.isSystemActionAvailable(kind) {
                    Text(localization.string(.footerUnavailable)).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            ForEach(1...2, id: \.self) { width in
                Button {
                    add(kind, width: width)
                } label: {
                    Label(localization.string(width == 1 ? .footerOneSlot : .footerTwoSlots), systemImage: "plus")
                }
                .disabled(!canAdd(kind, width: width))
                .accessibilityLabel(localization.string(.footerAdd) + " " + localization.string(kind.labelKey) + " " + localization.string(width == 1 ? .footerOneSlot : .footerTwoSlots))
            }
        }
        .font(.system(size: 12)).controlSize(.small)
        .padding(8).background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 8))
        .draggable("kind:\(kind.rawValue)")
    }

    private func select(_ id: UUID) {
        selection = id
        configurationScrollRequest += 1
    }

    private func add(_ kind: FooterModuleKind, width: Int) {
        guard canAdd(kind, width: width) else { return }
        let module = FooterModule(kind: kind, width: width)
        edit { $0.add(module) }
        select(module.id)
    }

    private func canAdd(_ kind: FooterModuleKind, width: Int) -> Bool {
        FooterActionController.isSystemActionAvailable(kind) && store.footerLayout.remainingSlots >= width && (kind.allowsMultipleInstances || !store.footerLayout.modules.contains { $0.kind == kind })
    }

    private func matchingKinds(_ category: FooterModuleCategory) -> [FooterModuleKind] {
        FooterModuleKind.allCases.filter {
            $0.category == category && (query.isEmpty || localization.string($0.labelKey).localizedCaseInsensitiveContains(query))
        }
    }

    private func replace(_ layout: FooterLayout) {
        guard store.footerLayout != layout else { return }
        undoLayout = store.footerLayout
        store.footerLayout = layout
    }

    private func edit(_ change: (inout FooterLayout) -> Bool) {
        var layout = store.footerLayout
        if change(&layout) { replace(layout) }
    }

    private func drop(_ items: [String], onto id: UUID?) -> Bool {
        guard items.count == 1, let payload = items.first else { return false }
        var layout = store.footerLayout
        let oldIDs = Set(layout.modules.map(\.id))
        guard FooterEditorDrop.apply(payload, onto: id, to: &layout) else { return false }
        if let added = layout.modules.first(where: { !oldIDs.contains($0.id) }) {
            guard FooterActionController.isSystemActionAvailable(added.kind) else { return false }
            select(added.id)
        }
        replace(layout)
        dropTarget = nil
        reconcileSelection()
        return true
    }

    private func reconcileSelection() {
        if !store.footerLayout.modules.contains(where: { $0.id == selection }) { selection = nil }
    }
}
