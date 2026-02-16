import UIKit

// MARK: - Section Header

final class SectionHeaderView: UICollectionReusableView {
    
    private let titleLabel = UILabel()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
    
    func configure(title: String) {
        titleLabel.text = title
    }
}
