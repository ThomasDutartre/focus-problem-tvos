import SwiftUI

// MARK: - SwiftUI Hosting Cell via UIHostingController

final class HostingControllerCell: UICollectionViewCell {
    
    private var hostingController: UIHostingController<AnyView>?
    
    #if os(tvOS)
    override var canBecomeFocused: Bool { false }

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        if let hcView = hostingController?.view {
            print("\(kDebugPrefix) HostingControllerCell.preferredFocusEnvironments → hostingController.view (\(String(format: "%p", unsafeBitCast(hcView, to: Int.self))))")
            return [hcView]
        }
        print("\(kDebugPrefix) HostingControllerCell.preferredFocusEnvironments → super (no HC)")
        return super.preferredFocusEnvironments
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        let prev = context.previouslyFocusedView.map { String(describing: type(of: $0)) } ?? "nil"
        let next = context.nextFocusedView.map { String(describing: type(of: $0)) } ?? "nil"
        print("\(kDebugPrefix) HostingControllerCell.didUpdateFocus: \(prev) → \(next)")
    }
    #endif
    
    func configure<Content: View>(rootView: Content, parentViewController: UIViewController?) {
        if let existing = hostingController {
            existing.willMove(toParent: nil)
            existing.view.removeFromSuperview()
            existing.removeFromParent()
            hostingController = nil
        }
        
        let hc = UIHostingController(rootView: AnyView(rootView))
        hc.view.backgroundColor = .clear
        hc.view.translatesAutoresizingMaskIntoConstraints = false
        
        parentViewController?.addChild(hc)
        contentView.addSubview(hc.view)
        hc.didMove(toParent: parentViewController)
        
        NSLayoutConstraint.activate([
            hc.view.topAnchor.constraint(equalTo: contentView.topAnchor),
            hc.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            hc.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            hc.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
        
        hostingController = hc
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        if let existing = hostingController {
            existing.willMove(toParent: nil)
            existing.view.removeFromSuperview()
            existing.removeFromParent()
            hostingController = nil
        }
    }
}
