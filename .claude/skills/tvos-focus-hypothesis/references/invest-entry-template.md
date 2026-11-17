# Template — H<n> entry in `focus-invest.md`

Insert in "## Hypotheses tested", after the last entry. Write in English, like H1–H12, so the document stays consistent and usable in an Apple Feedback.

```markdown
### H<n> — <short title> → <PENDING | CONFIRMED | REJECTED | PARTIAL>

**Idea**: <mechanism suspected, one or two sentences; mark [UNSOURCED] claims>.

**Implementation**: <what changes, file:symbol>, behind `-FocusHypothesis H<n>`. Single variable changed vs baseline: <variable>.

**Result**: <PENDING: "Awaiting manual test (protocol sent on YYYY-MM-DD)." / otherwise:>
- Baseline: <x/N cycles stable>, variant: <y/N cycles stable> (tvOS <version>, <device>).
- Script: key transitions (e.g. `S2 → S4 (down)` ×5), S3 entries <a> / nil ejections <b> (baseline vs variant).
- Key log lines:
  ```
  <2–5 lines, trimmed>
  ```
- Conclusion: <one sentence>.
```

## Verdict rules

- **CONFIRMED**: variant stable on 5/5 cycles, baseline reproducing the bug, zero `→ nil` ejection from S3, and control sections 1, 2, 4 not degraded (if that check isn't done yet, write `CONFIRMED (controls pending)`).
- **REJECTED**: variant as bad as the baseline (same failure rate within ±1 cycle, same signature).
- **PARTIAL**: clear improvement but not 5/5, or stable with residual warnings suggesting fragility.
- If the baseline **does not reproduce** the bug, no verdict: ask for a new baseline run, the hypothesis stays `PENDING`.

Dates in absolute format (YYYY-MM-DD).
