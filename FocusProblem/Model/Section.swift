import Foundation

// MARK: - Section Model

/// How a jumbotron cell hosts its content.
nonisolated enum JumbotronVariant: String, CaseIterable, Sendable {
    /// Pure UIKit cell with UIButtons (reference: focus OK).
    case uikit
    /// SwiftUI via `UIHostingController` (child view controller containment).
    case hostingController
    /// SwiftUI via `UIHostingConfiguration` (original bug).
    case hostingConfiguration
    /// SwiftUI via `UIHostingConfiguration`, re-applied on reuse (H12).
    case hostingConfigurationReset

    var label: String {
        switch self {
        case .uikit:                     return "UIKit"
        case .hostingController:         return "SwiftUI · UIHostingController"
        case .hostingConfiguration:      return "SwiftUI · UIHostingConfiguration"
        case .hostingConfigurationReset: return "SwiftUI · UIHostingConfiguration (reset on reuse)"
        }
    }
}

nonisolated enum SectionKind: Hashable, Sendable {
    case cardsUIKit
    case cardsSwiftUI
    case jumbotron(JumbotronVariant)

    var label: String {
        switch self {
        case .cardsUIKit:           return "Cards (UIKit)"
        case .cardsSwiftUI:         return "Cards (SwiftUI · UIHostingConfiguration)"
        case .jumbotron(let v):     return "Jumbotron \(v.label)"
        }
    }
}

nonisolated struct Section: Hashable, Sendable {
    let index: Int
    let kind: SectionKind

    var title: String { "Section \(index) — \(kind.label)" }
}

// MARK: - Page layouts

nonisolated enum PageLayout {
    /// Reads `FOCUS_LAYOUT` from the environment:
    /// - unset / `default`: the original 6-section page
    /// - `stress:<variant>`: many sections alternating UIKit and `<variant>` jumbotrons,
    ///   tall enough that a full top→bottom scroll recycles the cells.
    static func current() -> [SectionKind] {
        let value = ProcessInfo.processInfo.environment["FOCUS_LAYOUT"] ?? "default"
        if value.hasPrefix("stress:"), let variant = JumbotronVariant(rawValue: String(value.dropFirst("stress:".count))) {
            return stress(variant)
        }
        return [
            .cardsSwiftUI,
            .jumbotron(.hostingController),
            .jumbotron(.uikit),
            .jumbotron(.hostingConfiguration),
            .jumbotron(.hostingConfigurationReset),
            .cardsUIKit,
        ]
    }

    static func stress(_ v: JumbotronVariant) -> [SectionKind] {
        [
            .cardsUIKit,
            .jumbotron(v),
            .jumbotron(.uikit),
            .jumbotron(v),
            .cardsUIKit,
            .jumbotron(v),
            .jumbotron(v),
            .cardsUIKit,
            .jumbotron(v),
            .jumbotron(.uikit),
            .jumbotron(v),
            .cardsUIKit,
        ]
    }
}
