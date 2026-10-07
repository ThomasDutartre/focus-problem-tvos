import UIKit

/// Cell hosting multi-focusable SwiftUI content through `UIHostingConfiguration`.
///
/// `UIHostingContentView` sometimes exposes no focusable SwiftUI item to UIKit:
/// - before the cell has ever been on screen (its SwiftUI content is built lazily),
/// - after its content went off screen or was replaced (reuse): it keeps *stale* focus items that
///   vanish as soon as focus enters them (`→ nil`), sometimes leaving focus containers without leaves.
///
/// Workaround (public API only): while no usable SwiftUI item is exposed, the cell itself is a focus
/// placeholder; once focused, focus is forwarded to the SwiftUI content as soon as it is ready.
/// Stale content is handled according to `WORKAROUND`:
/// - `off`: no workaround (original bug)
/// - `v1`: rebuild the content view on `didEndDisplaying` and drop it on `prepareForReuse`
/// - `v2` (default): hide stale items, rebuild lazily only when focus lands on the cell
/// - `v3`: hide stale items, rebuild when the cell is displayed again (`willDisplay`)
final class SwiftUIPassthroughCell: UICollectionViewCell {

    enum Workaround: String {
        case off, v1, v2, v3
    }

    static let workaround = Workaround(rawValue: appSetting("WORKAROUND") ?? "") ?? .v2

    /// v2/v3: the content view went through disappear / reuse; its focus items can't be trusted.
    /// While stale, the content view doesn't take user interaction, so the focus engine ignores its items
    /// (overriding `focusItems(in:)` instead would disable UIKit's linear focus movement cache).
    private var hasStaleContent = false {
        didSet { contentView.isUserInteractionEnabled = !hasStaleContent }
    }
    /// v2/v3: cached positive result of the focus items walk (reset on every content change).
    private var focusItemsConfirmed = false
    private var placeholderFocusedAt: CFTimeInterval = 0

    // MARK: Focus items

    /// `true` when the hosted SwiftUI content exposes at least one usable focusable item.
    var hostedFocusItemsReady: Bool {
        switch Self.workaround {
        case .off, .v1:
            return Self.containsFocusableItem(contentView)
        case .v2, .v3:
            if hasStaleContent { return false }
            if focusItemsConfirmed { return true }
            focusItemsConfirmed = Self.containsFocusableItem(contentView)
            return focusItemsConfirmed
        }
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
        guard Self.workaround != .off else { return false }
        return Perf.shared.measure("cell.canBecomeFocused") { !hostedFocusItemsReady }
    }

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        hasStaleContent ? [] : [contentView]
    }

    // MARK: Lifecycle

    /// Call from `collectionView(_:willDisplay:forItemAt:)`.
    func willDisplay() {
        guard Self.workaround == .v3, hasStaleContent else { return }
        rebuildHostedContent()
    }

    /// Call from `collectionView(_:didEndDisplaying:forItemAt:)`.
    func didEndDisplaying() {
        switch Self.workaround {
        case .off:
            break
        case .v1:
            rebuildHostedContent()
        case .v2, .v3:
            markContentStale()
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        switch Self.workaround {
        case .off:
            break
        case .v1:
            // Drop the previous hosting content view: the registration creates a fresh one.
            contentConfiguration = nil
        case .v2, .v3:
            // The registration will update the existing content view with the new content: stale.
            markContentStale()
        }
    }

    private func markContentStale() {
        hasStaleContent = true
        focusItemsConfirmed = false
    }

    /// Recreates the `UIHostingContentView` so SwiftUI registers its focusable items again.
    private func rebuildHostedContent() {
        Perf.shared.measure("cell.rebuild") {
            debugLog("\(kDebugPrefix) SwiftUIPassthroughCell rebuilding hosted content")
            let configuration = contentConfiguration
            contentConfiguration = nil
            contentConfiguration = configuration
            hasStaleContent = false
            focusItemsConfirmed = false
        }
    }

    // MARK: Focus forwarding

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        let prev = context.previouslyFocusedView.map { String(describing: type(of: $0)) } ?? "nil"
        let next = context.nextFocusedView.map { String(describing: type(of: $0)) } ?? "nil"
        debugLog("\(kDebugPrefix) SwiftUIPassthroughCell.didUpdateFocus: \(prev) → \(next)")
        if context.nextFocusedItem === self {
            Perf.shared.increment("cell.placeholderFocused")
            placeholderFocusedAt = CACurrentMediaTime()
            if Self.workaround == .v1 || hasStaleContent {
                rebuildHostedContent()
            }
            forwardFocusToHostedContent()
        }
    }

    /// Focus requests are ignored while the collection view scrolls the cell into view,
    /// so keep asking until focus has actually moved into the SwiftUI content.
    private func forwardFocusToHostedContent(attempt: Int = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, self.isFocused, attempt < 40 else { return }
            if self.hostedFocusItemsReady {
                debugLog("\(kDebugPrefix) SwiftUIPassthroughCell forwarding focus to SwiftUI content (attempt \(attempt))")
                self.setNeedsFocusUpdate()
                self.updateFocusIfNeeded()
                if !self.isFocused {
                    Perf.shared.record("cell.placeholderHop", ms: (CACurrentMediaTime() - self.placeholderFocusedAt) * 1000)
                    return
                }
            } else if attempt == 20 {
                self.rebuildHostedContent()
            }
            self.forwardFocusToHostedContent(attempt: attempt + 1)
        }
    }
}
