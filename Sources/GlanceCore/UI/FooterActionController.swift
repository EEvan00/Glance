import AppKit
import Combine
import Darwin
import IOKit.pwr_mgt

/// Targets stay typed; arbitrary schemes and relative paths never reach Workspace.
enum FooterActionTarget {
    enum Failure: Error { case website, application, file, folder, shortcut }

    static func url(kind: FooterModuleKind, target: String) throws -> URL {
        switch kind {
        case .website:
            guard let components = URLComponents(string: target.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
                  let host = components.host, !host.isEmpty, !host.contains(where: { $0.isWhitespace }),
                  let url = components.url else { throw Failure.website }
            return url
        case .shortcut:
            let name = target.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { throw Failure.shortcut }
            var components = URLComponents()
            components.scheme = "shortcuts"
            components.host = "run-shortcut"
            components.queryItems = [URLQueryItem(name: "name", value: name)]
            guard let url = components.url else { throw Failure.shortcut }
            return url
        case .application, .file, .folder:
            let failure: Failure = kind == .application ? .application : (kind == .folder ? .folder : .file)
            let path = NSString(string: target).expandingTildeInPath
            guard path.hasPrefix("/") else { throw failure }
            let url = URL(fileURLWithPath: path).standardizedFileURL
            var directory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) else { throw failure }
            if kind == .application {
                guard directory.boolValue, url.pathExtension.lowercased() == "app",
                      let bundle = Bundle(url: url), bundle.executableURL != nil else { throw failure }
            } else if directory.boolValue != (kind == .folder) { throw failure }
            return url
        default:
            throw Failure.file
        }
    }
}

struct FooterActionEffects {
    var open: (URL) -> Bool
    var acquire: () -> UInt32?
    var release: (UInt32) -> Bool

    @MainActor static var live: Self {
        Self(open: { NSWorkspace.shared.open($0) }, acquire: {
            var id: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName(kIOPMAssertionTypeNoIdleSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn), "Glance keep awake" as CFString, &id)
            return result == kIOReturnSuccess ? id : nil
        }, release: { IOPMAssertionRelease($0) == kIOReturnSuccess })
    }
}

@MainActor
final class FooterActionController: ObservableObject {
    @Published private(set) var isKeepingAwake = false
    @Published var errorMessage: String?
    private let localization: Localization
    private let effects: FooterActionEffects
    nonisolated(unsafe) private let lockLibrary: UnsafeMutableRawPointer?
    private let lockScreen: (@convention(c) () -> Void)?
    // Only this controller owns the assertion. Main-actor methods mutate it;
    // deinit performs the final synchronous IOKit release after ownership ends.
    nonisolated(unsafe) private var assertionID: UInt32?
    nonisolated(unsafe) private let releaseAssertion: (UInt32) -> Bool

    init(localization: Localization, effects: FooterActionEffects? = nil) {
        self.localization = localization
        let resolved = effects ?? .live
        self.effects = resolved
        releaseAssertion = resolved.release
        // Guarded private macOS facility, matching existing dynamic framework adapters.
        // Availability is checked; its void return cannot prove the screen locked.
        let library = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY)
        lockLibrary = library
        lockScreen = library.flatMap { dlsym($0, "SACLockScreenImmediate") }.map { unsafeBitCast($0, to: (@convention(c) () -> Void).self) }
    }

    deinit {
        if let assertionID { _ = releaseAssertion(assertionID) }
        if let lockLibrary { dlclose(lockLibrary) }
    }

    /// Capability inspection does not execute any system action or allocate a power assertion.
    nonisolated static func isSystemActionAvailable(_ kind: FooterModuleKind) -> Bool {
        switch kind {
        case .lockScreen:
            guard let library = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY) else { return false }
            defer { dlclose(library) }
            return dlsym(library, "SACLockScreenImmediate") != nil
        case .showDesktop:
            return FileManager.default.isExecutableFile(atPath: "/System/Applications/Mission Control.app/Contents/MacOS/Mission Control")
        default: return true
        }
    }

    func isAvailable(_ kind: FooterModuleKind) -> Bool {
        switch kind {
        case .lockScreen: return lockScreen != nil
        case .showDesktop: return FileManager.default.isExecutableFile(atPath: "/System/Applications/Mission Control.app/Contents/MacOS/Mission Control")
        default: return true
        }
    }

    func perform(_ module: FooterModule) {
        errorMessage = nil
        switch module.kind {
        case .keepAwake:
            if assertionID != nil { stop() }
            else if let id = effects.acquire() { assertionID = id; isKeepingAwake = true }
            else { fail(.footerActionKeepAwakeFailed) }
        case .application, .shortcut, .website, .file, .folder:
            do { open(try FooterActionTarget.url(kind: module.kind, target: module.target)) }
            catch let failure as FooterActionTarget.Failure {
                switch failure {
                case .website: fail(.footerActionInvalidWebsite)
                case .application: fail(.footerActionInvalidApplication)
                case .file: fail(.footerActionInvalidFile)
                case .folder: fail(.footerActionInvalidFolder)
                case .shortcut: fail(.footerActionInvalidShortcut)
                }
            } catch { fail(.footerActionOpenFailed) }
        case .downloads:
            guard let url = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
                fail(.footerActionInvalidFolder); return
            }
            open(url)
        case .calculator: openSystemApplication("com.apple.calculator")
        case .notes: openSystemApplication("com.apple.Notes")
        case .reminders: openSystemApplication("com.apple.reminders")
        case .showDesktop:
            // Launch Services satisfies Mission Control's launch constraints;
            // direct Process execution can be killed with Code Signature Invalid.
            // Argument 1 selects com.apple.showdesktop.awake.
            Task { @MainActor [weak self] in
                do {
                    try await SystemApplicationLauncher.open(
                        URL(fileURLWithPath: "/System/Applications/Mission Control.app"), arguments: ["1"])
                } catch { self?.fail(.footerActionSystemUnavailable) }
            }
        case .lockScreen:
            guard let lockScreen else { fail(.footerActionSystemUnavailable); return }
            lockScreen()
        default: break // Existing popup utilities are dispatched by the footer view.
        }
    }

    func reconcile(layout: FooterLayout) {
        if !layout.modules.contains(where: { $0.kind == .keepAwake }) { stop() }
    }

    func stop() {
        guard let id = assertionID else { return }
        guard effects.release(id) else { fail(.footerActionKeepAwakeFailed); return }
        assertionID = nil
        isKeepingAwake = false
    }

    private func open(_ url: URL) {
        if !effects.open(url) { fail(.footerActionOpenFailed) }
    }

    private func openSystemApplication(_ identifier: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) else {
            fail(.footerActionOpenFailed); return
        }
        open(url)
    }

    private func fail(_ key: LocalizationKey) { errorMessage = localization.string(key) }
}
