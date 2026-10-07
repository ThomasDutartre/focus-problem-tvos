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

> **Update (H13–H19):** the analysis below was refined — see [Root cause (refined)](#root-cause-refined). The `mismatched parentFocusEnvironment` warnings are a red herring: they are also emitted for the `UIHostingController` section, which works.

The `UIHostingContentView` (Apple's private internal view) manages **"virtual focus items"** — SwiftUI focusable elements invisible to UIKit. After a specific navigation cycle, these virtual items are **deregistered and never re-registered**. The UIKit focus engine can no longer find any focusable items in the cell.

The Apple focus logs reveal a **`mismatched parentFocusEnvironment`** error on all virtual focus items just before the bug triggers. The items report their `parentFocusEnvironment` as the `_UIHostingView` (from UIHostingController in another section), but their `focusItemContainer` points to a different `UIKitFocusSectionResponderItem`. This hierarchy corruption causes the focus engine to mark all environments as "disappearing".

With `UIHostingController`, this does not happen because the hosting controller is a proper **`UIFocusEnvironment`** in the UIKit hierarchy — UIKit can traverse it via `preferredFocusEnvironments`, and the hosting controller correctly maintains its virtual focus items across navigation cycles.

## Test environment

- **POC**: `FocusProblem` — `UICollectionView` + `CompositionalLayout` + `DiffableDataSource`
- **Architecture**: `UITabBarController` → `UINavigationController` → `FocusProblemViewController`
- **6 sections** (default layout):
  - Section 0: Cards SwiftUI (UIHostingConfiguration) — simple focusable cells, focus works via `@Environment(\.isFocused)`
  - Section 1: Jumbotron SwiftUI (UIHostingController) — focus works correctly
  - Section 2: Jumbotron UIKit — focus works correctly
  - Section 3: Jumbotron SwiftUI (UIHostingConfiguration) — original bug, **fixed by the `SwiftUIPassthroughCell` workaround**
  - Section 3b: Jumbotron SwiftUI (UIHostingConfiguration, reset on reuse — H12)
  - Section 4: Cards UIKit — focus works correctly
- **Stress layout** (`FOCUS_LAYOUT=stress:<variant>`, variant = `hostingConfiguration`, `hostingController`, `hostingConfigurationReset`, `uikit`): 12 sections alternating UIKit sections and `<variant>` jumbotrons, so that a full top→bottom scroll recycles the cells.
- **`WORKAROUND=off`** disables the `SwiftUIPassthroughCell` workaround to reproduce the original bug.
- Both env vars are pre-declared (disabled) in the `FocusTrap` scheme.
- Every focus change prints a compact marker `🎯 S<section>#<item> <kind> (<focused view type>)`.
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

### H11 — Pure UIKit app entry point (remove root SwiftUI `UIHostingController`) → REJECTED

**Idea**: The `mismatched parentFocusEnvironment` could be caused by a conflict between the app's root SwiftUI `WindowGroup` (`@main` / `ContentView`, itself a root `UIHostingController`) and the `UIHostingConfiguration` inside the cells. By switching the app entry point to a pure UIKit lifecycle (`AppDelegate` + `SceneDelegate` setting the `UITabBarController` as `rootViewController`), the root SwiftUI hosting context is removed entirely.

**Implementation**: Disabled `@main` on `FocusProblemApp`, added `AppDelegate` / `SceneDelegate`, added a custom `Info.plist` with `UIApplicationSceneManifest` pointing to the `SceneDelegate`, and referenced it via `INFOPLIST_FILE` in `project.pbxproj`. (Note: a traditional `AppDelegate`-only setup fails on modern tvOS SDK with `UIScene life cycle is required` — a `SceneDelegate` is mandatory.)

**Result**: The exact same `mismatched parentFocusEnvironment` warnings and `Ignoring focus update request for ineligible environment` cascade appear, even with no root SwiftUI `UIHostingController` anywhere in the hierarchy. The bug is intrinsic to how `UIHostingConfiguration`/`UIHostingContentView` manages its virtual focus items — it is **not** caused by the app's root SwiftUI integration. Changes were reverted (back to SwiftUI `@main`).

### H12 — Reset the SwiftUI view on cell reuse (`prepareForReuse`) → PARTIAL / REJECTED

**Idea**: On `prepareForReuse()`, re-apply the `contentConfiguration` (a fresh `UIHostingConfiguration` with a new `JumbotronSwiftUIView` instance) to force `UIHostingContentView` to rebuild and re-register its virtual focus items.

**Implementation**: `SwiftUIResetPassthroughCell` stores the SwiftUI view and re-assigns the content configuration on reuse (`jumbotronSwiftUIReset` section, Section 3b). `canBecomeFocused = false`.

**Result**: Noticeably better than the plain `jumbotronSwiftUI` case — focus often works after a reuse cycle. But the behavior remains **non-deterministic**: it works, then stops working, then works again randomly after subsequent reuses. The same `mismatched parentFocusEnvironment` warnings still appear. Rebuilding on reuse mitigates but does not fix the underlying virtual-item deregistration bug, so it is not a reliable solution.

### H13 — `selfSizingInvalidation = .disabled` → REJECTED

**Idea**: `UIHostingConfiguration` cells auto-invalidate their size when SwiftUI content changes (focus → body re-evaluation → re-layout while focus lands).

**Result**: identical sequence. Not related to self-sizing.

### H14 — `automaticallyUpdatesContentConfiguration = false` → REJECTED

**Idea**: the cell's configuration state change (focus) re-applies the `UIHostingConfiguration` and recreates the focus items.

**Result**: identical sequence.

### H15 — Force `layoutIfNeeded()` when the focus engine reads the cell's items → REJECTED

**Idea**: the `UIHostingContentView` has not rendered yet when the focus engine queries it.

**Result**: `contentView.focusItems(in:)` still returns 0 items after a synchronous layout. Layout is not what gates the items.

### Diagnostic — focus items probe + reflection → ROOT CAUSE FOUND

A probe on every focus change (public API: `focusItemContainer` / `focusItems(in:)` / `canBecomeFocused`, walked recursively) + a `Mirror` dump of `UIHostingContentView` (diagnostic only) show:

1. **Lazy build**: `UIHostingContentView` has an internal `hasBeenVisible` flag. Until the cell has been on screen, the SwiftUI content is not built and **the cell exposes no focus item at all**. When the user navigates toward an off‑screen section, the focus engine materializes the cell (`_UIFocusPromiseItem`), finds nothing focusable, and **skips the section**. A `UIHostingController`'s `_UIHostingView` exposes its items even off screen — that's why it works.
2. **Stale items after disappear / reuse**: after the SwiftUI content went through `onDisappear` (cell scrolled off screen, or recycled with another content), the content view keeps exposing **stale focus items**. The focus engine enters one of them, the content re-appears / re-renders, the stale items are deregistered → `Ignoring focus update request for disappearing focus environment` → **focus `→ nil`**.
3. **Orphan containers**: in some of those cycles only the focus containers remain (`UIKitFocusSectionResponderItem`, `UIKitContainerFocusResponderItem<FocusStateBindingResponder>`) **without their focusable leaves** (`UIKitFocusableViewResponderItem`) — they never come back, even when the cell is fully on screen. This is the "permanently dead section".

In all cases, a **fresh** `UIHostingContentView` (configuration set to `nil` then re-applied) that is rendered while on screen registers its items correctly.

### H16 — Cell as focus placeholder while no SwiftUI item is exposed → CONFIRMED (part of the fix)

`canBecomeFocused` returns `true` only while the hosted content exposes no focusable item (recursive public-API walk). The focus engine stops skipping the section: focus lands on the cell, the collection view scrolls it on screen, SwiftUI builds its content, and focus is then forwarded with `setNeedsFocusUpdate()` + `updateFocusIfNeeded()` (`preferredFocusEnvironments = [contentView]`). Focus requests are ignored while the collection view scroll-animates, so the forward is retried every 50 ms until focus actually left the cell.

### H17 — Rebuild the hosted content when focus lands on the placeholder → CONFIRMED (part of the fix)

Fixes the "orphan containers" case (3): the placeholder rebuilds the `UIHostingContentView` so the leaves are registered again.

### H18 — Rebuild in `prepareForReuse` and in `didEndDisplaying` → CONFIRMED (part of the fix)

Fixes the "stale items" case (2). Rebuilding in `willDisplay` is **too late**: the focus engine enters the stale items of the off-screen cell before `willDisplay` is called. Rebuilding as soon as the cell leaves the screen (`collectionView(_:didEndDisplaying:forItemAt:)`) means an off-screen cell never exposes stale items — it is a placeholder until it is displayed again.

### H19 — `@Environment(\.isFocused)` in a `ButtonStyle` instead of `@FocusState` / `.buttonStyle(.plain)` instead of `.card` → REJECTED

Neither the `FocusState` binding nor the card button style is involved: identical behavior.

## Root cause (refined)

`UIHostingContentView` (behind `UIHostingConfiguration`) manages the lifecycle of its SwiftUI focus items according to the **display lifecycle of the cell**, not according to the focus engine's needs:
- it exposes **nothing** before the cell has been displayed (lazy content),
- it keeps exposing **stale** items after the content disappeared, which vanish as soon as focus enters them,
- it can end up with focus containers **without focusable leaves**, permanently.

The UIKit focus engine, which looks for focusable items in **off-screen** cells when navigating, therefore either skips the cell or loses focus (`→ nil`). `UIHostingController` doesn't have this lazy behavior.

## Solutions

Validated on the tvOS simulator with the remote (stress layout, 12 sections, recycling): full top→bottom→top cycles, slow (0.7 s) and fast (0.2 s) presses → **0 `nil`, 0 skipped section, focus always ends on the SwiftUI buttons**, for both recommended solutions below. Without the workaround (`WORKAROUND=off`), the same scenario skips 4 of the 6 SwiftUI sections on the first sweep.

### Solution A — `UIHostingConfiguration` + `SwiftUIPassthroughCell` workaround (v2, public API only)

See [SwiftUIPassthroughCell.swift](FocusProblem/SwiftUIPassthroughCell.swift):

| Mechanism | Fixes |
|---|---|
| `didEndDisplaying` / `prepareForReuse` mark the content **stale**: `contentView.isUserInteractionEnabled = false`, so the focus engine ignores its stale items (no re-creation while scrolling) | stale items → `nil` |
| `canBecomeFocused` = "content stale, or no focusable item exposed" (recursive walk of `focusItemContainer`, positive result cached) | section skipped (lazy content) |
| When focus lands on the placeholder cell: rebuild the content **only now** if stale, then forward focus (retry every 50 ms while scrolling) | orphan containers, lazy content |
| `preferredFocusEnvironments = [contentView]` | forward target |

Requirements / trade-offs:
- the collection view delegate must forward `didEndDisplaying` to the cell;
- on a recycled / scrolled-back cell, focus goes through the placeholder: **~60–430 ms during which no button is highlighted**, and the content is rebuilt then (local `@State` reset) — once per focus entry, not per scroll;
- after a placeholder hop, focus lands on the content's **preferred** item (first button), not the geometrically closest one;
- relies on observed `UIHostingContentView` behavior: re-validate on each tvOS release (`WORKAROUND=off` + stress layout).

Do **not** override `focusItems(in:)` on the cell to hide items: UIKit then logs *"implements focusItemsInRect: - caching for linear focus movement is limited as long as this view is on screen"*.

### Solution B — `UIHostingController` reused per cell (recommended)

[HostingControllerReusedCell](FocusProblem/HostingControllerReusedCell.swift): one `UIHostingController` per cell, created on first configure; on reuse only `rootView` is replaced (no view controller teardown). Focus goes **directly** to the SwiftUI buttons (no placeholder, no delay, no state reset by the workaround). Constraints: child view controller containment, `preferredFocusEnvironments → hostingController.view`, `remembersLastFocusedIndexPath = false`.

The original [HostingControllerCell](FocusProblem/HostingControllerCell.swift) (new `UIHostingController` on every configure) works for focus but is expensive while scrolling (see below).

## Performance (Apple TV AF-ATV-010, tvOS 27.0, Release build)

Bench layout `FOCUS_LAYOUT=bench:<variant>` (60 sections: 40 SwiftUI jumbotrons + 20 UIKit card rows), `BENCH=all`, driven inside the app (no remote needed, works on a device): programmatic scroll top→bottom→top at 3000 pt/s, then 39 programmatic focus jumps. Settings can be forced through `FocusProblem/Bench/BenchSettings.swift` (takes precedence over env vars). Timings are also emitted as signposts (`FocusProblem` / `Perf`) for Instruments. Display at ~50 Hz.

**Scroll (recycling cost)**

| Variant | Hitch ratio | Hitches | Jumbotron dequeue avg | Extra work |
|---|---|---|---|---|
| UIKit only (reference) | 3.6 ms/s | 4 | 4.9 ms¹ | — |
| UIHostingConfiguration, no workaround (bug) | 4.6–5.1 ms/s | 5–7 | 1.6 ms | — |
| **A — UIHostingConfiguration + v2** | **3.6 ms/s** | 3 | 1.55 ms | none while scrolling |
| UIHostingConfiguration + v1 (rebuild on didEndDisplaying) | 44.8 ms/s | 53 | 1.6 ms | rebuild 5.4 ms × 78 |
| UIHostingConfiguration + v3 (rebuild on willDisplay) | 106 ms/s | 116 | 1.65 ms | rebuild 6.6 ms × 76 |
| UIHostingController re-created per configure | 48.1 ms/s | 62 | 4.2 ms | — |
| **B — UIHostingController reused** | **3.0 ms/s** | 3 | 1.18 ms | — |

¹ includes the creation of the UIKit cells' view hierarchy.

**Focus jumps (39 jumps through recycled cells)**

| Variant | Landed in SwiftUI content | Per-jump cost | Notes |
|---|---|---|---|
| no workaround | 0 / 39 | 22.7 ms | focus ends on a neighbor card or `nil` |
| A — v2 | 39 / 39 | 6.6 ms | placeholder hop 59 ms avg (85 max), rebuild 1.8 ms ×38, `canBecomeFocused` 0.18 ms ×198 |
| v1 | 39 / 39 | 4.9 ms | + rebuild 19 ms on each `didEndDisplaying` |
| UIHostingController re-created | 39 / 39 | 11.9 ms | dequeue 3.5 ms |
| B — UIHostingController reused | 39 / 39 | 9.7 ms | no placeholder |

(The frame metrics of the focus bench are dominated by the bench's own non-animated `scrollToItem` jumps and are not compared.)

## Recommendation

- **Solution B (reused `UIHostingController`)** for heavy collection views: best scroll numbers (on par with UIKit), focus goes straight to the buttons, no hack relying on `UIHostingContentView` internals.
- **Solution A (v2)** if you must stay on `UIHostingConfiguration`: same scroll cost as UIKit, but a visible 60–430 ms hop on recycled cells and a dependency on observed private behavior.
- Avoid rebuilding the hosting content (v1/v3) or re-creating the `UIHostingController` on every configure: 10–30× more hitches while scrolling.
- File an Apple Feedback:

> **UIHostingConfiguration (tvOS): SwiftUI focus items missing for off-screen cells and stale after the content disappears — focus engine skips the cell or loses focus**

Include: tvOS version, the stress layout (`FOCUS_LAYOUT=stress:hostingConfiguration WORKAROUND=off`), the `-UIFocusLoggingEnabled YES` logs, the facts that `contentView.focusItems(in:)` is empty for a never-displayed cell (`hasBeenVisible == false`) and that only containers without `UIKitFocusableViewResponderItem` leaves remain after some cycles, and that `UIHostingController` doesn't have the issue. Reference WWDC22 session 10072.
