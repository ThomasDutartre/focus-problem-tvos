# Reading focus logs — the `[FOCUS]` channel

The user filters the Xcode console on `[FOCUS]` and pastes the result. That channel is the only log you should ask for: Apple's `-UIFocusLoggingEnabled` warnings are far too noisy to copy by hand. Verbose `🐛 [FocusProblem]` logs only exist with `-FocusVerbose YES`; ask for them only when a precise question needs them.

## Line formats

Helpers in `FocusProblem/DebugHelper.swift` (`focusLog`, `verboseLog`, `focusTag`, `headingName`); short section names in `Section.shortName`.

| Line | Emitted by | Meaning |
|---|---|---|
| `launch tvOS=27.2 hypotheses=["H14"] verbose=false` | `viewDidLoad` | Run identity: tvOS version and active flags. Require it in every paste. |
| `move S2/item0/UIButton → S4/item0/CardUIKitCell heading=down` | VC `didUpdateFocus` | Focus actually moved. `heading` = remote key (`none` = no input, engine-driven). `nil` = focus lost, `outside/…` = tab bar. |
| `button S3 Play focused=true` | `FocusableButton` | SwiftUI side: the button's `@FocusState` changed. |
| `display S3 cell=0x… hidden=false content=0x… subviews=[0x…,…]` / `hide …` | collection view delegate | Cell entered / left the screen; pointers tell whether the cell, its `contentView` and SwiftUI's subviews are the same objects across display cycles. |
| `reuse S3 cell=0x…` | cell `prepareForReuse` | Cell went through the reuse pool (S3b also re-applies its configuration, H12). |
| `configure S3 cell=0x… hadConfiguration=true` | cell registration handler | `contentConfiguration` (re)assigned; `skipped (H14)` when H14 prevents it. |

| `trampoline S3 cell=0x… focused → handing over to SwiftUI` | `SwiftUIPassthroughCell` (H19/H20) | The cell itself got focus and starts the hand-over. |
| `perf S3 rebuild ms=… reason=stale\|idle\|always` / `perf S3 rebuild skipped` | `SwiftUIPassthroughCell` | Content rebuilt at entry (`stale`, H20), while idle off screen (`idle`, H22), at every entry (`always`, H19), or reused. |
| `perf S3 handover ms=… attempts=… ok=true` | `SwiftUIPassthroughCell` | Time from trampoline focus to a SwiftUI button focused. |
| `perf hitch ms=41.7 budget=16.7` | `FrameHitchMonitor` (`-FocusPerf YES`) | A frame longer than 1.5× the budget (≥ 1 dropped frame). |

Sections: S0 SwiftUI cards (UIHostingConfiguration) · S1 jumbotron UIHostingController (**working control**) · S2 UIKit jumbotron · S3 jumbotron UIHostingConfiguration (**broken**) · S3b same + reset on reuse · S4 UIKit cards.

## Typical signatures

- **Ejection on display** (first `[FOCUS]` baseline, tvOS 27.2, 2026-11-09): `S3b → S3 (up)` then `display S3` then `S3 → nil (none)`; a section that stays on screen (S3b with S4 below) is stable. Afterwards `S2 → S4 (down)` / `S4 → S2 (up)`, S3 and S3b skipped.
- **Enter then eject** (original description in `focus-invest.md`): `S2 → S3 (down)` immediately followed by `S3 → nil (none)`, then `nil → S1 (none)`.
- **Effective fix**: every `S2 → S3 (down)` is followed by moves inside S3 or an exit with a real heading, never `→ nil`; `button S3 … focused=true` lines appear without an immediate `false`.
- **Partial**: some cycles OK, others not. Give the x/N rate.

Read the lines around each `→ nil`: which `display` / `reuse` / `configure` happened just before is usually the best clue to the mechanism. Note: `UIView.focusItems(in:)` was tried and returns `focusItems=1 focusable=0` for every SwiftUI cell, even the working S1 — don't use it.

## Adding logs for a hypothesis

Use `focusLog("…")` for the one or two events that prove or disprove the mechanism, phrased like the lines above (`<event> <section> key=value`). Anything that fires in a loop goes through `verboseLog`. Never reintroduce raw `print` calls: they end up in the noise the user cannot filter.
