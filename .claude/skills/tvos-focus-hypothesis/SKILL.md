---
name: tvos-focus-hypothesis
description: Full cycle of a fix hypothesis for the tvOS focus bug in the FocusProblem POC (UICollectionView cell using UIHostingConfiguration with several SwiftUI buttons that permanently loses focus) — picking the next untested lead, implementing it behind the -FocusHypothesis launch argument, writing the remote-control test protocol, analyzing the [FOCUS] log channel and recording an H<n> entry in focus-invest.md. Use this skill whenever work touches focus-invest.md, an H<n> hypothesis, SwiftUIPassthroughCell, UIHostingConfiguration focus, pasted [FOCUS] / 🐛 [FocusProblem] / "No focusable items found" logs, or the user asks to test, conclude or document a focus fix in this repo — even if they don't name the skill.
---

# Hypothesis cycle — tvOS focus bug

The bug: in section 3 (`SwiftUIPassthroughCell` + `UIHostingConfiguration`), focus enters, gets ejected to `nil` with no input, then the section is never focusable again. Full context and H1–H12 live in `focus-invest.md` at the repo root: it is the source of truth, read it first.

Tests run **without the user**: an XCUITest target drives the Siri Remote on the simulator and the app writes its `[FOCUS]` log to a file you read yourself. Only fall back to asking the user for a manual run (`references/manual-test-protocol.md`) if the automated run is broken and you cannot fix it.

<workflow>
Phase A prepares and runs a hypothesis, phase B concludes it; loop A → B until a fix is confirmed.

**Phase A — prepare**
1. Pick the hypothesis: read `references/hypotheses-backlog.md` and take the first lead not yet present in `focus-invest.md`. Number it `H<last+1>`. Write in one sentence the suspected mechanism and the expected log signature if true / false (`references/log-signatures.md`).
2. Implement **a single** change, guarded by `FocusHypothesis.isActive("H<n>")` (`references/flag-infrastructure.md`). Without the argument the app must behave exactly as today — that is what makes the baseline trustworthy. One variable at a time: if two things change, a success doesn't tell which one mattered.
3. If the existing `[FOCUS]` lines (move, button, display, reuse, configure) can't prove the mechanism, add one or two `focusLog` events for it — never raw `print` (see "Adding logs" in `references/log-signatures.md`).
4. Build: `mise exec -- xcodebuildmcp simulator build --scheme FocusTrap --project-path ./FocusProblem.xcodeproj --simulator-id <UDID>` (UDID via `xcrun simctl list devices available | grep -A8 tvOS`). Fix until green.
5. Run it yourself, baseline and variant, ≥ 3 runs of the variant (the bug can be non-deterministic):
   `.claude/skills/tvos-focus-hypothesis/scripts/run_focus_sequence.sh <scratchpad>/h<n>.log H<n>` (empty hypothesis = baseline; optional 3rd argument = custom sequence such as `"down*3 wait1 down wait1 right wait1 up"`). It builds, runs `FocusUITests` and copies the `[FOCUS]` log.
   For a confidence run before calling a fix reliable, use the stress test: `.claude/skills/tvos-focus-hypothesis/scripts/run_focus_stress.sh <scratchpad>/stress 10 H<n>` (≈ 1000 entries, ≈ 1 h; `DEVICE_ID=<udid>` for a real Apple TV). It ends with `summary.txt` (reliability + latency percentiles + long frames). It is long: ask the user before starting it.
6. Go straight to phase B with those logs. Record the entry in `focus-invest.md` only once you have a verdict.

**Phase B — conclude**
1. Use the log files from step A5 (or, for a manual fallback, save the pasted logs to scratchpad files).
2. Run the deterministic analysis on each file:
   `python3 .claude/skills/tvos-focus-hypothesis/scripts/analyze_focus_log.py <file.log> [--section S3]`
   It lists section-to-section transitions with the remote heading, entries / `nil` ejections / stable entries for the target section, and display / reuse / configure events, then prints JSON. Don't recount by hand: that's where errors creep in.
3. Compare with the baseline run and with the per-cycle OK/KO observations reported by the user. If script and observations disagree, say so and favor the on-screen observation, noting the gap.
4. **Performance is part of the verdict.** Compare the analyzer's "Performance" block (rebuild count, hand-over latency, long frames) with the current best fix on the same sequence: a fix that works but costs more rebuilds, latency or long frames is not an improvement. Simulator numbers are only comparable between runs on the same simulator.
5. Verdict (rules in `references/invest-entry-template.md`): `CONFIRMED`, `REJECTED` or `PARTIAL`, with rate x/N and 2–5 significant log lines. Update the `H<n>` entry.
6. If `REJECTED`: remove the hypothesis `isActive` block(s). If `CONFIRMED`: ask for a check of sections 1, 2 and 4 with the flag, then update "Working solution" and "Recommendation".
</workflow>

<deliverables>
- Phase A: diff behind flag + automated run logs.
- Phase B: finalized `H<n>` entry + script output for each run + recommendation for the next lead.
</deliverables>

<guardrails>
- No verdict without logs; an untested hypothesis stays `PENDING`.
- No re-test of a rejected hypothesis without naming the variable that changes.
- No change to default behavior outside the flag; no modification of `xcuserdata`.
- No private API, swizzling or KVC on `UIHostingContentView` / `_UIInheritedView` presented as a fix; at most `[DIAGNOSTIC ONLY]`.
- Any claim about UIKit/SwiftUI internals not proven by logs or Apple docs is marked `[UNSOURCED]`.
- No commit or branch switch; logs and temporary files go in the scratchpad, not the repo.
</guardrails>
