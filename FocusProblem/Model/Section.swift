// MARK: - Section Model

nonisolated enum Section: Int, CaseIterable, Sendable {
    case cardsSwiftUI = 0
    case jumbotronSwiftUIHC
    case jumbotronUIKit
    case jumbotronSwiftUI
    case cardsUIKit
    
    var title: String {
        switch self {
        case .cardsSwiftUI:       return "Section 0 — Cards (SwiftUI · UIHostingConfiguration)"
        case .jumbotronSwiftUIHC: return "Section 1 — Jumbotron SwiftUI · UIHostingController"
        case .jumbotronUIKit:     return "Section 2 — Jumbotron UIKit (focus OK)"
        case .jumbotronSwiftUI:   return "Section 3 — Jumbotron SwiftUI · UIHostingConfiguration"
        case .cardsUIKit:         return "Section 4 — Cards (UIKit)"
        }
    }
}
