# tvOS focus fix (H20) — handoff for the real project

Purpose: everything needed to port the fix into the real tvOS app and test it under real conditions.
The clean implementation is in this branch (`fix/focus-h20`). The full investigation (hypotheses H13–H22 in
`focus-invest.md`, the `[FOCUS]` log channel, the XCUITest harness, the stress-test scripts, the investigator agent and
skill) is kept on the branch `investigation/h13-h22-archive`.

## 1. The problem

A `UICollectionView` (compositional layout + diffable data source) has a cell whose content is SwiftUI,
set through `UIHostingConfiguration`, with **several focusable buttons** (the jumbotron).
Sometimes the focus engine skips the cell or the focus gets lost when navigating to it:

- going Down/Up past the jumbotron skips it (e.g. S2 → S4), or
- focus enters then is ejected (`nil`), or the buttons never receive focus.

### Root cause (established on simulator and real Apple TV)

A `UIHostingConfiguration` cell exposes **no SwiftUI focus items** when it is not displayed, and
**loses them after a hidden → visible cycle**. The collection view keeps off-screen cells with
`isHidden = true`; when the cell comes back, its SwiftUI buttons are not focusable.

- Re-assigning a configuration on top of an existing one updates the hosting view **in place** and does
  **not** bring the focus items back.
- Setting `contentConfiguration = nil` and then a new configuration creates a **new hosting view**, which does.
- A cell that was displayed and then hidden is dead even if it never had focus.
- The SwiftUI cards in the same screen work because the cell itself is focusable (they have no inner buttons to reach).

## 2. The fix (H20, "trampoline")

Idea: while focus is outside, the **cell itself is focusable** (so the engine can always land on it, like the
working cards). When it receives focus it **hands focus over to its SwiftUI buttons**, rebuilding the SwiftUI
content first **only if needed**.

1. `canBecomeFocused = enabled && !focusIsInside && !redirecting`.
2. `didUpdateFocus`: when `next === self` → `startTrampoline()`.
3. `startTrampoline()`: if `contentIsStale` → rebuild the content (`nil` then a new configuration); else skip
   (performance). Then hand over (immediately if displayed, otherwise when `willDisplay` fires).
4. Hand-over: `preferredFocusEnvironments = [contentView]` while `redirecting`, then
   `setNeedsFocusUpdate()` + `updateFocusIfNeeded()`, **retried once per frame** (max 60) until focus is inside.
5. `contentIsStale` is set in `didEndDisplaying` and cleared only by a rebuild or by a configuration assigned to
   a cell that had **none** (a fresh hosting view).
6. Safety net: if the hand-over is still stuck at attempt 30 (≈0.5 s), rebuild once more ("recovery") and keep trying.

### Critical detail found by the device stress test

On re-dequeue, the cell registration assigns a configuration **on top of** the existing one. That must **not**
mark the content as fresh (the hosting view is updated in place, focus items stay dead). Initial version marked it
fresh → 154 failures out of 1006. Fixed by `didConfigure(replacedExistingContent:)`.

### Performance rules (central requirement)

- Rebuild only when the cell went off screen (28 % of entries in the stress test).
- No fixed delay: the hand-over is attempted every frame; it succeeds in ≈16 ms when the content is valid.
- No work while focus is inside the cell.

## 3. Code to port

### 3.1 The cell (`FocusProblem/SwiftUIPassthroughCell.swift`)

This is the version committed in this branch: no logs, no hypothesis flag (the behaviour is always H20).
Rename the class as needed.

