#!/usr/bin/env bash
# extract-python.sh - pulls the Python transformation out of data flow JSON files
# into readable .py files next to them, so code changes show up clearly in git diff.
#
# Writes objects/data-flows/<name>.py for every flow that contains a Python script.
# jq writes straight to the file (no bash variable) to avoid truncating the code.
#
# Usage: ./scripts/extract-python.sh

set -euo pipefail

FLOWS_DIR="${FLOWS_DIR:-objects/data-flows}"
JQ_FILTER='.. | .config? | select(type=="object") | .script? | select(. != null)'

command -v jq >/dev/null || { echo "jq not found" >&2; exit 1; }
[[ -d "$FLOWS_DIR" ]] || { echo "No data-flows dir: $FLOWS_DIR" >&2; exit 0; }

found=0
for flow in "$FLOWS_DIR"/*.json; do
  [[ -e "$flow" ]] || continue
  name="$(basename "$flow" .json)"
  out="$FLOWS_DIR/$name.py"

  # jq writes directly to the .py file - same as the working manual command.
  jq -r "$JQ_FILTER" "$flow" > "$out" 2>/dev/null || true

  # Keep the file only if it actually got content. 
  if [[ -s "$out" ]]; then
    echo "Extracted: $out"
    found=$((found+1))
  else
    rm -f "$out"
  fi
done

[[ "$found" -eq 0 ]] && echo "No Python scripts found in $FLOWS_DIR" || echo "Done: $found file(s)."
