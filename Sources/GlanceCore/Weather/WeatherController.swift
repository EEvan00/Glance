import Foundation
import Combine

@MainActor
final class WeatherController: ObservableObject {
    @Published private(set) var snapshot: WeatherSnapshot?
    @Published private(set) var updatedAt: Date?
    @Published private(set) var isUnavailable = false
    @Published private(set) var isLoading = false
    @Published private(set) var source: WeatherSource = .shortcuts
    @Published private(set) var nativeIssue: NativeWeatherIssue?
    @Published private(set) var attribution: NativeWeatherAttribution?
    private let connection = JSONLineProcess()
    private let executable: URL
    private let versions: WeatherShortcutVersions
    private let nativeProvider: NativeWeatherProvider
    // Teardown owns the task after the controller is no longer accessible.
    // Deinit only cancels it; normal reads/writes remain on the main actor.
    nonisolated(unsafe) private var nativeTask: Task<Void, Never>?
    private var nativeRequestID: UUID?
    private var shortcutName = ""
    private var lastAttempt: Date?
    private var visible = false
    // Exclusively main-actor owned while alive; deinit only removes this request's temporary file.
    nonisolated(unsafe) private var outputFile: URL?

    init(executable: URL = URL(fileURLWithPath: "/usr/bin/shortcuts"), versions: WeatherShortcutVersions? = nil,
         nativeProvider: NativeWeatherProvider? = nil) {
        self.executable = executable
        self.versions = versions ?? .shared
        self.nativeProvider = nativeProvider ?? .shared
    }

    func configure(source: WeatherSource) {
        guard self.source != source else { return }
        stopRequest()
        self.source = source
        snapshot = nil; updatedAt = nil; lastAttempt = nil; isUnavailable = false
        nativeIssue = nil; attribution = nil
        if visible { setVisible(true, shortcutName: shortcutName) }
    }

    static func shouldRefresh(shortcutName: String, lastAttempt: Date?, now: Date) -> Bool {
        !shortcutName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (lastAttempt.map { now.timeIntervalSince($0) >= 900 } ?? true)
    }

    func setVisible(_ visible: Bool, shortcutName rawName: String) {
        self.visible = visible
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        if source == .nativeWeather {
            shortcutName = name
            guard visible else { stopRequest(); return }
            guard !isLoading else { return }
            startNativeRequest(forceRefresh: false)
            return
        }
        if shortcutName != name {
            stopRequest()
            shortcutName = name; snapshot = nil; updatedAt = nil; lastAttempt = nil; isUnavailable = false
        }
        guard visible else {
            if isLoading { lastAttempt = nil }
            stopRequest()
            return
        }
        guard !isLoading, (versions.pendingVerification.contains(shortcutName) || Self.shouldRefresh(shortcutName: shortcutName, lastAttempt: lastAttempt, now: Date())) else { return }
        lastAttempt = Date()
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("glance-weather-\(UUID().uuidString).txt")
        outputFile = file
        isLoading = true
        do {
            try connection.start(executable: executable, arguments: ["run", shortcutName, "--output-type", "public.plain-text", "--output-path", file.path], timeout: 20, keepsInputOpen: false,
                onLine: { _ in }, onExit: { [weak self] status in
                    guard let self, self.visible, self.outputFile == file else { return }
                    defer { self.stopRequest() }
                    guard status == 0,
                          let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
                          let size = attributes[.size] as? NSNumber, size.intValue <= 4096,
                          let data = try? Data(contentsOf: file),
                          let text = String(data: data, encoding: .utf8),
                          let snapshot = WeatherSnapshot.fromShortcut(text) else {
                        self.snapshot = nil; self.updatedAt = nil; self.lastAttempt = nil; self.isUnavailable = true
                        return
                    }
                    self.versions.record(name: self.shortcutName, version: snapshot.shortcutVersion)
                    self.snapshot = snapshot
                    self.updatedAt = Date()
                    self.isUnavailable = false
                })
        } catch {
            stopRequest(); snapshot = nil; updatedAt = nil; lastAttempt = nil; isUnavailable = true
        }
    }

    func refreshNow(shortcutName: String) {
        guard visible, !isLoading else { return }
        if source == .nativeWeather { startNativeRequest(forceRefresh: true); return }
        lastAttempt = nil
        setVisible(true, shortcutName: shortcutName)
    }

    private func stopRequest() {
        nativeRequestID = nil
        nativeTask?.cancel()
        nativeTask = nil
        connection.stop()
        isLoading = false
        if let file = outputFile {
            try? FileManager.default.removeItem(at: file)
            // The owned child is forcibly stopped within 0.5s; cover an atomic write racing cancellation.
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
                try? FileManager.default.removeItem(at: file)
            }
        }
        outputFile = nil
    }

    private func startNativeRequest(forceRefresh: Bool) {
        let id = UUID()
        nativeRequestID = id
        isLoading = true
        nativeTask = Task { [weak self, nativeProvider] in
            do {
                let response = try await nativeProvider.fetch(forceRefresh: forceRefresh)
                guard !Task.isCancelled, let self, self.visible, self.nativeRequestID == id else { return }
                self.snapshot = response.snapshot
                self.updatedAt = response.updatedAt
                self.attribution = response.attribution
                self.nativeIssue = nil
                self.isUnavailable = false
                self.isLoading = false
                self.nativeTask = nil
                self.nativeRequestID = nil
            } catch {
                guard !Task.isCancelled, let self, self.visible, self.nativeRequestID == id else { return }
                self.snapshot = nil
                self.updatedAt = nil
                self.attribution = nil
                self.nativeIssue = error as? NativeWeatherIssue ?? .serviceUnavailable
                self.isUnavailable = true
                self.isLoading = false
                self.nativeTask = nil
                self.nativeRequestID = nil
            }
        }
    }

    deinit {
        nativeTask?.cancel()
        if let outputFile { try? FileManager.default.removeItem(at: outputFile) }
    }
}
