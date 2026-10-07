import UIKit

// MARK: - Debug Helpers

public let kDebugPrefix = "🐛 [FocusProblem]"

/// Compact marker parsed by the test scripts: `🎯 S<section>#<item> <kind> (<focused view type>)`.
public let kFocusMarker = "🎯"

func focusDescription(_ view: UIView?, in collectionView: UICollectionView?, sections: [Section]) -> String {
    let typeName = view.map { String(describing: type(of: $0)) } ?? "nil"
    let ptr = view.map { String(format: "%p", unsafeBitCast($0, to: Int.self)) } ?? ""
    guard let view, let cv = collectionView else { return "\(typeName) \(ptr)" }
    if let ip = indexPath(of: view, in: cv) {
        let title = sections.indices.contains(ip.section) ? sections[ip.section].title : "s\(ip.section)"
        return "\(typeName) \(ptr) [\(title), item \(ip.item)]"
    }
    return "\(typeName) \(ptr)"
}

func focusMarker(_ view: UIView?, in collectionView: UICollectionView?, sections: [Section]) -> String {
    guard let view else { return "\(kFocusMarker) nil" }
    let typeName = String(describing: type(of: view)).components(separatedBy: "<").first ?? ""
    guard let cv = collectionView, let ip = indexPath(of: view, in: cv) else {
        return "\(kFocusMarker) outside (\(typeName))"
    }
    let kind = sections.indices.contains(ip.section) ? "\(sections[ip.section].kind)" : "?"
    return "\(kFocusMarker) S\(ip.section)#\(ip.item) \(kind) (\(typeName))"
}

private func indexPath(of view: UIView, in cv: UICollectionView) -> IndexPath? {
    var current: UIView? = view
    while let v = current {
        if let cell = v as? UICollectionViewCell, let ip = cv.indexPath(for: cell) { return ip }
        current = v.superview
    }
    return nil
}

// MARK: - Focus items probe

/// Logs, for every visible cell of the given sections, how many focus items its content exposes
/// and where they are (in window coordinates). Used to see whether SwiftUI virtual items exist.
func probeFocusItems(in cv: UICollectionView, sections: [Section], tag: String) {
    for cell in cv.visibleCells {
        guard let ip = cv.indexPath(for: cell), sections.indices.contains(ip.section),
              case .jumbotron(let v) = sections[ip.section].kind, v != .uikit else { continue }
        // For UIHostingController cells the SwiftUI host is the contentView's subview.
        let host = cell.contentView.subviews.first { String(describing: type(of: $0)).contains("Hosting") } ?? cell.contentView
        let items = host.focusItems(in: host.bounds)
        let frames = items.map { item -> String in
            let r = item.frame
            let w = host.convert(r, to: nil)
            return "\(type(of: item)) win=\(NSCoder.string(for: w.integral)) env=\(item.parentFocusEnvironment.map { String(describing: type(of: $0)) } ?? "nil")"
        }
        let cellWin = cell.convert(cell.bounds, to: nil)
        let tree = focusTree(of: host).joined(separator: " | ")
        print("🌳 [\(tag)] S\(ip.section) \(tree)")
        print("🔬 [\(tag)] S\(ip.section) \(v) cell=\(NSCoder.string(for: cellWin.integral)) host=\(type(of: host)) items=\(items.count) " + frames.joined(separator: " ; "))
    }
}

// MARK: - Reflection dump (diagnostic only)

nonisolated(unsafe) private var dumpedStates = Set<Int>()

/// Dumps the stored properties of a hosting view (and its superclasses) once per `itemCount` value.
func dumpHostOnce(_ host: UIView, itemCount: Int) {
    guard !dumpedStates.contains(itemCount) else { return }
    dumpedStates.insert(itemCount)
    var lines: [String] = []
    var mirror: Mirror? = Mirror(reflecting: host)
    while let m = mirror {
        for child in m.children {
            var value = String(describing: child.value)
            if value.count > 160 { value = String(value.prefix(160)) + "…" }
            lines.append("\(m.subjectType).\(child.label ?? "?") = \(value)")
        }
        mirror = m.superclassMirror
    }
    print("🧬 items=\(itemCount) hidden=\(host.isHidden) alpha=\(host.alpha) win=\(host.window != nil)\n" + lines.map { "🧬 " + $0 }.joined(separator: "\n"))
}

// MARK: - Focus tree

/// Recursively walks the focus item tree under `env` (public API only) and describes leaves.
func focusTree(of env: UIFocusEnvironment, depth: Int = 0) -> [String] {
    guard depth < 8, let container = env.focusItemContainer else { return [] }
    var out: [String] = []
    for item in container.focusItems(in: CGRect(origin: .zero, size: CGSize(width: 100_000, height: 100_000)).offsetBy(dx: -50_000, dy: -50_000)) {
        if item === env { continue }
        out.append(String(repeating: "  ", count: depth) + "\(type(of: item)) canFocus=\(item.canBecomeFocused) frame=\(NSCoder.string(for: item.frame.integral))")
        out += focusTree(of: item, depth: depth + 1)
    }
    return out
}
