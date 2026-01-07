#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib.sh"

OUT_DIR="${1:-}"
if [[ -z "$OUT_DIR" ]]; then
  if [[ -f "$ROOT_DIR/output/LAST_RUN" ]]; then
    RUN_ID=$(cat "$ROOT_DIR/output/LAST_RUN")
    OUT_DIR="$ROOT_DIR/output/$RUN_ID"
  else
    log_error "No output directory specified and no LAST_RUN found."
    exit 1
  fi
fi

REPORT_FILE="$OUT_DIR/REPORT.md"
log "Building report at $REPORT_FILE..."

{
  echo "# Reconnaissance Report: $(basename "$OUT_DIR")"
  echo "Generated on: $(date)"
  echo ""
  echo "## Summary"
  echo "- Subdomains found: $(wc -l < "$OUT_DIR/subdomains.txt" || echo 0)"
  echo "- Alive URLs: $(wc -l < "$OUT_DIR/alive.urls.txt" || echo 0)"
  echo ""
  echo "## Top Prioritized Assets"
  if [[ -f "$OUT_DIR/prioritized_assets.json" ]]; then
    echo "| Host | Score | Tags |"
    echo "| :--- | :--- | :--- |"
    jq -r '.[:10] | .[] | "| \(.host) | \(.priority_score) | \(.priority_tags | join(", ")) |"' "$OUT_DIR/prioritized_assets.json"
  fi
  echo ""
  echo "## Visual Evidence"
  echo "Screenshots are available in the project root /screenshots directory."
} > "$REPORT_FILE"

log "✓ Report generated."
