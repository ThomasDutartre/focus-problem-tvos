#!/usr/bin/env python3
"""Generate a randomized (seeded) remote sequence for FocusSequenceUITests.

Every block starts and ends with focus on S2 (UIKit jumbotron), so blocks can be chained.
Layout assumed (fix active): tab bar → S0 → S1 → S2 → S3 → S4, S3b skipped.

Blocks (weights in BLOCKS):
  enter_exit  Down into S3, random pause, Up                         1 entry
  enter_lr    Down into S3, Right, Right, Left, Up                   1 entry
  through     Down, Down (S3 → S4), pause, Up, Up (S4 → S3 → S2)     2 entries
  fast_burst  Down/Up 3× with 0.15 s between presses                 3 entries (some hand-overs aborted)
  long_trip   Up to S0, pause, back to S2 (S3 goes off screen)       0 entry, makes S3 stale
  bottom_trip Down to S4, Right ×3 in the cards, back, Up to S2      2 entries
  background  Home button, back to the app                           0 entry
A resync (Up ×6 to the tab bar, Down ×3) is inserted every 15 blocks in case focus drifted.

Usage: make_stress_sequence.py [--seed N] [--entries 100] [--estimate]
"""

import argparse
import random

BLOCKS = {
    "enter_exit": 30,
    "enter_lr": 15,
    "through": 20,
    "fast_burst": 10,
    "long_trip": 10,
    "bottom_trip": 10,
    "background": 2,
}
ENTRIES = {"enter_exit": 1, "enter_lr": 1, "through": 2, "fast_burst": 3,
           "long_trip": 0, "bottom_trip": 2, "background": 0}


def block(name, rnd):
    pause = f"wait{rnd.choice([0.3, 0.6, 1, 1.5, 2])}"
    if name == "enter_exit":
        return f"down {pause} up wait0.5"
    if name == "enter_lr":
        return "down wait0.5 right right left up wait0.5"
    if name == "through":
        return f"down down {pause} up up wait0.5"
    if name == "fast_burst":
        return "pace0.15 down up down up down up pace0.8 wait1"
    if name == "long_trip":
        return f"up up {pause} down down wait0.5"
    if name == "bottom_trip":
        return "down down wait0.5 right right right wait0.5 left left left up up wait0.5"
    if name == "background":
        return "background"
    raise ValueError(name)


def generate(seed, target_entries):
    rnd = random.Random(seed)
    names, weights = zip(*BLOCKS.items())
    steps = ["down*3 wait1"]   # tab bar → S0 → S1 → S2
    entries, count = 0, 0
    while entries < target_entries:
        name = rnd.choices(names, weights)[0]
        steps.append(block(name, rnd))
        entries += ENTRIES[name]
        count += 1
        if count % 15 == 0:
            steps.append("up*6 wait1 down*3 wait1")
    return " ".join(steps), entries


def estimate_seconds(seq):
    total, pace = 0.0, 0.8
    for tok in seq.split():
        if tok.startswith("wait"):
            total += float(tok[4:])
        elif tok.startswith("pace"):
            pace = float(tok[4:])
        elif tok == "background":
            total += 4
        else:
            n = int(tok.split("*")[1]) if "*" in tok else 1
            total += n * pace
    return total


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--seed", type=int, default=1)
    p.add_argument("--entries", type=int, default=100, help="approximate number of entries into S3")
    p.add_argument("--estimate", action="store_true", help="print expected entries and duration instead")
    a = p.parse_args()
    seq, entries = generate(a.seed, a.entries)
    if a.estimate:
        print(f"seed={a.seed} planned entries≈{entries} duration≈{estimate_seconds(seq) / 60:.1f} min")
    else:
        print(seq)


if __name__ == "__main__":
    main()
