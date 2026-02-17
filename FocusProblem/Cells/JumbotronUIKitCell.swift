import UIKit

final class JumbotronUIKitCell: UICollectionViewCell {

    private let containerView = UIView()
    private let imageView = UIView()
    private let imageIcon = UIImageView()
    private let titleLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let buttonStack = UIStackView()
    private var buttons: [UIButton] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var canBecomeFocused: Bool { false }

    // MARK: - Setup

    private func setupViews() {
        // Container
        containerView.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        containerView.layer.cornerRadius = 20
        containerView.clipsToBounds = true
        containerView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(containerView)

        // Image placeholder
        imageView.backgroundColor = UIColor.systemTeal.withAlphaComponent(0.4)
        imageView.layer.cornerRadius = 16
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(imageView)

        imageIcon.image = UIImage(systemName: "headphones")
        imageIcon.tintColor = UIColor.white.withAlphaComponent(0.6)
        imageIcon.contentMode = .scaleAspectFit
        imageIcon.translatesAutoresizingMaskIntoConstraints = false
        imageView.addSubview(imageIcon)

        // Title
        titleLabel.font = .systemFont(ofSize: 38, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(titleLabel)

        // Buttons
        buttonStack.axis = .horizontal
        buttonStack.spacing = 20
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(buttonStack)

        let buttonConfigs: [(String, String, UIColor)] = [
            ("Play", "play.fill", .systemBlue),
            ("Favorite", "heart.fill", .systemPink),
            ("Info", "info.circle.fill", .systemGray)
        ]

        for (title, icon, color) in buttonConfigs {
            let button = makeButton(title: title, icon: icon, color: color)
            buttonStack.addArrangedSubview(button)
            buttons.append(button)
        }

        // Description
        descriptionLabel.font = .systemFont(ofSize: 20)
        descriptionLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        descriptionLabel.numberOfLines = 3
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(descriptionLabel)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            imageView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 40),
            imageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 40),
            imageView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -40),
            imageView.heightAnchor.constraint(equalToConstant: 300),

            imageIcon.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
            imageIcon.centerYAnchor.constraint(equalTo: imageView.centerYAnchor),
            imageIcon.widthAnchor.constraint(equalToConstant: 80),
            imageIcon.heightAnchor.constraint(equalToConstant: 80),

            titleLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 40),
            titleLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -40),

            buttonStack.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 20),
            buttonStack.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 40),

            descriptionLabel.topAnchor.constraint(equalTo: buttonStack.bottomAnchor, constant: 20),
            descriptionLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 40),
            descriptionLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -40),
            descriptionLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -40)
        ])
    }

    private func makeButton(title: String, icon: String, color: UIColor) -> UIButton {
        let button = UIButton(type: .system)
        let image = UIImage(systemName: icon)
        button.setImage(image, for: .normal)
        button.setTitle("  \(title)", for: .normal)
        button.tintColor = .white
        button.backgroundColor = color.withAlphaComponent(0.3)
        button.layer.cornerRadius = 12
        button.contentEdgeInsets = UIEdgeInsets(top: 14, left: 24, bottom: 14, right: 24)
        button.titleLabel?.font = .systemFont(ofSize: 22, weight: .semibold)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
        return button
    }

    // MARK: - Configure

    func configure(title: String, description: String) {
        titleLabel.text = title
        descriptionLabel.text = description
    }
}
