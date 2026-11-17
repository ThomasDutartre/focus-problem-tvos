#!/usr/bin/env python3
"""Analyze the [FOCUS] log channel of the FocusProblem POC (tvOS).

Input: a console dump (raw or already filtered on "[FOCUS]"). Every other line
is ignored, so Apple warnings and verbose 🐛 logs don't get in the way.

Reports:
  - launch line(s): tvOS version and active hypotheses
  - every focus transition between sections, with the remote heading, counted
  - for the target section (default S3): entries, nil ejections, stable entries
  - "scan" stats per SwiftUI section: focusable items UIKit sees after each move
  - SwiftUI button focus events per section

Usage:
    python3 analyze_focus_log.py run.log [--section S3] [--json-only]

Line formats (see FocusProblem/DebugHelper.swift and FocusProblemViewController.swift):
    [FOCUS] launch tvOS=27.2 hypotheses=["H14"] verbose=false
    [FOCUS] move S2/item0/UIButton → S4/item0/CardUIKitCell heading=down
    [FOCUS] scan S3 focusItems=0 focusable=0
    [FOCUS] button S3 Play focused=true
    [FOCUS] display S3 cell=0x… | hide S3 cell=0x… | reuse S3 cell=0x… | configure S3 cell=0x… hadConfiguration=true
"""

import argparse
import json
import re
import sys
from collections import Counter, defaultdict

TAG = "[FOCUS]"
MOVE = re.compile(r"\[FOCUS\] move (?P<src>\S+) → (?P<dst>\S+) heading=(?P<heading>\S+)")
SCAN = re.compile(r"\[FOCUS\] scan (?P<sec>\S+) focusItems=(?P<items>\d+) focusable=(?P<focusable>\d+)")
BUTTON = re.compile(r"\[FOCUS\] button (?P<sec>\S+) (?P<label>\S+) focused=(?P<val>true|false)")
LAUNCH = re.compile(r"\[FOCUS\] launch (?P<rest>.*)$")
REBUILD = re.compile(r"\[FOCUS\] perf S3 rebuild ms=(?P<ms>[\d.]+)")
REBUILD_SKIP = re.compile(r"\[FOCUS\] perf S3 rebuild skipped")
HANDOVER = re.compile(r"\[FOCUS\] perf S3 handover ms=(?P<ms>[\d.]+) attempts=(?P<att>\d+) ok=(?P<ok>true|false)")
HITCH = re.compile(r"\[FOCUS\] perf hitch ms=(?P<ms>[\d.]+)")
OTHER = re.compile(r"\[FOCUS\] (?P<kind>display|hide|reuse|configure) (?P<sec>\S+)")


def section_of(tag: str) -> str:
    """'S3/item0/UIHostingContentView' -> 'S3'; 'nil' -> 'nil'; 'outside/…' -> 'outside'."""
    return tag.split("/", 1)[0]


