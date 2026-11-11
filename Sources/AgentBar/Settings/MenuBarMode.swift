enum MenuBarMode: String, CaseIterable, Identifiable {
    case separate
    case combined

    var id: Self { self }
    var title: String { self == .separate ? "Separate accounts" : "Combined" }
}
