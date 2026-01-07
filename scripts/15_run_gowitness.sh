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
  log "No targets for gowitness, skipping..."
  exit 0
fi

log "Running gowitness visual recon..."
gowitness scan file -f "$TARGETS" --threads 5 --write-db --write-db-uri "sqlite://$ROOT_DIR/gowitness.sqlite3" --screenshot-path "$ROOT_DIR/screenshots" || true

log "✓ Visual recon complete."
