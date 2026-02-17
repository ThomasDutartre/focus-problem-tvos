import UIKit
import SwiftUI

// MARK: - View Controller

final class FocusProblemViewController: UIViewController {
    
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCollectionView()
        setupDataSource()
        applySnapshot()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        setContentScrollView(collectionView, for: .top)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        setContentScrollView(nil, for: .top)
    }

    // MARK: - Focus Debug Logging

    override func shouldUpdateFocus(in context: UIFocusUpdateContext) -> Bool {
        let prev = focusDescription(context.previouslyFocusedView, in: collectionView)
        let next = focusDescription(context.nextFocusedView, in: collectionView)
        let heading = context.focusHeading
        print("\(kDebugPrefix) shouldUpdateFocus: \(prev) → \(next) heading=\(heading)")
        return super.shouldUpdateFocus(in: context)
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        let prev = focusDescription(context.previouslyFocusedView, in: collectionView)
        let next = focusDescription(context.nextFocusedView, in: collectionView)
        print("\(kDebugPrefix) didUpdateFocus: \(prev) → \(next)")
    }

    // MARK: - Collection View Setup
    
    private func setupCollectionView() {
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: createLayout())
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        view.addSubview(collectionView)
        collectionView.remembersLastFocusedIndexPath = false

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    // MARK: - Layout
    
    private func createLayout() -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { sectionIndex, environment in
            guard let section = Section(rawValue: sectionIndex) else { return nil }
            
            switch section {
            case .cardsUIKit, .cardsSwiftUI:
                return CardSection.makeCardsSection()
            case .jumbotronUIKit, .jumbotronSwiftUI, .jumbotronSwiftUIHC:
                return JumbotronSection.makeJumbotronSection()
            }
        }
    }
    
    // MARK: - Data Source
    
    private func setupDataSource() {
        // UIKit card cell
        let uikitCardRegistration = UICollectionView.CellRegistration<CardUIKitCell, Item> { cell, _, item in
            if case let .card(id, _) = item {
                cell.configure(title: "Card \(id)")
            }
        }
        
        // SwiftUI card cell — focus detected via @Environment(\.isFocused)
        let swiftUICardRegistration = UICollectionView.CellRegistration<UICollectionViewCell, Item> { cell, _, item in
            guard case let .card(id, _) = item else { return }
            cell.contentConfiguration = UIHostingConfiguration {
                CardSwiftUIView(title: "Card \(id)")
            }
            .margins(.all, 0)
        }
        
        // Jumbotron UIKit cell
        let uikitJumbotronRegistration = UICollectionView.CellRegistration<JumbotronUIKitCell, Item> { cell, _, _ in
            cell.configure(
                title: "Podcast — UIKit",
                description: "UIKit jumbotron with UIButton. Focus enters and exits normally. Navigate up/down to verify."
            )
        }
        
        // Jumbotron SwiftUI cell (UIHostingConfiguration)
        let swiftUIJumbotronRegistration = UICollectionView.CellRegistration<SwiftUIPassthroughCell, Item> { cell, _, _ in
            cell.contentConfiguration = UIHostingConfiguration {
                JumbotronSwiftUIView(
                    title: "Podcast — SwiftUI (UIHostingConfiguration)",
                    description: "Embedded via UIHostingConfiguration. Focus becomes permanently broken after a navigation cycle."
                )
            }
            .margins(.all, 0)
        }
        
        // Jumbotron SwiftUI cell (UIHostingController)
        let swiftUIHCRegistration = UICollectionView.CellRegistration<HostingControllerCell, Item> { [weak self] cell, _, _ in
            cell.configure(
                rootView: JumbotronSwiftUIView(
                    title: "Podcast — SwiftUI (UIHostingController)",
                    description: "Embedded via UIHostingController. Focus works correctly."
                ),
                parentViewController: self
            )
        }
        
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) {
            collectionView, indexPath, item in
            let section = Section(rawValue: indexPath.section)
            switch item {
            case .card:
                if section == .cardsSwiftUI {
                    return collectionView.dequeueConfiguredReusableCell(
                        using: swiftUICardRegistration, for: indexPath, item: item
                    )
                }
                return collectionView.dequeueConfiguredReusableCell(
                    using: uikitCardRegistration, for: indexPath, item: item
                )
            case .jumbotronUIKit:
                return collectionView.dequeueConfiguredReusableCell(
                    using: uikitJumbotronRegistration, for: indexPath, item: item
                )
            case .jumbotronSwiftUI:
                return collectionView.dequeueConfiguredReusableCell(
                    using: swiftUIJumbotronRegistration, for: indexPath, item: item
                )
            case .jumbotronSwiftUIHC:
                return collectionView.dequeueConfiguredReusableCell(
                    using: swiftUIHCRegistration, for: indexPath, item: item
                )
            }
        }
        
        // Header registration
        let headerRegistration = UICollectionView.SupplementaryRegistration<SectionHeaderView>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { header, _, indexPath in
            let section = Section(rawValue: indexPath.section)
            header.configure(title: section?.title ?? "")
        }
        
        dataSource.supplementaryViewProvider = { collectionView, kind, indexPath in
            collectionView.dequeueConfiguredReusableSupplementary(
                using: headerRegistration, for: indexPath
            )
        }
    }
    
    // MARK: - Snapshot
    
    private func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections(Section.allCases)
        
        // Section 0 — SwiftUI cards (UIHostingConfiguration)
        snapshot.appendItems(
            (0..<10).map { Item.card(id: $0, section: 0) },
            toSection: .cardsSwiftUI
        )
        
        // Section 1 — Jumbotron SwiftUI (UIHostingController)
        snapshot.appendItems([.jumbotronSwiftUIHC], toSection: .jumbotronSwiftUIHC)
        
        // Section 2 — Jumbotron UIKit
        snapshot.appendItems([.jumbotronUIKit], toSection: .jumbotronUIKit)
        
        // Section 3 — Jumbotron SwiftUI (UIHostingConfiguration)
        snapshot.appendItems([.jumbotronSwiftUI], toSection: .jumbotronSwiftUI)
        
        // Section 4 — UIKit cards
        snapshot.appendItems(
            (0..<10).map { Item.card(id: $0, section: 4) },
            toSection: .cardsUIKit
        )
        
        dataSource.apply(snapshot, animatingDifferences: false)
    }
}
