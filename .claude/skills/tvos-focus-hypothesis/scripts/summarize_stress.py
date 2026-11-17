#!/usr/bin/env python3
"""Summarize several [FOCUS] logs (stress batches) into reliability and performance figures.

Usage: summarize_stress.py batch-1.log batch-2.log ... [--json]

Reliability
  entries        trampoline activations on S3 (focus reached the S3 cell)
  hand-over OK   a SwiftUI button got focus (`perf S3 handover … ok=true`)
  failed         60 frames without success (`ok=false`) — focus stuck on the cell
  aborted        trampoline without a hand-over line: focus left before the hand-over finished
                 (fast presses); not a failure if the next move is normal
  nil ejections  focus lost from S3 to nil — the original bug
  upper bound    with 0 failures, the "rule of three": true failure rate < 3 / entries (95 %)
Performance
  hand-over latency p50 / p95 / p99 / max, rebuilds at entry, long frames (> 1.5× budget),
  long frames between a trampoline and its hand-over.
"""

import argparse
import json
import re
import sys

HANDOVER = re.compile(r"\[FOCUS\] perf S3 handover ms=([\d.]+) attempts=(\d+) ok=(true|false)")
MOVE_NIL = re.compile(r"\[FOCUS\] move S3/\S+ → nil")


def pct(values, p):
    if not values:
        return None
    v = sorted(values)
    k = min(len(v) - 1, max(0, round(p / 100 * (len(v) - 1))))
    return v[k]


def summarize(paths):
    r = {"batches": len(paths), "launches_tvos": set(), "entries": 0, "ok": 0, "failed": 0, "aborted": 0,
         "nil_ejections": 0, "rebuilds": 0, "rebuild_skipped": 0, "latency_ms": [], "hitches": 0,
         "hitches_during_entry": 0, "failed_batches": []}
    for path in paths:
        try:
            lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
        except OSError:
            r["failed_batches"].append(path)
            continue
        pending = False
        batch_failed = False
        for l in lines:
            if "[FOCUS] launch" in l:
                m = re.search(r"tvOS=(\S+)", l)
                if m:
                    r["launches_tvos"].add(m.group(1))
            elif "trampoline S3" in l and "focused" in l:
                if pending:
                    r["aborted"] += 1
                r["entries"] += 1
                pending = True
            elif (m := HANDOVER.search(l)):
                pending = False
                if m.group(3) == "true":
                    r["ok"] += 1
                    r["latency_ms"].append(float(m.group(1)))
                else:
                    r["failed"] += 1
                    batch_failed = True
            elif "perf S3 rebuild ms=" in l:
                r["rebuilds"] += 1
            elif "perf S3 rebuild skipped" in l:
                r["rebuild_skipped"] += 1
            elif "perf hitch" in l:
                r["hitches"] += 1
                if pending:
                    r["hitches_during_entry"] += 1
            elif MOVE_NIL.search(l):
                r["nil_ejections"] += 1
                batch_failed = True
        if pending:
            r["aborted"] += 1
        if batch_failed:
            r["failed_batches"].append(path)
    r["launches_tvos"] = sorted(r["launches_tvos"])
    return r


def report(r):
    n, lat = r["entries"], r["latency_ms"]
    out = [f"Batches: {r['batches']}  tvOS: {', '.join(r['launches_tvos']) or '?'}",
           "",
           "Reliability",
           f"  entries into S3      : {n}",
           f"  hand-over OK         : {r['ok']}",
           f"  hand-over failed     : {r['failed']}",
           f"  aborted (focus left) : {r['aborted']}",
           f"  nil ejections from S3: {r['nil_ejections']}"]
    if r["failed"] == 0 and r["nil_ejections"] == 0 and r["ok"]:
        out.append(f"  failure rate < {300 / r['ok']:.2f} % (95 %, rule of three on {r['ok']} hand-overs)")
    if r["failed_batches"]:
        out.append(f"  batches to look at   : {', '.join(r['failed_batches'])}")
    out += ["",
            "Performance",
            f"  hand-over latency ms : p50 {pct(lat, 50)}  p95 {pct(lat, 95)}  p99 {pct(lat, 99)}  max {max(lat) if lat else None}",
            f"  rebuilds at entry    : {r['rebuilds']} ({100 * r['rebuilds'] / n:.0f} % of entries)" if n else "  rebuilds at entry    : 0",
            f"  long frames          : {r['hitches']} total, {r['hitches_during_entry']} during an entry"
            + (f" ({100 * r['hitches_during_entry'] / n:.1f} % of entries)" if n else "")]
    return "\n".join(out)


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("logs", nargs="+")
    p.add_argument("--json", action="store_true")
    a = p.parse_args()
    r = summarize(a.logs)
    print(json.dumps(r, indent=2) if a.json else report(r))
    if r["entries"] == 0:
        sys.exit("No S3 entry found: wrong logs, or the fix was not active (-FocusHypothesis H20).")


if __name__ == "__main__":
    main()
