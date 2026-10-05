import AppKit
import Combine
import Darwin

@MainActor
final class BrightnessController: ObservableObject {
    @Published private(set) var value: Double?
    private typealias GetBrightness = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (UInt32, Float) -> Int32
    // Handle belongs exclusively to this controller; deinit only releases it.
    nonisolated(unsafe) private let handle: UnsafeMutableRawPointer?
    private let getBrightness: GetBrightness?
    private let setBrightness: SetBrightness?
    private var display: CGDirectDisplayID?
    private var lastWrite = Date.distantPast

    init() {
        let library = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
        handle = library
        getBrightness = library.flatMap { dlsym($0, "DisplayServicesGetBrightness") }.map { unsafeBitCast($0, to: GetBrightness.self) }
        setBrightness = library.flatMap { dlsym($0, "DisplayServicesSetBrightness") }.map { unsafeBitCast($0, to: SetBrightness.self) }
    }

    func refresh() {
        var count: UInt32 = 0
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        guard CGGetOnlineDisplayList(16, &displays, &count) == .success,
              let builtIn = displays.prefix(Int(count)).first(where: { CGDisplayIsBuiltin($0) != 0 }),
              let getBrightness, setBrightness != nil else { value = nil; display = nil; return }
        var scalar: Float = 0
        guard getBrightness(builtIn, &scalar) == 0, scalar.isFinite else { value = nil; display = nil; return }
        display = builtIn
        value = min(1, max(0, Double(scalar)))
    }

    func setValue(_ scalar: Double, final: Bool = false) {
        guard scalar.isFinite, let display, let setBrightness else { return }
        let now = Date()
        guard final || now.timeIntervalSince(lastWrite) >= 1.0 / 30 else { return }
        lastWrite = now
        if setBrightness(display, Float(min(1, max(0, scalar)))) == 0 {
            value = min(1, max(0, scalar))
        } else { refresh() }
    }

    deinit { if let handle { dlclose(handle) } }
}
