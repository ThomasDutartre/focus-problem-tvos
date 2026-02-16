# UIHostingConfiguration — Focus Bug on tvOS

## Context

On tvOS, a `UICollectionView` contains cells hosting SwiftUI content (focusable buttons) via two approaches:
- **`UIHostingController`** (classic view controller containment)
- **`UIHostingConfiguration`** (modern API, iOS 16+ / tvOS 16+)

The goal: focus should land on the **individual SwiftUI buttons** inside the cell (not the cell itself), and the user should be able to navigate freely between sections.

## The Problem

With `UIHostingConfiguration`, after navigating focus in and out of the section (e.g. down from a UIKit section, then the focus engine ejects it), the SwiftUI section becomes **permanently unfocusable**. The focus engine never "sees" it again.

### Reproduced sequence (with `-UIFocusLoggingEnabled YES` + custom prints)

```
1. User presses DOWN from Section 2 (Jumbotron UIKit)
   🐛 shouldUpdateFocus: UIButton [Section 2] → UIHostingContentView [Section 3]  heading=Down
   → Focus ENTERS Section 3 (UIHostingConfiguration) ✓

2. Focus system immediately reports "disappearing focus environments"
   for UIKitFocusSectionResponderItem & UIKitContainerFocusResponderItem
   ⚠️ 6 "Ignoring focus update request for disappearing focus environment" in cascade

3. Focus exits to nil — NO user input occurred
   🐛 SwiftUIPassthroughCell.didUpdateFocus: UIHostingContentView → nil
   🐛 didUpdateFocus: UIHostingContentView [Section 3] → nil

4. FocusableButton 'Info' flashes isFocused true → false
   🐛 FocusableButton 'Info' isFocused → true   (during "disappearing" cascade)
   🐛 FocusableButton 'Info' isFocused → false   (immediately after)

5. Focus engine searches for a new focusable item
   🐛 SwiftUIPassthroughCell.preferredFocusEnvironments → [3x _UIInheritedView]
   🐛 SwiftUIPassthroughCell.canBecomeFocused → false
   🐛 HostingControllerCell.preferredFocusEnvironments → hostingController.view

6. Apple's preferred focus search visits the UIHostingContentView and all subviews:
   |  ├ <SwiftUI._UIInheritedView>  → (warning) No focusable items found.
   |  ├ <SwiftUI._UIInheritedView>  → (warning) No focusable items found.
   |  ├ <SwiftUI._UIInheritedView>  → (warning) No focusable items found.
   |  └ <UIHostingContentView>      → (warning) No focusable items found.
   |  === unable to find focused item in context. retrying with updated request. ===

7. Retry lands on HostingControllerCell (UIHostingController) — "It's focusable!"
   🐛 HostingControllerCell.didUpdateFocus: nil → _UIHostingView<AnyView>
   🐛 didUpdateFocus: nil → _UIHostingView [Section 1 — UIHostingController]
   → Focus BUMPS to Section 1

8. From this point, Section 3 is DEAD:
   Focus skips from Section 2 → Section 4, ignoring Section 3 entirely.
   canBecomeFocused is queried repeatedly on SwiftUIPassthroughCell → false,
   but the focus engine never attempts to explore its virtual items again.
```

### Root cause

