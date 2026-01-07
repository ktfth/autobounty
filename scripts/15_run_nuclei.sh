#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib.sh"

OUT_DIR="${1:-}"
if [[ -z "$OUT_DIR" ]]; then
  log_error "Usage: $0 <output_dir>"
  exit 1
fi

TARGETS="$OUT_DIR/alive.urls.txt"
if [[ ! -s "$TARGETS" ]]; then
  log "No targets for nuclei, skipping..."
  exit 0
fi

log "Running nuclei scans..."
nuclei -silent -l "$TARGETS" -jsonl -o "$OUT_DIR/nuclei.findings.jsonl" -severity low,medium,high,critical || true

log "✓ Nuclei scans complete."
