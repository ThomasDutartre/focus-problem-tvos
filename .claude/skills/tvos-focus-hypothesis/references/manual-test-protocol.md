# Template — manual test protocol

Fill in the `<…>` and give this text to the user. Keep it short and plain: the user should not need to read code or understand the mechanism to run it. Always two runs, baseline (no flag) and variant, same moves, otherwise the comparison is worthless. If a recent baseline `[FOCUS]` paste for the same tvOS version exists, you may skip the baseline run, saying so.

---

## Test H<n> — <short title>

**In one sentence**: <what changes, in plain words>.

### Two runs
In Xcode: Edit Scheme → Run → Arguments → "Arguments Passed On Launch".
- **Run 1 (baseline)**: no `-FocusHypothesis` line (or untick it).
- **Run 2 (variant)**: add and tick `-FocusHypothesis H<n>`.

`-UIFocusLoggingEnabled YES` can stay ticked or not, it doesn't matter.

### Moves (same for both runs)
The keyboard arrows act as the remote.
1. Down until section 2 (UIKit jumbotron).
2. 5 times: Down, wait 2 s, Up.
3. Down until section 4, then 5 times: Up, wait 2 s, Down.
4. <Hypothesis-specific step if needed.>

### What to send back
1. In the Xcode console, type `[FOCUS]` in the **Filter** field (bottom right), select all (⌘A), copy (⌘C), paste here. One paste per run, say which is which.
2. One line per run on what you saw, e.g. "focus never stops on section 3".