The `UIHostingContentView` (Apple's private internal view) manages **"virtual focus items"** — SwiftUI focusable elements invisible to UIKit. After a specific navigation cycle, these virtual items are **deregistered and never re-registered**. The UIKit focus engine can no longer find any focusable items in the cell.

The Apple focus logs reveal a **`mismatched parentFocusEnvironment`** error on all virtual focus items just before the bug triggers. The items report their `parentFocusEnvironment` as the `_UIHostingView` (from UIHostingController in another section), but their `focusItemContainer` points to a different `UIKitFocusSectionResponderItem`. This hierarchy corruption causes the focus engine to mark all environments as "disappearing".

With `UIHostingController`, this does not happen because the hosting controller is a proper **`UIFocusEnvironment`** in the UIKit hierarchy — UIKit can traverse it via `preferredFocusEnvironments`, and the hosting controller correctly maintains its virtual focus items across navigation cycles.

## Test environment

- **POC**: `FocusProblem` — `UICollectionView` + `CompositionalLayout` + `DiffableDataSource`
- **Architecture**: `UITabBarController` → `UINavigationController` → `FocusProblemViewController`
- **5 sections**:
  - Section 0: Cards SwiftUI (UIHostingConfiguration) — simple focusable cells, focus works via `@Environment(\.isFocused)`
  - Section 1: Jumbotron SwiftUI (UIHostingController) — focus works correctly
  - Section 2: Jumbotron UIKit — focus works correctly
  - Section 3: Jumbotron SwiftUI (UIHostingConfiguration) — **BUG: focus permanently broken**
  - Section 4: Cards UIKit — focus works correctly
- **`remembersLastFocusedIndexPath = false`** (true causes a separate focus trap)
- **`-UIFocusLoggingEnabled YES`** launch argument for system focus logs

## Key finding: `@Environment(\.isFocused)` works with UIHostingConfiguration

For **simple cells** (single focusable item = the cell itself), `UIHostingConfiguration` works fine. The cell is focusable by default, and `@Environment(\.isFocused)` auto-propagates from the UIKit cell's focus state to the SwiftUI view. No `configurationUpdateHandler`, no `@FocusState`, no `.focusable()` needed.

This was confirmed by runtime logs: only `@Environment(\.isFocused)` fires when the cell gains/loses focus. `configurationUpdateHandler` with `state.isFocused` does NOT fire for focus changes. `@FocusState` does NOT react either.

**The bug only occurs when the cell contains multiple focusable SwiftUI elements** (e.g. buttons) and `canBecomeFocused` returns `false` on the cell to let focus pass through to the SwiftUI content.

## Hypotheses tested

### H1 — `preferredFocusEnvironments` on the cell → REJECTED

**Idea**: Override `preferredFocusEnvironments` on `SwiftUIPassthroughCell` to point to the internal `UIHostingContentView`, as done with `UIHostingController`.

**Result**: The method is called and returns the correct `UIHostingContentView`, but focus still exits to `nil` after ~30ms. The `UIHostingContentView` does not re-expose its virtual items even when the focus engine is explicitly redirected to it.

### H2 — UIHostingContentView removed from view hierarchy → REJECTED

**Idea**: Cell recycling (`prepareForReuse`) or scrolling removes the `UIHostingContentView` from the view hierarchy.

**Result**: `layoutSubviews` logs and pointer verification show that the `UIHostingContentView` remains **always present** in `contentView.subviews` with the same pointer. The view doesn't disappear — its internal focus state is corrupted.

### H3 — `.focusSection()` creates a conflict → REJECTED

**Idea**: The `.focusSection()` modifier on the SwiftUI content interferes with the cell's focus system.

**Result**: Removing `.focusSection()` makes the section inaccessible from the first attempt (the focus engine can't find the boundaries of the SwiftUI buttons). The modifier is **required**, not the cause.

### H4 — Virtual items not re-registered after nil transition → CONFIRMED (mechanism)

**Idea**: The `UIHostingContentView` does not re-scan/re-register its virtual focus items after focus exits to `nil`.

**Result**: This is the core mechanism of the bug. After the `→ nil` transition, the `UIHostingContentView` no longer provides any focus item to the focus engine. Logs show `canBecomeFocused` is queried in a loop on the cell (returns `false`), but the focus engine no longer attempts to explore the internal virtual items. Apple's focus search explicitly reports `(warning) No focusable items found.` on the `UIHostingContentView` and all its `_UIInheritedView` subviews.

### H5 — `setNeedsFocusUpdate()` to force a rescan → REJECTED

**Idea**: Call `setNeedsFocusUpdate()` + `updateFocusIfNeeded()` on the cell/collection view to force the focus engine to rescan.

**Result**: The rescan is triggered but finds nothing — virtual items remain deregistered. The rescan traverses the existing hierarchy; it does not force `UIHostingContentView` to re-create its items.

### H6 — Force a UIKit redraw → REJECTED

**Idea**: The problem is a corrupted render state. Forcing `setNeedsLayout()` / `layoutIfNeeded()` / `setNeedsDisplay()` on the cell and `UIHostingContentView` could trigger a refresh.

**Result**: Layout methods are called (confirmed by `layoutSubviews` logs), but the internal focus state in `UIHostingContentView` is not tied to layout. UIKit redraw does not touch the virtual focus items registry.

### H7 — Remove SwiftUI visual effects (scaleEffect, animation) → REJECTED

**Idea**: SwiftUI animations (`scaleEffect`, `animation`) tied to `@FocusState` interfere with the focus system during the `true → false` flash.

**Result**: Without any visual effects, the behavior is strictly identical. The `isFocused true → false` flash still occurs, followed by the transition to `nil`. Visual effects are cosmetic, not causal.

### H8 — `canFocusItemAt:` delegate instead of cell subclass → REJECTED

**Idea**: Use `UICollectionViewDelegate.canFocusItemAt:` (returning `false`) instead of `canBecomeFocused = false` on the cell. The focus engine makes the decision at a different level.

**Result**: Identical sequence in logs. The delegate `canFocusItemAt:` is evaluated at the same point as `canBecomeFocused` in the focus engine's decision tree for this case. The internal `UIHostingContentView` bug is identical — the source of the decision (collection view vs cell) makes no difference.

### H9 — `remembersLastFocusedIndexPath = true` + `canFocusItemAt:` delegate → REJECTED

**Idea**: Combine `remembersLastFocusedIndexPath = true` with `canFocusItemAt: false` for SwiftUI sections. The collection view would not memorize the SwiftUI cell, and the focus engine would take a different path when `remembers` is active.

**Result**: `remembersLastFocusedIndexPath = true` bypasses the `canFocusItemAt:` delegate — focus is restored directly into the `UIHostingView`/`UIHostingController` hierarchy, without going through the delegate. Result: **focus trap** in the UIHostingController section. `remembersLastFocusedIndexPath = true` is fundamentally incompatible with any cell containing focusable SwiftUI on tvOS.

### H10 — `configurationUpdateHandler` + `setNeedsUpdateConfiguration()` → REJECTED

**Idea**: Use `configurationUpdateHandler` instead of assigning `contentConfiguration` directly. Call `setNeedsUpdateConfiguration()` in the `didUpdateFocusIn` delegate to force a **complete rebuild** of `UIHostingConfiguration` on every focus change. This should recreate the `UIHostingContentView` and re-register the virtual items.

**Result**: The handler executes correctly (~15+ times during testing), the configuration is rebuilt on each call. But despite the complete rebuild, the `UIHostingContentView` still deregisters its virtual items after the `→ nil` transition. Recreating the configuration is not enough — the bug is in how `UIHostingContentView` manages its internal focus state, not in the configuration itself.

## Working solution

**`UIHostingController`** via a custom cell (`HostingControllerCell`):

```swift
final class HostingControllerCell: UICollectionViewCell {
    private var hostingController: UIHostingController<AnyView>?

    override var canBecomeFocused: Bool { false }

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        if let hcView = hostingController?.view { return [hcView] }
        return super.preferredFocusEnvironments
    }

    func configure<V: View>(with view: V, parent: UIViewController?) {
        // UIViewController containment: addChild, didMove(toParent:)
        // ...
    }
}
```

**Why it works**: `UIHostingController` is a full `UIFocusEnvironment` in the UIKit hierarchy. The focus engine can traverse it via `preferredFocusEnvironments`, and the hosting controller correctly maintains its virtual focus items across navigation cycles.

**Constraints**:
- `remembersLastFocusedIndexPath = false` (mandatory)
- `preferredFocusEnvironments` pointing to `hostingController.view` (mandatory for upward navigation)
- Proper UIViewController containment (`addChild` / `didMove(toParent:)`)

## Recommendation

File an Apple Feedback with the title:

> **UIHostingConfiguration: virtual focus items permanently deregistered after focus cycle on tvOS when cell's canBecomeFocused returns false**

Include: tvOS version, the 10 tested hypotheses, the `-UIFocusLoggingEnabled YES` logs showing `(warning) No focusable items found.` and `mismatched parentFocusEnvironment`, and note that the problem does NOT occur with `UIHostingController` for the same SwiftUI content. Reference WWDC22 session 10072.