```swift
import UIKit

final class JumbotronHostingCell: UICollectionViewCell {

    /// Set by the cell registration: builds a fresh content configuration.
    var makeContentConfiguration: (() -> UIContentConfiguration)?

    private var focusIsInside = false
    private var redirecting = false
    private var contentIsStale = false      // went off screen after its content was built
    private var isDisplayed = false
    private var handOverPending = false
    private var recoveredThisEntry = false

    override var canBecomeFocused: Bool { !focusIsInside && !redirecting }

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        if redirecting { return [contentView] }
        let envs = contentView.subviews
        return envs.isEmpty ? super.preferredFocusEnvironments : envs
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        let next = context.nextFocusedView
        focusIsInside = next.map { $0 !== self && $0.isDescendant(of: self) } ?? false
        if next === self {
            startTrampoline()
        } else if !focusIsInside {
            redirecting = false
            handOverPending = false
        }
    }

    private func startTrampoline() {
        redirecting = true
        recoveredThisEntry = false
        if contentIsStale { rebuildContent() }
        if isDisplayed { handOver(attempt: 1) } else { handOverPending = true }   // resumed by cellWillDisplay()
    }

    /// Drop the configuration first so UIKit creates a new hosting view.
    private func rebuildContent() {
        guard let make = makeContentConfiguration else { return }
        contentConfiguration = nil
        contentConfiguration = make()
        contentIsStale = false
    }

    /// Call from the registration every time it assigns a configuration.
    /// Only a configuration given to a cell that had none creates a fresh hosting view.
    func didConfigure(replacedExistingContent: Bool) {
        if !replacedExistingContent { contentIsStale = false }
    }

    // Called by the collection view delegate
    func cellWillDisplay() {
        isDisplayed = true
        if handOverPending { handOverPending = false; handOver(attempt: 1) }
    }

    func cellDidEndDisplaying() {
        isDisplayed = false
        contentIsStale = true
    }

    private func handOver(attempt: Int) {
        let delay: TimeInterval = attempt == 1 ? 0 : 1.0 / 60.0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.performHandOver(attempt: attempt)
        }
    }

    private func performHandOver(attempt: Int) {
        guard redirecting else { return }
        setNeedsFocusUpdate()
        updateFocusIfNeeded()
        if !focusIsInside && attempt < 60 {
            if attempt == 30 && !recoveredThisEntry {      // safety net
                recoveredThisEntry = true
                rebuildContent()
            }
            handOver(attempt: attempt + 1)
            return
        }
        redirecting = false
    }
}
```

### 3.2 Registration

```swift
let registration = UICollectionView.CellRegistration<JumbotronHostingCell, Item> { cell, _, item in
    let hadConfiguration = cell.contentConfiguration != nil      // read BEFORE assigning
    let make: () -> UIContentConfiguration = {
        UIHostingConfiguration { JumbotronView(/* … */) }.margins(.all, 0)
    }
    cell.makeContentConfiguration = make
    cell.contentConfiguration = make()
    cell.didConfigure(replacedExistingContent: hadConfiguration)
}
```

If the jumbotron data is refreshed in place, `make` must capture the **latest** model (re-set it each time).

### 3.3 Collection view delegate (required)

```swift
func collectionView(_ cv: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt ip: IndexPath) {
    (cell as? JumbotronHostingCell)?.cellWillDisplay()
}
func collectionView(_ cv: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt ip: IndexPath) {
    (cell as? JumbotronHostingCell)?.cellDidEndDisplaying()
}
```

If the real project already implements these delegate methods (or wraps the delegate), forward to the cell there.

## 4. Integration notes for the real app

- The real jumbotron is **single**, at the top of Home under the tab bar, with 2 buttons. Multi-jumbotron rows do not exist.
- Check `remembersLastFocusedIndexPath`, any `UIFocusGuide`, `.focusSection()` and `shouldUpdateFocus` overrides in the
  real controller: they can interfere with the trampoline (the POC uses `remembersLastFocusedIndexPath = false`).
- The cell must not be reused for other content types without calling `didConfigure` correctly.
- Content rebuild resets SwiftUI `@State` inside the jumbotron (carousel index, etc.); keep such state in the model.
- Focus always lands on the **first** button (Play / primary). Directional memory of the last focused button is not kept.

## 5. How to test

### 5.1 Automated harness (on branch `investigation/h13-h22-archive`)

To reuse it: `git checkout investigation/h13-h22-archive -- FocusProblemUITests .claude/skills/tvos-focus-hypothesis/scripts`
and re-add the logs and the `-FocusHypothesis` flag it relies on (see that branch's `DebugHelper.swift`,
`FocusHypothesis.swift`, `FrameHitchMonitor.swift`, `SwiftUIPassthroughCell.swift`). The fix itself does not need any of it.

