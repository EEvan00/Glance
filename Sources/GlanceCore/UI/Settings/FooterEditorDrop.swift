import Foundation

/// Drag payloads are data only. Only known kinds and IDs already in this layout are accepted.
enum FooterEditorDrop {
    /// An occupied tile is one reorder target, regardless of its width or pointer position.
    static func apply(_ payload: String, onto targetID: UUID?, to layout: inout FooterLayout) -> Bool {
        if payload.hasPrefix("module:"), let targetID {
            guard let id = UUID(uuidString: String(payload.dropFirst(7))),
                  let destination = layout.modules.firstIndex(where: { $0.id == targetID }) else { return false }
            return layout.move(id: id, to: destination)
        }
        // Empty slots append; library entries insert before the chosen module.
        return apply(payload, before: targetID, to: &layout)
    }

    static func apply(_ payload: String, before targetID: UUID?, to layout: inout FooterLayout) -> Bool {
        let boundary: Int
        if let targetID {
            guard let index = layout.modules.firstIndex(where: { $0.id == targetID }) else { return false }
            boundary = index
        } else {
            boundary = layout.modules.count
        }
        if payload.hasPrefix("module:"), let id = UUID(uuidString: String(payload.dropFirst(7))),
           let source = layout.modules.firstIndex(where: { $0.id == id }) {
            return layout.move(id: id, to: source < boundary ? boundary - 1 : boundary)
        }
        if payload.hasPrefix("kind:"), let kind = FooterModuleKind(rawValue: String(payload.dropFirst(5))) {
            return layout.add(FooterModule(kind: kind), at: boundary)
        }
        return false
    }
}
