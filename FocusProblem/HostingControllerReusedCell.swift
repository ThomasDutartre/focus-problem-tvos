import SwiftUI

// MARK: - SwiftUI Hosting Cell via a reused UIHostingController

/// Same as `HostingControllerCell`, but the hosting controller is created once per cell and only its
/// `rootView` is replaced on reuse (no view controller teardown / re-creation while scrolling).
final class HostingControllerReusedCell: UICollectionViewCell {

    private var hostingController: UIHostingController<AnyView>?

    override var canBecomeFocused: Bool { false }

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        if let hcView = hostingController?.view { return [hcView] }
        return super.preferredFocusEnvironments
    }

    func configure<Content: View>(rootView: Content, parentViewController: UIViewController?) {
        if let hc = hostingController {
            hc.rootView = AnyView(rootView)
            if hc.parent !== parentViewController {
                hc.willMove(toParent: nil)
                hc.removeFromParent()
                parentViewController?.addChild(hc)
                hc.didMove(toParent: parentViewController)
            }
            return
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
}
