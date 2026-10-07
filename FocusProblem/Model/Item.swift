nonisolated enum Item: Hashable, Sendable {
    case card(id: Int, section: Int)
    case jumbotron(section: Int, variant: JumbotronVariant)
}
