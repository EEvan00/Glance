import Foundation

struct FooterLayout: Codable, Equatable, Sendable {
    static let capacity = 8
    static let currentVersion = 1
    private(set) var modules: [FooterModule]
    var usedSlots: Int { modules.reduce(0) { $0 + $1.width } }
    var remainingSlots: Int { Self.capacity - usedSlots }
    var utilities: Set<PopupUtility> { Set(modules.compactMap { $0.kind.utility }) }

    init(modules: [FooterModule]) {
        self.modules = []
        for module in modules { _ = add(module) }
    }

    static var defaultLayout: FooterLayout {
        FooterLayout(modules: [
            FooterModule(kind: .timer), FooterModule(kind: .weather, width: 2),
            FooterModule(kind: .date, width: 2), FooterModule(kind: .clock, width: 2),
            FooterModule(kind: .screenshot)
        ])
    }

    func startSlot(for id: UUID) -> Int? {
        guard let index = modules.firstIndex(where: { $0.id == id }) else { return nil }
        return modules.prefix(index).reduce(0) { $0 + $1.width }
    }

    @discardableResult
    mutating func add(_ module: FooterModule, at index: Int? = nil) -> Bool {
        let destination = index ?? modules.count
        guard (0...modules.count).contains(destination), accepts(module, replacing: nil) else { return false }
        modules.insert(module, at: destination)
        return true
    }

    @discardableResult
    mutating func remove(id: UUID) -> Bool {
        guard let index = modules.firstIndex(where: { $0.id == id }) else { return false }
        modules.remove(at: index)
        return true
    }

    /// Destination is the final list index; count appends to the end.
    @discardableResult
    mutating func move(id: UUID, to destination: Int) -> Bool {
        guard let source = modules.firstIndex(where: { $0.id == id }),
              (0...modules.count).contains(destination) else { return false }
        let module = modules.remove(at: source)
        modules.insert(module, at: min(destination, modules.count))
        return true
    }

    @discardableResult
    mutating func resize(id: UUID, width: Int) -> Bool {
        guard var module = modules.first(where: { $0.id == id }) else { return false }
        module.width = width
        return update(module)
    }

    @discardableResult
    mutating func update(_ module: FooterModule) -> Bool {
        guard let index = modules.firstIndex(where: { $0.id == module.id }),
              accepts(module, replacing: index) else { return false }
        modules[index] = module
        return true
    }

    private func accepts(_ module: FooterModule, replacing index: Int?) -> Bool {
        guard (1...2).contains(module.width) else { return false }
        let others = modules.enumerated().filter { $0.offset != index }.map(\.element)
        guard !others.contains(where: { $0.id == module.id }),
              module.kind.allowsMultipleInstances || !others.contains(where: { $0.kind == module.kind }) else { return false }
        return others.reduce(0) { $0 + $1.width } + module.width <= Self.capacity
    }

    private enum CodingKeys: String, CodingKey { case version, modules }
    private struct SavedModule: Decodable {
        let module: FooterModule?
        init(from decoder: Decoder) throws {
            module = try? FooterModule(from: decoder)
        }
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let version = try values.decode(Int.self, forKey: .version)
        guard version == Self.currentVersion else {
            throw DecodingError.dataCorruptedError(forKey: .version, in: values, debugDescription: "Unsupported footer layout version")
        }
        let saved = try values.decode([SavedModule].self, forKey: .modules)
        self.init(modules: saved.compactMap(\.module))
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(Self.currentVersion, forKey: .version)
        try values.encode(modules, forKey: .modules)
    }
}
