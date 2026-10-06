import AppKit
import SwiftUI

/// Retains the native track and knob, overriding only the filled portion.
struct MediaProgressSlider: NSViewRepresentable {
    @Binding var value: Double
    let onEditingChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> MediaProgressControl {
        let slider = MediaProgressControl(frame: .zero)
        slider.cell = MediaProgressCell()
        slider.controlSize = .mini
        slider.minValue = 0
        slider.maxValue = 1
        slider.isContinuous = true
        slider.target = context.coordinator
        slider.action = #selector(Coordinator.changed(_:))
        slider.editingChanged = { [weak coordinator = context.coordinator] editing in
            coordinator?.isEditing = editing
            coordinator?.parent.onEditingChanged(editing)
        }
        return slider
    }

    func updateNSView(_ slider: MediaProgressControl, context: Context) {
        context.coordinator.parent = self
        if !context.coordinator.isEditing { slider.doubleValue = value }
        slider.isEnabled = context.environment.isEnabled
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: MediaProgressSlider
        var isEditing = false
        init(_ parent: MediaProgressSlider) { self.parent = parent }
        @objc func changed(_ slider: NSSlider) {
            // Keyboard and accessibility changes also commit a complete seek.
            if !isEditing { parent.onEditingChanged(true) }
            parent.value = slider.doubleValue
            if !isEditing { parent.onEditingChanged(false) }
        }
    }
}

@MainActor
final class MediaProgressControl: NSSlider {
    var editingChanged: ((Bool) -> Void)?
    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        editingChanged?(true)
        super.mouseDown(with: event)
        editingChanged?(false)
    }
}

@MainActor
final class MediaProgressCell: NSSliderCell {
    override func drawBar(inside rect: NSRect, flipped: Bool) {
        super.drawBar(inside: rect, flipped: flipped)
        let bar = barRect(flipped: flipped)
        let end = min(bar.maxX, max(bar.minX, knobRect(flipped: flipped).midX))
        guard end > bar.minX else { return }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: bar, xRadius: bar.height / 2, yRadius: bar.height / 2).addClip()
        NSColor(PopupProgressBar.fillColor).setFill()
        NSRect(x: bar.minX, y: bar.minY, width: end - bar.minX, height: bar.height).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}
