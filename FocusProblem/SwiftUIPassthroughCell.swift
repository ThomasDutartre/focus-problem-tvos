import UIKit

/// Cell hosting multi-focusable SwiftUI content through `UIHostingConfiguration`.
///
/// `UIHostingContentView` sometimes exposes no focusable SwiftUI item to UIKit:
/// - before the cell has ever been on screen (its SwiftUI content is built lazily), and
/// - after some reuse / focus cycles, where only empty focus containers remain
///   (the focusable leaves are never re-registered).
/// The focus engine then skips the cell, or loses focus (`→ nil`) when the leaves vanish.
///
/// Workaround (public API only): while no focusable SwiftUI item is exposed, the cell itself is a
/// focus placeholder. When it receives focus, its content is rebuilt (it is now about to be on screen),
/// and focus is forwarded to the SwiftUI content as soon as its focusable items exist.
final class SwiftUIPassthroughCell: UICollectionViewCell {

    private static let workaroundEnabled = ProcessInfo.processInfo.environment["WORKAROUND"] != "off"

    /// `true` when the hosted SwiftUI content exposes at least one focusable item.
    var hostedFocusItemsReady: Bool {
        Self.containsFocusableItem(contentView)
    }

    private static func containsFocusableItem(_ environment: UIFocusEnvironment, depth: Int = 0) -> Bool {
        guard depth < 10, let container = environment.focusItemContainer else { return false }
        let bounds = (environment as? UIView)?.bounds ?? CGRect(x: -50_000, y: -50_000, width: 100_000, height: 100_000)
        for item in container.focusItems(in: bounds) where item !== environment {
            if item.canBecomeFocused || containsFocusableItem(item, depth: depth + 1) { return true }
        }
        return false
    }

    override var canBecomeFocused: Bool {
        guard Self.workaroundEnabled else { return false }
        return !hostedFocusItemsReady
    }

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        [contentView]
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        // Drop the previous hosting content view: it would otherwise keep exposing the focus items
        // of the previous content, which vanish as soon as the new content is rendered.
        if Self.workaroundEnabled {
            contentConfiguration = nil
        }
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        let prev = context.previouslyFocusedView.map { String(describing: type(of: $0)) } ?? "nil"
        let next = context.nextFocusedView.map { String(describing: type(of: $0)) } ?? "nil"
        print("\(kDebugPrefix) SwiftUIPassthroughCell.didUpdateFocus: \(prev) → \(next)")
        if context.nextFocusedItem === self {
            rebuildHostedContent()
            forwardFocusToHostedContent()
        }
    }

    /// Recreates the `UIHostingContentView` so SwiftUI registers its focusable items again.
    private func rebuildHostedContent() {
        print("\(kDebugPrefix) SwiftUIPassthroughCell rebuilding hosted content")
        let configuration = contentConfiguration
        contentConfiguration = nil
        contentConfiguration = configuration
    }

    /// Focus requests are ignored while the collection view scrolls the cell into view,
    /// so keep asking until focus has actually moved into the SwiftUI content.
    private func forwardFocusToHostedContent(attempt: Int = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, self.isFocused, attempt < 40 else { return }
            if self.hostedFocusItemsReady {
                print("\(kDebugPrefix) SwiftUIPassthroughCell forwarding focus to SwiftUI content (attempt \(attempt))")
                self.setNeedsFocusUpdate()
                self.updateFocusIfNeeded()
            } else if attempt == 20 {
                self.rebuildHostedContent()
            }
            self.forwardFocusToHostedContent(attempt: attempt + 1)
        }
    }
}
