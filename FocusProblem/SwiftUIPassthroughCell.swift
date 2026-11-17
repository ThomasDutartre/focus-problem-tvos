import UIKit

/// Cell hosting SwiftUI content through `UIHostingConfiguration`, with several focusable SwiftUI buttons.
///
/// Problem: such a cell exposes no SwiftUI focus items while it is off screen, and loses them after a
/// hidden → visible cycle, so the focus engine skips it or the buttons never get the focus.
///
/// Fix ("trampoline"): while focus is outside, the cell itself is focusable (like the working SwiftUI
/// cards). When it receives focus, it hands focus over to its SwiftUI buttons, rebuilding the SwiftUI
/// content first only if the cell went off screen since the content was built.
///
/// What belongs to the fix, by mechanism (marked `FIX [n]` below):
///   [1] the cell is focusable while focus is outside              → `canBecomeFocused`
///   [2] on focus, hand over to the SwiftUI buttons                → `didUpdateFocus`, `preferredFocusEnvironments`
///   [3] rebuild the content only when it went stale               → `contentIsStale`, `rebuildContent`, `didConfigure`
///   [4] retry the hand-over every frame until SwiftUI is ready    → `handOver`, `performHandOver`
/// Everything in this class is part of the fix: the original cell was only a non-focusable passthrough
/// (`canBecomeFocused = false`, `preferredFocusEnvironments` = its subviews), which is the part kept as the
/// "outside the trampoline" fallback in `preferredFocusEnvironments`.
///
/// See FIX-HANDOFF.md for the root cause, the stress-test results and the integration notes.
final class SwiftUIPassthroughCell: UICollectionViewCell {

    /// FIX [3]: set by the cell registration, builds a fresh content configuration.
    var makeContentConfiguration: (() -> UIContentConfiguration)?

    private var focusIsInside = false
    private var redirecting = false
    /// True once the cell went off screen after its content was built: its SwiftUI focus items are gone.
    private var contentIsStale = false
    private var isDisplayed = false
    private var handOverPending = false
    private var recoveredThisEntry = false

    // MARK: - Focus

    /// FIX [1]: focusable while focus is outside, so the engine can always land on the cell (originally `false`).
    /// Not focusable once focus is inside, or while handing over, so it never steals focus from its buttons.
    override var canBecomeFocused: Bool {
        !focusIsInside && !redirecting
    }

    /// FIX [2]: while handing over, point the engine at the SwiftUI content. Otherwise this is the original
    /// behaviour (the SwiftUI subviews).
    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        if redirecting { return [contentView] }
        let envs = contentView.subviews
        return envs.isEmpty ? super.preferredFocusEnvironments : envs
    }

    /// FIX [2]: detects focus landing on the cell (start of the hand-over) and focus being inside or outside.
    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        let next = context.nextFocusedView
        focusIsInside = next.map { $0 !== self && $0.isDescendant(of: self) } ?? false

        if next === self {
            startTrampoline()
        } else if !focusIsInside {
            redirecting = false
            handOverPending = false
        }
    }

    /// FIX [2]+[3]+[4]: entry point of the hand-over.
    private func startTrampoline() {
        redirecting = true
        recoveredThisEntry = false
        if contentIsStale { rebuildContent() }
        if isDisplayed {
            handOver(attempt: 1)
        } else {
            handOverPending = true   // resumed by cellWillDisplay()
        }
    }

    // MARK: - Content rebuild (FIX [3])

    /// Drops the configuration first so UIKit creates a new hosting view: re-assigning on top of the
    /// existing one updates it in place and does not bring the focus items back.
    private func rebuildContent() {
        guard let make = makeContentConfiguration else { return }
        contentConfiguration = nil
        contentConfiguration = make()
        contentIsStale = false
    }

    /// Call from the cell registration each time it assigns a configuration.
    ///
    /// Only a configuration assigned to a cell that had none creates a new hosting view, so only that one
    /// gives fresh content. When a cell that went off screen is dequeued again, the registration assigns on
    /// top of the existing configuration: the old hosting view is updated in place, its focus items stay
    /// dead, and the content must still count as stale.
    func didConfigure(replacedExistingContent: Bool) {
        if !replacedExistingContent { contentIsStale = false }
    }

    // MARK: - Display tracking (forwarded by the collection view delegate)

    func cellWillDisplay() {
        isDisplayed = true
        if handOverPending {
            handOverPending = false
            handOver(attempt: 1)
        }
    }

    func cellDidEndDisplaying() {
        isDisplayed = false
        contentIsStale = true
    }

    // MARK: - Hand-over (FIX [4])

    /// Tries on the next run loop turn, then once per frame until SwiftUI has declared its focus items.
    /// Called from `startTrampoline` / `cellWillDisplay` (attempt 1, no delay) and then from `performHandOver`
    /// itself while the focus is not inside yet. SwiftUI declares its focus items asynchronously after the
    /// content is (re)built, so a single `setNeedsFocusUpdate()` right away fails; a fixed delay (tried: 0.3 s)
    /// is slower than needed in the common case (≈ 16 ms when the content is still valid).
    private func handOver(attempt: Int) {
        let delay: TimeInterval = attempt == 1 ? 0 : 1.0 / 60.0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.performHandOver(attempt: attempt)
        }
    }

    private func performHandOver(attempt: Int) {
        guard redirecting else { return }
        setNeedsFocusUpdate()
        updateFocusIfNeeded()

        if !focusIsInside && attempt < Self.maxHandOverAttempts {
            // Safety net: still nothing after ≈ 0.5 s, so the content is dead whatever our bookkeeping
            // says. Rebuild it once and keep trying.
            if attempt == Self.recoveryAttempt && !recoveredThisEntry {
                recoveredThisEntry = true
                rebuildContent()
            }
            handOver(attempt: attempt + 1)
            return
        }
        redirecting = false
    }

    private static let maxHandOverAttempts = 60
    private static let recoveryAttempt = 30
}
