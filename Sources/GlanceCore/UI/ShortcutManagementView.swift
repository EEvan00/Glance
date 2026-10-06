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

    static func editorURL(name: String) -> URL? {
        var url = URLComponents(string: "shortcuts://open-shortcut")
        url?.queryItems = [URLQueryItem(name: "name", value: name)]
        return url?.url
    }
}

struct ShortcutManagementView: View {
    enum Purpose { case missingOnly, installedOnly }
    struct Item: Identifiable {
        let name: String
        let addLabel: LocalizationKey
        let resource: URL?
        var id: String { name }
    }
    let items: [Item]
    var purpose: Purpose = .missingOnly
    @EnvironmentObject private var localization: Localization
    @StateObject private var controller = ShortcutInstallationController()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let installed = controller.installed {
                ForEach(items.filter { purpose == .installedOnly ? installed.contains($0.name) : !installed.contains($0.name) }) { item in
                    HStack {
                        Text(item.name).font(.caption).lineLimit(1)
                        Spacer()
                        if installed.contains(item.name) {
                            Button(localization.string(.shortcutManageRemove)) {
                                if let url = ShortcutInstallationController.editorURL(name: item.name) { NSWorkspace.shared.open(url) }
                            }
                        } else {
                            Button(localization.string(item.addLabel)) {
                                if let resource = item.resource { NSWorkspace.shared.open(resource) }
                            }
                        }
                    }
                }
                if purpose == .installedOnly, items.contains(where: { installed.contains($0.name) }) {
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
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in controller.refresh() }
    }
}
