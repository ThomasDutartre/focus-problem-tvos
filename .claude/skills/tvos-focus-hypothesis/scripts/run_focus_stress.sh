#!/usr/bin/env bash
# Stress test: N batches of a randomized sequence (≈100 entries into S3 each), then one summary.
#
# Usage: run_focus_stress.sh <out_dir> [batches=10] [hypothesis=H20] [entries_per_batch=100]
#   Same env as run_focus_sequence.sh (SIM_UDID, or DEVICE_ID for a real Apple TV).
#   Each batch is a separate app launch with its own seed (1..N), so a failure is reproducible:
#   re-run one batch with `run_focus_sequence.sh <log> H20 "$(make_stress_sequence.py --seed <n>)"`.
#   Expect ≈ 5 min per batch of 100 entries (see `make_stress_sequence.py --estimate`).
set -euo pipefail

OUT_DIR="${1:?usage: run_focus_stress.sh <out_dir> [batches] [hypothesis] [entries_per_batch]}"
BATCHES="${2:-10}"
HYP="${3:-H20}"
PER_BATCH="${4:-100}"
HERE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$OUT_DIR"

for i in $(seq 1 "$BATCHES"); do
  SEQ="$(python3 "$HERE/make_stress_sequence.py" --seed "$i" --entries "$PER_BATCH")"
  echo "batch $i/$BATCHES — $(python3 "$HERE/make_stress_sequence.py" --seed "$i" --entries "$PER_BATCH" --estimate)"
  "$HERE/run_focus_sequence.sh" "$OUT_DIR/batch-$i.log" "$HYP" "$SEQ" || echo "batch $i FAILED to run (see $OUT_DIR/batch-$i.xcodebuild.txt)"
done

python3 "$HERE/summarize_stress.py" "$OUT_DIR"/batch-*.log | tee "$OUT_DIR/summary.txt"
