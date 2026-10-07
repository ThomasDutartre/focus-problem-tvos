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