def analyze(lines, target):
    s = {
        "target_section": target,
        "launches": [],
        "transitions": Counter(),
        "target": {"entries": 0, "stable_entries": 0, "nil_ejections": 0,
                   "normal_exits": 0, "internal_moves": 0, "still_focused_at_end": 0},
        "scan": defaultdict(lambda: {"samples": 0, "min_focusable": None, "max_focusable": None, "last": None}),
        "buttons_focused": Counter(),
        "display_events": Counter(),
        "focus_lines": 0,
        "perf": {"rebuild_ms": [], "rebuild_skipped": 0, "handover_ms": [], "handover_attempts": [],
                 "handover_failed": 0, "hitch_ms": []},
    }
    in_target, ejected = False, False

    for raw in lines:
        line = raw.rstrip("\n")
        if TAG not in line:
            continue
        s["focus_lines"] += 1

        m = LAUNCH.search(line)
        if m:
            s["launches"].append(m.group("rest"))
            continue

        m = MOVE.search(line)
        if m:
            src, dst, heading = section_of(m.group("src")), section_of(m.group("dst")), m.group("heading")
            if src != dst:
                s["transitions"][f"{src} → {dst} ({heading})"] += 1
            t = s["target"]
            if dst == target and src != target:
                t["entries"] += 1
                in_target, ejected = True, False
            elif src == target and dst == target:
                t["internal_moves"] += 1
            elif src == target:
                if dst == "nil":
                    t["nil_ejections"] += 1
                    ejected = True
                else:
                    t["normal_exits"] += 1
                    if not ejected:
                        t["stable_entries"] += 1
                in_target = False
            continue

        pf = s["perf"]
        m = REBUILD.search(line)
        if m:
            pf["rebuild_ms"].append(float(m.group("ms")))
            continue
        if REBUILD_SKIP.search(line):
            pf["rebuild_skipped"] += 1
            continue
        m = HANDOVER.search(line)
        if m:
            pf["handover_ms"].append(float(m.group("ms")))
            pf["handover_attempts"].append(int(m.group("att")))
            if m.group("ok") == "false":
                pf["handover_failed"] += 1
            continue
        m = HITCH.search(line)
        if m:
            pf["hitch_ms"].append(float(m.group("ms")))
            continue

        m = SCAN.search(line)
        if m:
            sc = s["scan"][m.group("sec")]
            f = int(m.group("focusable"))
            sc["samples"] += 1
            sc["min_focusable"] = f if sc["min_focusable"] is None else min(sc["min_focusable"], f)
            sc["max_focusable"] = f if sc["max_focusable"] is None else max(sc["max_focusable"], f)
            sc["last"] = {"focusItems": int(m.group("items")), "focusable": f}
            continue

        m = BUTTON.search(line)
        if m:
            if m.group("val") == "true":
                s["buttons_focused"][f"{m.group('sec')} {m.group('label')}"] += 1
            continue

        m = OTHER.search(line)
        if m:
            s["display_events"][f"{m.group('kind')} {m.group('sec')}"] += 1

    if in_target and not ejected:
        s["target"]["still_focused_at_end"] += 1
    s["transitions"] = dict(s["transitions"].most_common())
    s["scan"] = dict(s["scan"])
    s["buttons_focused"] = dict(s["buttons_focused"])
    s["display_events"] = dict(s["display_events"])
    return s


def summary(s):
    t = s["target"]
    out = [f"[FOCUS] lines read : {s['focus_lines']}"]
    out += [f"Launch             : {l}" for l in s["launches"]] or ["Launch             : (no launch line — flag state unknown)"]
    out.append("\nTransitions between sections (count):")
    out += [f"  {k}: {v}" for k, v in s["transitions"].items()] or ["  (none)"]
    out.append(f"\nTarget section {s['target_section']}:")
    stable = t["stable_entries"] + t["still_focused_at_end"]
    out.append(f"  entries {t['entries']}, stable {stable}/{t['entries']}, nil ejections {t['nil_ejections']}, "
               f"normal exits {t['normal_exits']}, internal moves {t['internal_moves']}")
    out.append("\nFocusable items seen by UIKit after each move (scan):")
    out += [f"  {sec}: samples {v['samples']}, focusable min {v['min_focusable']} / max {v['max_focusable']}, last {v['last']}"
            for sec, v in sorted(s["scan"].items())] or ["  (no scan line — SwiftUI cells never on screen?)"]
    out.append("\nSwiftUI buttons that got focus:")
    out += [f"  {k}: {v}" for k, v in s["buttons_focused"].items()] or ["  (none)"]
    pf = s["perf"]
    def stats(v):
        if not v:
            return "n=0"
        v = sorted(v)
        return f"n={len(v)} min={v[0]:.1f} median={v[len(v)//2]:.1f} max={v[-1]:.1f} total={sum(v):.1f}"
    out.append("\nPerformance:")
    out.append(f"  S3 rebuilds        : {stats(pf['rebuild_ms'])} ms, skipped {pf['rebuild_skipped']}")
    out.append(f"  S3 hand-over       : {stats(pf['handover_ms'])} ms, failed {pf['handover_failed']}, attempts {sorted(set(pf['handover_attempts']))}")
    out.append(f"  Long frames (hitch): {stats(pf['hitch_ms'])} ms")
    if s["display_events"]:
        out.append("\nDisplay / reuse / configure events:")
        out += [f"  {k}: {v}" for k, v in s["display_events"].items()]
    return "\n".join(out)


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("log")
    p.add_argument("--section", default="S3", help="target section short name: S0, S1, S2, S3, S3b, S4")
    p.add_argument("--json-only", action="store_true")
    a = p.parse_args()

    try:
        with open(a.log, encoding="utf-8", errors="replace") as f:
            lines = f.readlines()
    except OSError as e:
        sys.exit(f"Cannot read {a.log}: {e}")

    if not any(TAG in l for l in lines):
        sys.exit(f"No {TAG} line in {a.log}: incomplete log, wrong file, or app built before the [FOCUS] channel existed.")

    s = analyze(lines, a.section)
    if not a.json_only:
        print(summary(s))
        print("\n--- JSON ---")
    print(json.dumps(s, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
