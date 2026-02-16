import UIKit

// MARK: - Debug Helpers

public let kDebugPrefix = "🐛 [FocusProblem]"

public func focusDescription(_ view: UIView?, in collectionView: UICollectionView?) -> String {
    let typeName = view.map { String(describing: type(of: $0)) } ?? "nil"
    let ptr = view.map { String(format: "%p", unsafeBitCast($0, to: Int.self)) } ?? ""
    
    guard let view, let cv = collectionView else {
        return "\(typeName) \(ptr)"
    }
    
    // Walk up to find the cell
    var current: UIView? = view
    while let v = current {
        if let cell = v as? UICollectionViewCell, let ip = cv.indexPath(for: cell) {
            let section = Section(rawValue: ip.section)?.title ?? "s\(ip.section)"
            return "\(typeName) \(ptr) [\(section), item \(ip.item)]"
        }
        current = v.superview
    }
    return "\(typeName) \(ptr)"
}
