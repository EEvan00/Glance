import AppKit
import Combine
import SwiftUI

@MainActor
final class ShortcutInstallationController: ObservableObject {
    @Published private(set) var installed: Set<String>?
    @Published private(set) var isLoading = false
    @Published private(set) var failed = false
    private let process = JSONLineProcess()
    private let executable: URL
    init(executable: URL = URL(fileURLWithPath: "/usr/bin/shortcuts")) { self.executable = executable }

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        var names: Set<String> = []
        do {
            try process.start(executable: executable, arguments: ["list"], timeout: 15, keepsInputOpen: false,
                onLine: { data in
                    if let name = String(data: data, encoding: .utf8) { names.insert(name.trimmingCharacters(in: .whitespacesAndNewlines)) }
                }, onExit: { [weak self] status in
                    guard let self else { return }
                    self.isLoading = false
                    self.failed = status != 0
                    self.installed = status == 0 ? names : nil
                })
        } catch { isLoading = false; failed = true; installed = nil }
    }

    func stop() { process.stop(); isLoading = false }
}

struct ShortcutManagementView: View {
    enum Purpose { case missingOnly, settings }
    struct Item: Identifiable {
        let name: String
        let addLabel: LocalizationKey
        let resource: URL?
        var version: Int = 1
        var id: String { name }
    }
    let items: [Item]
    var purpose: Purpose = .missingOnly
    @EnvironmentObject private var localization: Localization
    @ObservedObject private var installation = WeatherShortcutInstallFlow.shared
    @ObservedObject private var versions = WeatherShortcutVersions.shared
    @StateObject private var controller = ShortcutInstallationController()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let installed = controller.installed {
                let missing = items.filter { !installed.contains($0.name) }
                if !missing.isEmpty {
                    let next = installation.pending.first(where: { pending in missing.contains { $0.name == pending.rawValue } })?.rawValue ?? missing[0].name
                    Text(next).font(.caption).lineLimit(1)
                    Button(localization.string(installation.isInProgress ? .shortcutContinueSetup : .shortcutAddWeather)) {
                        if let next = installation.nextToOpen(installed: installed),
                           let resource = items.first(where: { $0.name == next.rawValue })?.resource {
                            versions.requestVerification(name: next.rawValue)
                            NSWorkspace.shared.open(resource)
                        }
                    }
                    Text(localization.string(.shortcutSequentialInstallHelp))
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(items.filter { installed.contains($0.name) &&
                    (purpose == .settings || versions.needsUpdate(name: $0.name, bundledVersion: $0.version)) }) { item in
                    HStack {
                        Text(item.name).font(.caption).lineLimit(1)
                        Spacer()
                        if purpose == .settings {
                            Button(localization.string(.shortcutManageRemove)) {
                                if let url = URL(string: "shortcuts://") { NSWorkspace.shared.open(url) }
                            }
                        } else {
                            Button(localization.string(.shortcutUpdate)) {
                                if let resource = item.resource {
                                    versions.requestVerification(name: item.name)
                                    NSWorkspace.shared.open(resource)
                                }
                            }
                        }
                    }
                }
                if purpose == .missingOnly, items.contains(where: {
                    installed.contains($0.name) && versions.needsUpdate(name: $0.name, bundledVersion: $0.version)
                }) {
                    Text(localization.string(.shortcutUpdateHelp)).font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if purpose == .settings, items.contains(where: { installed.contains($0.name) }) {
                    Text(localization.string(.shortcutRemoveHelp)).font(.caption2).foregroundStyle(.secondary).lineLimit(nil).fixedSize(horizontal: false, vertical: true)
                }
            } else if controller.failed {
                HStack {
                    Text(localization.string(.shortcutDiscoveryFailed)).font(.caption).foregroundStyle(.secondary).lineLimit(nil).fixedSize(horizontal: false, vertical: true)
                    Button { controller.refresh() } label: { Image(systemName: "arrow.clockwise") }
                        .accessibilityLabel(localization.string(.codexRefreshNow))
                }
            } else { ProgressView().controlSize(.small) }
        }.buttonStyle(.bordered).controlSize(.small)
            .onAppear { controller.refresh() }
            .onDisappear { controller.stop() }
            .onChange(of: controller.installed) { _, installed in
                if let installed { installation.reconcile(installed: installed) }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in controller.refresh() }
    }
}
