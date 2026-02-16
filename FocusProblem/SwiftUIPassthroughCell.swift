import UIKit

final class SwiftUIPassthroughCell: UICollectionViewCell {
    override var canBecomeFocused: Bool {
        print("\(kDebugPrefix) SwiftUIPassthroughCell.canBecomeFocused queried → false (ptr: \(String(format: "%p", unsafeBitCast(self, to: Int.self))))")
        return false
    }

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        let envs = contentView.subviews
        let desc = envs.map { "\(type(of: $0)) \(String(format: "%p", unsafeBitCast($0, to: Int.self)))" }
        print("\(kDebugPrefix) SwiftUIPassthroughCell.preferredFocusEnvironments → [\(desc.joined(separator: ", "))]")
        return envs.isEmpty ? super.preferredFocusEnvironments : envs
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        let prev = context.previouslyFocusedView.map { String(describing: type(of: $0)) } ?? "nil"
        let next = context.nextFocusedView.map { String(describing: type(of: $0)) } ?? "nil"
        print("\(kDebugPrefix) SwiftUIPassthroughCell.didUpdateFocus: \(prev) → \(next)")
    }
}
