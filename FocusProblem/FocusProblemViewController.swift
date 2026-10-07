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
        if let mode = BenchConfig.mode, bench == nil {
            let label = "\(appSetting("FOCUS_LAYOUT") ?? "default") workaround=\(SwiftUIPassthroughCell.workaround.rawValue)"
            bench = BenchDriver(viewController: self, collectionView: collectionView, sections: sections, mode: mode, label: label)
            bench?.start()
        }
    }

    // MARK: - Bench

    private var bench: BenchDriver?
    var benchFocusTarget: IndexPath?

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        if let target = benchFocusTarget, let cell = collectionView.cellForItem(at: target) {
            return [cell]
        }
        return super.preferredFocusEnvironments
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
        debugLog("\(kDebugPrefix) shouldUpdateFocus: \(prev) → \(next) heading=\(heading)")
        return super.shouldUpdateFocus(in: context)
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        let prev = focusDescription(context.previouslyFocusedView, in: collectionView, sections: sections)
        let next = focusDescription(context.nextFocusedView, in: collectionView, sections: sections)
        debugLog("\(kDebugPrefix) didUpdateFocus: \(prev) → \(next)")
        debugLog(focusMarker(context.nextFocusedView, in: collectionView, sections: sections))
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

        // Jumbotron SwiftUI cell (UIHostingConfiguration) — cas d'origine du bug, corrigé par SwiftUIPassthroughCell
        let swiftUIJumbotronRegistration = UICollectionView.CellRegistration<SwiftUIPassthroughCell, Item> { cell, indexPath, _ in
            cell.contentConfiguration = UIHostingConfiguration {
                JumbotronSwiftUIView(
                    title: "Podcast \(indexPath.section) — SwiftUI (UIHostingConfiguration)",
                    description: "Embedded via UIHostingConfiguration + SwiftUIPassthroughCell workaround. Set WORKAROUND=off to see the original bug."
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

        // Jumbotron SwiftUI cell (UIHostingController, reused: only rootView replaced)
        let swiftUIHCReusedRegistration = UICollectionView.CellRegistration<HostingControllerReusedCell, Item> { [weak self] cell, indexPath, _ in
            cell.configure(
                rootView: JumbotronSwiftUIView(
                    title: "Podcast \(indexPath.section) — SwiftUI (UIHostingController · reused)",
                    description: "Embedded via a reused UIHostingController."
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
                return Perf.shared.measure("dequeue.jumbotron") { () -> UICollectionViewCell in
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
                case .hostingControllerReused:
                    return collectionView.dequeueConfiguredReusableCell(
                        using: swiftUIHCReusedRegistration, for: indexPath, item: item
                    )
                }
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

// MARK: - UICollectionViewDelegate

extension FocusProblemViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let cell = cell as? SwiftUIPassthroughCell else { return }
        Perf.shared.measure("delegate.willDisplay") { cell.willDisplay() }
    }

    func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let cell = cell as? SwiftUIPassthroughCell else { return }
        Perf.shared.measure("delegate.didEndDisplaying") { cell.didEndDisplaying() }
    }
}