XCUITest drives the remote with `XCUIRemote.shared.press(...)` (simulator HID keys are ignored on tvOS). The app writes the
`[FOCUS]` channel to `Library/Caches/focus-log.txt`; scripts pull it and analyse it.

```bash
# Standard sequence (simulator or device)
DEVICE_ID=<udid> .claude/skills/tvos-focus-hypothesis/scripts/run_focus_sequence.sh <out.log> H20
python3 .claude/skills/tvos-focus-hypothesis/scripts/summarize_stress.py <out.log>

# Stress: N batches of ~100 random entries
DEVICE_ID=<udid> .claude/skills/tvos-focus-hypothesis/scripts/run_focus_stress.sh <outdir> 10 H20
```

Sequence tokens (`FOCUS_SEQUENCE`): `down/up/left/right/select`, `*N` repeat, `waitN`, `paceN`, `background`.
Launch args: `-FocusHypothesis H20`, `-FocusPerf YES` (dropped-frame monitor), `-FocusVerbose YES`.

Only **device** runs support reliability claims (the simulator, tvOS 27.2, does not reproduce the re-configuration case).

### 5.2 Log signatures to look for (only with the instrumented version from the archive branch)

- `trampoline S3 … focused → handing over to SwiftUI`, then `button S3 Play focused=true` and `perf S3 handover ms=… ok=true`.
- `perf S3 rebuild ms=… reason=stale` (expected after a hide), `reason=recovery` (should be **rare / zero**).
- `perf S3 rebuild skipped (content still valid)` = the fast path.
- Failure: `ok=false`, `move … → nil`, or `No focusable items found`.

### 5.3 Manual scenarios to run in the real app (not covered by the POC)

1. Initial focus on Home: jumbotron first under the tab bar.
2. Up to the tab bar, Down back to the jumbotron, repeated.
3. Down to the season tabs, Up back to the jumbotron.
4. Scroll so the jumbotron leaves the screen (several rows), return to it.
5. Tab switch Home ↔ Live-TV ↔ Home, then enter the jumbotron.
6. Jumbotron content refreshed in place (data reload) while displayed, then navigate away and back.
7. App backgrounded / foregrounded, then navigate to the jumbotron.
8. Fast repeated Up/Down presses (stress).

Pass criterion: every entry ends with focus on a jumbotron button, no skip, no ejection.

## 6. Results (real Apple TV SA-ATV-011, tvOS 26.6)

| Run | Entries | Hand-overs OK | Failed | Notes |
|---|---|---|---|---|
| Baseline (no fix) | — | — | — | S3 reachable only sometimes; dead after hide → visible |
| H20, first stress (before `didConfigure`) | 1006 | 852 | 154 | all caused by re-configuration marked as fresh |
| Control after fix (worst seed) | 100 | 100 | 0 | p50 8.5 ms, p95 229 ms |
| **H20 final, standard sequence** | 11 | 11 | 0 | |
| **H20 final, stress 10 batches (2026-11-10)** | **1006** | **1006** | **0** | 0 aborted, 0 nil ejection |

Final stress figures: failure rate < 0.30 % (95 %, rule of three).
Hand-over latency: p50 16.1 ms, p95 236.5 ms, p99 259.7 ms, max 268.5 ms.
Content rebuilt on 28 % of entries (280); 26 % of entries had a dropped frame (263), mostly the rebuild entries.
Earlier run on the standard H20 path: 83 entries, 63 without rebuild at ≈8.5 ms, 20 rebuilds at 137–205 ms.

### Rejected alternatives (do not retry)

- H16 `isHidden` override (never called), H17 shorter jumbotron (clips buttons), H21 in-place refresh (failed 5/11),
  H22 (regressed on device), H19 rebuild at every entry with fixed 0.3 s delay (works, slower — kept only for comparison).

## 7. Known limitations

- ≈150–240 ms and one dropped frame when entering after the cell went off screen (rebuild).
- SwiftUI state inside the jumbotron is lost at rebuild.
- Focus always lands on the first button.
- Not yet validated on the real page layout (section 5.3); the POC has several sections that the real app does not.
- Behaviour relies on UIKit/SwiftUI internals that may change with tvOS versions: re-run the stress test on each major tvOS release.
