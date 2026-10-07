import UIKit

/// Drives a benchmark without any remote input (works on a physical Apple TV):
/// - `scroll`: programmatic scroll top → bottom → top at constant speed (stresses dequeue / reuse / display),
/// - `focus`: programmatic focus jumps to each jumbotron (top → bottom → top) and checks focus ends inside it,
/// - `all`: `scroll` then `focus`.
/// Results are printed as `📊` lines.
final class BenchDriver: NSObject {
    private weak var viewController: FocusProblemViewController?
    private let collectionView: UICollectionView
    private let sections: [Section]
    private let mode: String
    private let label: String

    private static let scrollSpeed: CGFloat = 3000 // pt/s
    private static let focusInterval: TimeInterval = 0.7

    init(viewController: FocusProblemViewController, collectionView: UICollectionView, sections: [Section], mode: String, label: String) {
        self.viewController = viewController
        self.collectionView = collectionView
        self.sections = sections
        self.mode = mode
        self.label = label
    }

    func start() {
        print("⚙️ bench mode=\(mode) \(label) sections=\(sections.count)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [self] in
            switch mode {
            case "focus": runFocus { self.done() }
            case "all": runScroll { self.runFocus { self.done() } }
            default: runScroll { self.done() }
            }
        }
    }

    private func done() {
        print("⚙️ bench finished")
    }

    // MARK: Scroll

    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var direction: CGFloat = 1
    private var scrollCompletion: (() -> Void)?

    private func runScroll(completion: @escaping () -> Void) {
        scrollCompletion = completion
        direction = 1
        lastTimestamp = 0
        Perf.shared.start()
        let link = CADisplayLink(target: self, selector: #selector(scrollTick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func scrollTick(_ link: CADisplayLink) {
        defer { lastTimestamp = link.timestamp }
        guard lastTimestamp > 0 else { return }
        let dt = CGFloat(link.timestamp - lastTimestamp)
        let maxY = max(0, collectionView.contentSize.height - collectionView.bounds.height + collectionView.adjustedContentInset.bottom)
        var y = collectionView.contentOffset.y + direction * Self.scrollSpeed * dt
        if direction > 0, y >= maxY {
            y = maxY
            direction = -1
        } else if direction < 0, y <= 0 {
            y = 0
            link.invalidate()
            self.link = nil
            collectionView.contentOffset.y = 0
            Perf.shared.stopAndReport("scroll \(label)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.scrollCompletion?() }
            return
        }
        collectionView.contentOffset.y = y
    }

    // MARK: Focus

    private var tabBarController: FocusRedirectingTabBarController? {
        viewController?.tabBarController as? FocusRedirectingTabBarController
    }

    private static func environment(_ ancestor: UIFocusEnvironment, contains item: UIFocusEnvironment) -> Bool {
        var current: UIFocusEnvironment? = item
        while let env = current {
            if env === ancestor { return true }
            current = env.parentFocusEnvironment
        }
        return false
    }

    private func runFocus(completion: @escaping () -> Void) {
        let targets = sections.filter {
            if case .jumbotron(let v) = $0.kind { return v != .uikit }
            return false
        }.map { IndexPath(item: 0, section: $0.index) }
        let path = Array(targets.prefix(20)) + Array(targets.prefix(20).reversed().dropFirst())

        // Move focus out of the tab bar into the collection view first, through a UIKit card (always focusable).
        if let cards = sections.first(where: { $0.kind == .cardsUIKit }) {
            let ip = IndexPath(item: 0, section: cards.index)
            collectionView.scrollToItem(at: ip, at: .centeredVertically, animated: false)
            collectionView.layoutIfNeeded()
            if let cell = collectionView.cellForItem(at: ip) {
                tabBarController?.moveFocus(to: cell)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
            let focused = collectionView.window?.windowScene?.focusSystem?.focusedItem
            print("⚙️ focus bench start — focused: \(focused.map { String(describing: type(of: $0)) } ?? "nil")")
            Perf.shared.start()
            jump(path, index: 0, completion: completion)
        }
    }

    private func jump(_ path: [IndexPath], index: Int, completion: @escaping () -> Void) {
        guard index < path.count, let viewController else {
            Perf.shared.stopAndReport("focus \(label)")
            completion()
            return
        }
        let target = path[index]
        // Bring the target just on screen (bottom edge), then ask focus to move there:
        // the focus engine scrolls it into place, as with a real remote press.
        collectionView.scrollToItem(at: target, at: .bottom, animated: false)
        collectionView.layoutIfNeeded()
        // Request through the focus system: a view controller request is ignored when it doesn't
        // contain the focused item (e.g. focus still in the tab bar at launch).
        if let cell = collectionView.cellForItem(at: target) {
            Perf.shared.measure("focus.request") {
                tabBarController?.moveFocus(to: cell)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.focusInterval) { [self] in
            let focused = collectionView.window?.windowScene?.focusSystem?.focusedItem
            if let cell = collectionView.cellForItem(at: target), let focused,
               focused !== cell, Self.environment(cell, contains: focused) {
                Perf.shared.increment("focus.landedInContent")
            } else {
                Perf.shared.increment("focus.FAILED")
                print("⚠️ focus jump to S\(target.section) failed — focused: \(focused.map { String(describing: type(of: $0)) } ?? "nil")")
            }
            jump(path, index: index + 1, completion: completion)
        }
    }
}
