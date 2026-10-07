import UIKit
import SwiftUI

// MARK: - View Controller

final class FocusProblemViewController: UIViewController {

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private let sections: [Section] = PageLayout.current().enumerated().map { Section(index: $0.offset, kind: $0.element) }

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
        let prev = focusDescription(context.previouslyFocusedView, in: collectionView, sections: sections)
        let next = focusDescription(context.nextFocusedView, in: collectionView, sections: sections)
        let heading = context.focusHeading
        print("\(kDebugPrefix) shouldUpdateFocus: \(prev) → \(next) heading=\(heading)")
        probeFocusItems(in: collectionView, sections: sections, tag: "should")
        return super.shouldUpdateFocus(in: context)
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        let prev = focusDescription(context.previouslyFocusedView, in: collectionView, sections: sections)
        let next = focusDescription(context.nextFocusedView, in: collectionView, sections: sections)
        print("\(kDebugPrefix) didUpdateFocus: \(prev) → \(next)")
        print(focusMarker(context.nextFocusedView, in: collectionView, sections: sections))
        probeFocusItems(in: collectionView, sections: sections, tag: "didUpdate")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.runRemedyExperiment()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self else { return }
            probeFocusItems(in: self.collectionView, sections: self.sections, tag: "+1s")
        }
    }

    // MARK: - Collection View Setup

    private func setupCollectionView() {
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: createLayout())
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        view.addSubview(collectionView)
        collectionView.remembersLastFocusedIndexPath = false
        collectionView.delegate = self

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    // MARK: - Layout

    private func createLayout() -> UICollectionViewCompositionalLayout {
        let sections = sections
        return UICollectionViewCompositionalLayout { sectionIndex, environment in
            guard sections.indices.contains(sectionIndex) else { return nil }

            switch sections[sectionIndex].kind {
            case .cardsUIKit, .cardsSwiftUI:
                return CardSection.makeCardsSection()
            case .jumbotron:
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
        let uikitJumbotronRegistration = UICollectionView.CellRegistration<JumbotronUIKitCell, Item> { cell, indexPath, _ in
            cell.configure(
                title: "Podcast \(indexPath.section) — UIKit",
                description: "UIKit jumbotron with UIButton. Focus enters and exits normally. Navigate up/down to verify."
            )
        }

        // Jumbotron SwiftUI cell (UIHostingConfiguration) — cas d'origine du bug
        let swiftUIJumbotronRegistration = UICollectionView.CellRegistration<SwiftUIPassthroughCell, Item> { cell, indexPath, _ in
            cell.contentConfiguration = UIHostingConfiguration {
                JumbotronSwiftUIView(
                    title: "Podcast \(indexPath.section) — SwiftUI (UIHostingConfiguration)",
                    description: "Embedded via UIHostingConfiguration. Focus becomes permanently broken after a navigation cycle."
                )
            }
            .margins(.all, 0)
        }

        // Jumbotron SwiftUI cell (UIHostingConfiguration) — view stored & re-applied on reuse
        let swiftUIJumbotronRegistrationBis = UICollectionView.CellRegistration<SwiftUIResetPassthroughCell, Item> { cell, indexPath, _ in
            cell.configure(
                with: JumbotronSwiftUIView(
                    title: "Podcast \(indexPath.section) — SwiftUI (UIHostingConfiguration · reset on reuse)",
                    description: "Embedded via UIHostingConfiguration. The SwiftUI view is stored and re-applied to contentConfiguration on every reuse."
                )
            )
        }

        // Jumbotron SwiftUI cell (UIHostingController)
        let swiftUIHCRegistration = UICollectionView.CellRegistration<HostingControllerCell, Item> { [weak self] cell, indexPath, _ in
            cell.configure(
                rootView: JumbotronSwiftUIView(
                    title: "Podcast \(indexPath.section) — SwiftUI (UIHostingController)",
                    description: "Embedded via UIHostingController. Focus works correctly."
                ),
                parentViewController: self
            )
        }

        let sections = sections
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) {
            collectionView, indexPath, item in
            switch item {
            case .card:
                if sections[indexPath.section].kind == .cardsSwiftUI {
                    return collectionView.dequeueConfiguredReusableCell(
                        using: swiftUICardRegistration, for: indexPath, item: item
                    )
                }
                return collectionView.dequeueConfiguredReusableCell(
                    using: uikitCardRegistration, for: indexPath, item: item
                )
            case .jumbotron(_, let variant):
                switch variant {
                case .uikit:
                    return collectionView.dequeueConfiguredReusableCell(
                        using: uikitJumbotronRegistration, for: indexPath, item: item
                    )
                case .hostingConfiguration:
                    return collectionView.dequeueConfiguredReusableCell(
                        using: swiftUIJumbotronRegistration, for: indexPath, item: item
                    )
                case .hostingConfigurationReset:
                    return collectionView.dequeueConfiguredReusableCell(
                        using: swiftUIJumbotronRegistrationBis, for: indexPath, item: item
                    )
                case .hostingController:
                    return collectionView.dequeueConfiguredReusableCell(
                        using: swiftUIHCRegistration, for: indexPath, item: item
                    )
                }
            }
        }

        // Header registration
        let headerRegistration = UICollectionView.SupplementaryRegistration<SectionHeaderView>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { header, _, indexPath in
            header.configure(title: sections[indexPath.section].title)
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
        snapshot.appendSections(sections)
        for section in sections {
            switch section.kind {
            case .cardsUIKit, .cardsSwiftUI:
                snapshot.appendItems(
                    (0..<10).map { Item.card(id: $0, section: section.index) },
                    toSection: section
                )
            case .jumbotron(let variant):
                snapshot.appendItems([.jumbotron(section: section.index, variant: variant)], toSection: section)
            }
        }
        dataSource.apply(snapshot, animatingDifferences: false)
    }
}

// MARK: - Remedy experiments (REMEDY env var)

extension FocusProblemViewController: UICollectionViewDelegate {
    func runRemedyExperiment() {
        let remedy = ProcessInfo.processInfo.environment["REMEDY"] ?? "none"
        for case let cell as SwiftUIPassthroughCell in collectionView.visibleCells where !cell.hostedFocusItemsReady {
            let ip = collectionView.indexPath(for: cell).map { "S\($0.section)" } ?? "?"
            switch remedy {
            case "updateConfig": cell.setNeedsUpdateConfiguration()
            case "layout": cell.contentView.setNeedsLayout(); cell.contentView.layoutIfNeeded()
            case "intrinsic": cell.contentView.invalidateIntrinsicContentSize()
            case "reassign": let c = cell.contentConfiguration; cell.contentConfiguration = c
            case "rebuild": let c = cell.contentConfiguration; cell.contentConfiguration = nil; cell.contentConfiguration = c
            default: break
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                print("💊 \(ip) remedy=\(remedy) leavesAfter=\(cell.hostedFocusItemsReady)")
            }
        }
    }
}
