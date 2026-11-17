# Backlog of untested hypotheses

Priority order. Before taking one, check in `focus-invest.md` that it doesn't already have an H<n> entry. Add here any new lead revealed by the logs, with its justification.

Key fact (2026-11-09, tvOS 27.2): in the baseline, S3 and S3b are skipped from the very first Down — the SwiftUI buttons are invisible to the focus engine from the start, not only after an ejection. Prefer leads that explain that.

Update (first `[FOCUS]` baseline, same day): ejections happen exactly when focus enters a SwiftUI cell that is (re)entering the screen (`display` logged right before `→ nil`); a cell that stays on screen is stable. → Lead 0 below.

Update 2 (H15 run): off-screen cells are kept with `isHidden = true`; every ejection happens when focus enters a hidden SwiftUI cell, at un-hide. S1 survives because it gets a brand-new hosting view at each configure. → H16 (never hide S3); if confirmed, look for a shippable way to get the same effect (e.g. fresh content configuration on `willDisplay`, or UIHostingController like S1).

## 0. Cell re-configuration on display — done (H14, REJECTED: ejections happen with no configure/reuse in between)
- **Suspected mechanism**: when the cell comes back on screen it is dequeued, the registration handler re-assigns `contentConfiguration`, SwiftUI rebuilds its virtual focus items while focus is moving in → ejection, then permanent loss. `[UNSOURCED]`.
- **Change (H14)**: in the S3 registration, skip re-assigning `contentConfiguration` when the cell already has one. S3b untouched (control).
- **Signature if true**: S3 entries stable even right after `display S3`; `configure S3 … skipped (H14)` lines; S3b still breaks.
- **Follow-ups if partial**: `reconfigureItems` instead of reload; keep cells alive (no reuse) for SwiftUI jumbotrons.

Already rejected (don't redo as is): H1 `preferredFocusEnvironments` → UIHostingContentView · H2 view removed from hierarchy · H3 removing `.focusSection()` · H5 `setNeedsFocusUpdate` · H6 forced redraw/layout · H7 removing scaleEffect/animation · H8 `canFocusItemAt:` · H9 `remembersLastFocusedIndexPath = true` · H10 `configurationUpdateHandler` rebuild · H11 pure UIKit app · H12 reset in `prepareForReuse` (partial) · H13 `selfSizingInvalidation = .disabled` · H14 skip re-configuration of the S3 cell · H15 remove the `preferredFocusEnvironments` override.

## 1. Self-sizing invalidation — variant a done (H13, REJECTED)
- **Suspected mechanism**: `.estimated(500)` height (`JumbotronSection`) + `UIHostingConfiguration` invalidates the cell size when SwiftUI state changes (`@FocusState`, `@Environment(\.isFocused)`) → the collection view relays out the cell during the focus update → environments flagged as "disappearing". `[UNSOURCED]` until proven.
- **Variant a**: `collectionView.selfSizingInvalidation = .disabled` (tvOS 16+).
- **Variant b** (separate hypothesis): `.absolute(<measured height>)` height for section 3.
- **Signature if true**: no more `disappearing` nor `→ nil` ejection after entering; stable entries.

## 2. Interference with section 1 (UIHostingController)
- **Suspected mechanism**: `mismatched parentFocusEnvironment` points to the `_UIHostingView` of another section; two neighboring SwiftUI hosts may confuse the focus hierarchy.
- **Change**: snapshot without sections `.cardsSwiftUI` and `.jumbotronSwiftUIHC` (keep 2, 3, 4).
- **Signature if true**: no more `mismatched parentFocusEnvironment`, section 3 stable. If false: same cascade, bounce to section 2 or 4 instead of 1.

## 3. `preferredFocusEnvironments` override in `SwiftUIPassthroughCell` — done (H15, REJECTED)
- **Suspected mechanism**: it returns `contentView.subviews` (private `_UIInheritedView`s), unlike H1; pointing the focus engine at these views may disturb the search.
- **Change**: return `super.preferredFocusEnvironments` (default behavior).

## 4. `.buttonStyle(.card)`
- **Suspected mechanism**: on tvOS the card style relies on platform views; H7 removed effects but not the style.
- **Change**: `.buttonStyle(.plain)`; separate variant: custom `ButtonStyle` or `.focusable()` + `onTapGesture`.

## 5. Secondary leads (justify from logs before taking them)
- `.focusScope` / `.prefersDefaultFocus` / `.defaultFocus` on the `HStack`.
- `UIFocusGuide` covering the cell, `preferredFocusEnvironments` → guide.
- Cell height frozen during the focus animation (`.scaleEffect` outside layout already checked in H7).
