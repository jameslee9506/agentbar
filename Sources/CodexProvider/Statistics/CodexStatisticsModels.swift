struct CodexStatisticsModels: Sendable {
    private(set) var names: [String]
    private var indices: [String: UInt32]

    init(_ names: [String] = ["unknown"]) {
        self.names = names
        indices = Dictionary(names.enumerated().map { ($0.element, UInt32($0.offset)) }, uniquingKeysWith: { first, _ in first })
    }

    mutating func index(_ name: String) -> UInt32 {
        if let index = indices[name] { return index }
        let index = UInt32(names.count)
        names.append(name)
        indices[name] = index
        return index
    }
}
