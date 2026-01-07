#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib.sh"

OUT_DIR="${1:-}"
if [[ -z "$OUT_DIR" ]]; then
  log_error "Usage: $0 <output_dir>"
  exit 1
fi

SUBDOMAINS="$OUT_DIR/subdomains.txt"
ARCHIVE_URLS="$OUT_DIR/archive_urls.txt"

if [[ ! -s "$SUBDOMAINS" ]]; then
  log "No subdomains found, skipping archive fetching."
  exit 0
fi

log "Fetching historical URLs from archives (gau)..."
gau --threads 10 < "$SUBDOMAINS" > "$ARCHIVE_URLS" || true

URL_COUNT=$(wc -l < "$ARCHIVE_URLS" | tr -d ' ' || echo 0)
log "✓ Found $URL_COUNT historical URLs."
