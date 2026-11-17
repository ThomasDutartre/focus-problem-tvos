# `-FocusHypothesis` infrastructure

Goal: enable a hypothesis at runtime, without rebuilding between baseline and variant, and without changing default behavior.

It already exists in `FocusProblem/FocusHypothesis.swift`. A `-Key Value` launch argument lands in the `UserDefaults` argument domain, so `-FocusHypothesis H14` (or `H14,H15`) is read from `UserDefaults.standard.string(forKey: "FocusHypothesis")`.

## Usage

```swift
// H14 — <one-line description>
if FocusHypothesis.isActive("H14") {
    // the single change under test
}
```

- Hypotheses are plain strings: nothing to declare, nothing to delete except the `isActive` blocks when a hypothesis is rejected.
- Keep each block as close as possible to the code concerned, one hypothesis per block, with the `// H<n> —` comment so it is easy to find and remove.
- Active flags are printed at launch by the `[FOCUS] launch … hypotheses=[…]` line: it proves which run is which in a paste.
- If the change must happen before `viewDidLoad` (e.g. in a cell initializer), `FocusHypothesis.isActive` is safe to call anywhere: it only reads `UserDefaults`.

## Verbose logs

`-FocusVerbose YES` turns on the old `🐛 [FocusProblem]` diagnostics (`verboseLog`). Off by default because they fire in loops and drown the `[FOCUS]` lines.
