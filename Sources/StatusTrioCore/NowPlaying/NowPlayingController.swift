import AppKit
import Foundation
import Combine

@MainActor
final class NowPlayingController: ObservableObject {
    @Published private(set) var items: [NowPlayingItem] = []
    @Published private(set) var commandFailed = false
    private let stream = JSONLineProcess()
    private let command = JSONLineProcess()
    private var isVisible = false

    static func libraryURL() -> URL? {
        var candidates = [Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/libStatusTrioMediaBridge.dylib")]
        if let executable = Bundle.main.executableURL {
            candidates.append(executable.deletingLastPathComponent().appendingPathComponent("libStatusTrioMediaBridge.dylib"))
        }
        // SwiftPM executables and test bundles share the build products directory.
        candidates.append(Bundle.module.bundleURL.deletingLastPathComponent().appendingPathComponent("libStatusTrioMediaBridge.dylib"))
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func start(_ process: JSONLineProcess, mode: String, environment: [String: String]? = nil,
                       onLine: @escaping @MainActor (Data) -> Void,
                       onExit: @escaping @MainActor (Int32) -> Void) throws {
        guard let library = Self.libraryURL(),
              let script = Bundle.module.url(forResource: "status-trio-media", withExtension: "pl") else {
            throw CocoaError(.fileNoSuchFile)
        }
        try process.start(executable: URL(fileURLWithPath: "/usr/bin/perl"),
                          arguments: [script.path, library.path, mode], environment: environment,
                          timeout: mode == "command" ? 4 : nil, onLine: onLine, onExit: onExit)
    }

    func setVisible(_ visible: Bool) {
        isVisible = visible
        stream.stop()
        command.stop()
        items = []
        commandFailed = false
        guard visible else { return }
        do {
            try start(stream, mode: "stream", onLine: { [weak self] data in
                guard let self, self.isVisible else { return }
                self.items = NowPlayingItem.visible((try? JSONDecoder().decode([NowPlayingItem].self, from: data)) ?? [])
            }, onExit: { [weak self] _ in
                self?.items = []
                self?.stream.stop()
            })
        } catch { items = [] }
    }

    func openSource(_ item: NowPlayingItem) {
        guard isVisible, items.contains(where: { $0.id == item.id }),
              let pid = item.sourceProcessIdentifier, pid > 0,
              let bundle = item.sourceBundleIdentifier, !bundle.isEmpty,
              let application = NSRunningApplication(processIdentifier: pid),
              application.bundleIdentifier == bundle, !application.isTerminated else { return }
        application.activate(options: [])
    }

    func send(_ action: NowPlayingCommand, to item: NowPlayingItem, position: Double? = nil) {
        guard isVisible, items.contains(where: { $0.id == item.id }), !command.isRunning else { return }
        var environment = ProcessInfo.processInfo.environment
        environment["STATUS_TRIO_MEDIA_PATH"] = item.id
        environment["STATUS_TRIO_MEDIA_COMMAND"] = String(action.rawValue)
        if action == .seek {
            guard let position, position.isFinite, position >= 0, item.canSeek == true,
                  let duration = item.duration, duration.isFinite, duration > 0, position <= duration else { return }
            environment["STATUS_TRIO_MEDIA_POSITION"] = String(position)
        }
        commandFailed = false
        do {
            try start(command, mode: "command", environment: environment, onLine: { [weak self] data in
                let result = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                self?.commandFailed = result?["ok"] as? Bool != true
            }, onExit: { [weak self] status in
                if status != 0 { self?.commandFailed = true }
                self?.command.stop()
            })
        } catch { commandFailed = true }
    }
}
