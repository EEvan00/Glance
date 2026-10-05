import AppKit
import Combine
import DisplayFeaturesBridge

struct DisplayPreset: Identifiable, Equatable {
    let id: Int32
    let name: String
}

@MainActor
final class DisplayControlsController: ObservableObject {
    @Published private(set) var presets: [DisplayPreset] = []
    @Published private(set) var activePreset: Int32?
    @Published private(set) var displayName = ""
    @Published private(set) var states: [Int: Bool] = [:]
    @Published private(set) var actionFailed = false
    private var display: CGDirectDisplayID?
    private typealias Index = @convention(c) (UInt32) -> Int32
    private typealias CopyPreset = @convention(c) (UInt32, Int32) -> Unmanaged<CFDictionary>?
    private typealias SetPreset = @convention(c) (UInt32, Int32) -> Void
    // Exclusively owned handle; Swift 6.1 deinit releases it after synchronous API calls end.
    nonisolated(unsafe) private let handle: UnsafeMutableRawPointer?
    private let count: Index?
    private let active: Index?
    private let copyPreset: CopyPreset?
    private let setPreset: SetPreset?

    init() {
        let library = dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY)
        handle = library
        count = library.flatMap { dlsym($0, "CoreDisplay_Display_GetPresetCount") }.map { unsafeBitCast($0, to: Index.self) }
        active = library.flatMap { dlsym($0, "CoreDisplay_Display_GetActivePresetIndex") }.map { unsafeBitCast($0, to: Index.self) }
        copyPreset = library.flatMap { dlsym($0, "CoreDisplay_Display_CopyPreset") }.map { unsafeBitCast($0, to: CopyPreset.self) }
        setPreset = library.flatMap { dlsym($0, "CoreDisplay_Display_SetActivePresetIndex") }.map { unsafeBitCast($0, to: SetPreset.self) }
    }

    func refresh() {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var size: UInt32 = 0
        if CGGetOnlineDisplayList(16, &ids, &size) == .success {
            display = ids.prefix(Int(size)).first { CGDisplayIsBuiltin($0) != 0 } ?? ids.prefix(Int(size)).first
        } else { display = nil }
        displayName = NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display }?.localizedName ?? ""
        presets = []
        activePreset = nil
        if let display, let count, let active, let copyPreset, setPreset != nil {
            let total = count(display)
            if total > 0 && total <= 64 {
                activePreset = active(display)
                for index in 0..<total {
                    guard let dictionary = copyPreset(display, index)?.takeRetainedValue() as? [String: Any],
                          dictionary["PresetValid"] as? Bool == true,
                          let name = dictionary["PresetName"] as? String, !name.isEmpty else { continue }
                    presets.append(DisplayPreset(id: index, name: name))
                }
            }
        }
        states = [:]
        for feature in 0...2 {
            let state = STDisplayFeatureState(Int32(feature))
            if state >= 0 { states[feature] = state == 1 }
        }
    }

    func select(_ preset: DisplayPreset) {
        guard presets.contains(preset), let display, let setPreset else { return }
        setPreset(display, preset.id)
        refresh()
        actionFailed = activePreset != preset.id
    }

    func toggle(_ feature: Int) {
        guard let enabled = states[feature] else { return }
        let accepted = STSetDisplayFeature(Int32(feature), !enabled)
        refresh()
        actionFailed = !accepted || states[feature] != !enabled
    }

    func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    deinit { if let handle { dlclose(handle) } }
}
