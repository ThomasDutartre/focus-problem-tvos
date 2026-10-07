import UIKit
import SwiftUI

/// Same passthrough behavior as `SwiftUIPassthroughCell`, but the hosted
/// `JumbotronSwiftUIView` is stored and re-applied to `contentConfiguration`
/// on every reuse, forcing a fresh `UIHostingConfiguration` on recycle.
final class SwiftUIResetPassthroughCell: UICollectionViewCell {
    private var storedView: JumbotronSwiftUIView?

    override var canBecomeFocused: Bool {
        debugLog("\(kDebugPrefix) SwiftUIResetPassthroughCell.canBecomeFocused queried → false (ptr: \(String(format: "%p", unsafeBitCast(self, to: Int.self))))")
        return false
    }

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        let envs = contentView.subviews
        return envs.isEmpty ? super.preferredFocusEnvironments : envs
    }

    func configure(with view: JumbotronSwiftUIView) {
        storedView = view
        applyConfiguration()
    }

    private func applyConfiguration() {
        guard let storedView else { return }
        contentConfiguration = UIHostingConfiguration {
            storedView
        }
        .margins(.all, 0)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        debugLog("\(kDebugPrefix) SwiftUIResetPassthroughCell.prepareForReuse — reset & re-apply stored JumbotronSwiftUIView")
        contentConfiguration = nil
        applyConfiguration()
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        let prev = context.previouslyFocusedView.map { String(describing: type(of: $0)) } ?? "nil"
        let next = context.nextFocusedView.map { String(describing: type(of: $0)) } ?? "nil"
        debugLog("\(kDebugPrefix) SwiftUIResetPassthroughCell.didUpdateFocus: \(prev) → \(next)")
    }
}
