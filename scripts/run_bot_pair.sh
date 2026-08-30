#!/usr/bin/env bash
# Drives two agent players (test_bot_pair.gd) through the cooperative campaign
# levels, captures engine errors/warnings, and writes a gameplay + bug report.
#
# Usage:
#   bash scripts/run_bot_pair.sh
#   FRAMES=2400 LEVELS="sunny_forest crystal_caves cloud_factory" bash scripts/run_bot_pair.sh
#
# Output:
#   game/test-output/bot_pair_report.md   - human-readable gameplay + bug report
#   game/test-output/bot_pair_<level>.log - raw godot stdout+stderr per level
set -euo pipefail

PROJECT_ROOT=$(cd "$(dirname "$0")/.." && pwd)
GODOT_BIN="${GODOT_BIN:-godot}"
FRAMES="${FRAMES:-1800}"
LEVELS="${LEVELS:-sunny_forest crystal_caves cloud_factory}"
OUT_DIR="$PROJECT_ROOT/game/test-output"
mkdir -p "$OUT_DIR"

REPORT="$OUT_DIR/bot_pair_report.md"
: > "$REPORT"

echo "# Bot Pair Gameplay Report" >> "$REPORT"
echo "" >> "$REPORT"
echo "Generated: \`$(date -u '+%Y-%m-%dT%H:%M:%SZ')\`  " >> "$REPORT"
echo "Harness: \`game/tests/integration/test_bot_pair.gd\`  " >> "$REPORT"
echo "Frames per level: \`$FRAMES\` (~$(( FRAMES / 30 ))s at 30 physics fps)  " >> "$REPORT"
echo "Godot: \`$GODOT_BIN\`  " >> "$REPORT"
echo "" >> "$REPORT"

# Aggregate distinct error signatures across all levels.
declare -A ERROR_COUNTS
declare -A ERROR_LEVELS
TOTAL_ERRORS=0
TOTAL_WARNINGS=0

for level in $LEVELS; do
  log="$OUT_DIR/bot_pair_${level}.log"
  echo "==> Running bot pair on $level ($FRAMES frames)..."
  set +e
  "$GODOT_BIN" --headless --path "$PROJECT_ROOT/game" \
    -s res://tests/integration/test_bot_pair.gd -- \
    --level="$level" --frames="$FRAMES" >"$log" 2>&1
  status=$?
  set -e

  report_line=$(grep -m1 '^BOT_REPORT ' "$log" || true)
  if [[ -z "$report_line" ]]; then
    report_line="BOT_REPORT level=$level error=no_report_line exit=$status"
  fi

  # Count engine diagnostics in this level's log.
  lvl_errors=$(grep -cE 'ERROR:|SCRIPT ERROR|bubble pool exhausted|already connected' "$log" || true)
  lvl_warnings=$(grep -cE 'WARNING:' "$log" || true)
  TOTAL_ERRORS=$(( TOTAL_ERRORS + lvl_errors ))
  TOTAL_WARNINGS=$(( TOTAL_WARNINGS + lvl_warnings ))

  # Collect distinct error signatures (first 120 chars, deduped).
  while IFS= read -r sig; do
    [[ -z "$sig" ]] && continue
    ERROR_COUNTS["$sig"]=$(( ${ERROR_COUNTS["$sig"]:-0} + 1 ))
    if [[ -z "${ERROR_LEVELS["$sig"]:-}" ]]; then
      ERROR_LEVELS["$sig"]="$level"
    else
      ERROR_LEVELS["$sig"]="${ERROR_LEVELS["$sig"]},$level"
    fi
  done < <(grep -E 'ERROR:|SCRIPT ERROR|bubble pool exhausted|already connected' "$log" \
        | sed -E 's/[0-9]+/N/g' | cut -c1-160 | sort -u)

  echo "    exit=$status  errors=$lvl_errors  warnings=$lvl_warnings"
  echo "    $report_line"

  # Per-level section in the report.
  echo "## $level" >> "$REPORT"
  echo "" >> "$REPORT"
  echo "- exit code: \`$status\`" >> "$REPORT"
  echo "- engine errors: \`$lvl_errors\`  |  warnings: \`$lvl_warnings\`" >> "$REPORT"
  echo "- report: \`$report_line\`" >> "$REPORT"
  echo "" >> "$REPORT"
done

# Aggregate bugs / error signatures section.
echo "## Aggregated Error Signatures" >> "$REPORT"
echo "" >> "$REPORT"
echo "Total engine errors across levels: \`$TOTAL_ERRORS\`  |  warnings: \`$TOTAL_WARNINGS\`" >> "$REPORT"
echo "" >> "$REPORT"
if [[ ${#ERROR_COUNTS[@]} -eq 0 ]]; then
  echo "_No engine errors or warnings detected._" >> "$REPORT"
else
  echo "| count | levels | signature |" >> "$REPORT"
  echo "|------:|--------|-----------|" >> "$REPORT"
  # Sort by count desc.
  for sig in "${!ERROR_COUNTS[@]}"; do
    printf '%d\t%s\t%s\n' "${ERROR_COUNTS[$sig]}" "${ERROR_LEVELS[$sig]}" "$sig"
  done | sort -rn -k1 | while IFS=$'\t' read -r cnt lvls sig; do
    echo "| $cnt | $lvls | \`$sig\` |" >> "$REPORT"
  done
fi
echo "" >> "$REPORT"

echo "==> Report written to $REPORT"
cat "$REPORT"
