#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib.sh"

# Run preflight checks first
log "Running preflight checks..."
bash "$ROOT_DIR/scripts/05_preflight.sh"

# Resume mode: continue from LAST_RUN if RESUME=true
RESUME="${RESUME:-false}"
if [[ "$RESUME" == "true" ]] && [[ -f "$ROOT_DIR/output/LAST_RUN" ]]; then
  RUN_ID="$(cat "$ROOT_DIR/output/LAST_RUN")"
  log "=== RESUME MODE: Continuing RUN_ID=$RUN_ID ==="
else
  RUN_ID="$(date +%Y%m%d_%H%M%S)"
  log "=== NEW RUN: RUN_ID=$RUN_ID ==="
fi

OUT_DIR="$ROOT_DIR/output/$RUN_ID"
mkdir -p "$OUT_DIR"

SCOPE_FILE="$ROOT_DIR/input/scope.txt"
log "OUT_DIR=$OUT_DIR"

# 1) Normalize scope
log "Normalizing scope..."
cat "$SCOPE_FILE" | sed 's#https\?://##g' | sed 's#/.*$##g' | sed 's/:.*$//g' | awk 'NF' | sort -u > "$OUT_DIR/scope.normalized.txt"
SCOPE_COUNT=$(wc -l < "$OUT_DIR/scope.normalized.txt" | tr -d ' ')
log "✓ Normalized scope: $SCOPE_COUNT domains"

# 2) Subdomain enumeration
log "Subfinder enumeration..."
subfinder -silent -dL "$OUT_DIR/scope.normalized.txt" | sort -u > "$OUT_DIR/subdomains.txt"
SUB_COUNT=$(wc -l < "$OUT_DIR/subdomains.txt" | tr -d ' ')
log "✓ Subdomains found: $SUB_COUNT"

# 3) Httpx Probing (Enhanced)
log "Httpx probing + tech detection (Enhanced)..."
httpx -silent -l "$OUT_DIR/subdomains.txt" \
  -json \
  -title -tech-detect -status-code -content-type -server \
  -favicon -jarm -hash md5,mmh3,sha256 \
  -tls-grab -csp-probe \
  -o "$OUT_DIR/httpx.json"

jq -r '.url' "$OUT_DIR/httpx.json" 2>/dev/null | sort -u > "$OUT_DIR/alive.urls.txt" || echo -n "" > "$OUT_DIR/alive.urls.txt"
ALIVE_COUNT=$(wc -l < "$OUT_DIR/alive.urls.txt" | tr -d ' ')
log "✓ Alive URLs: $ALIVE_COUNT"

# 4) Archive Fetching
log "Fetching historical data from archives..."
bash "$ROOT_DIR/scripts/12_fetch_archives.sh" "$OUT_DIR"

# 5) Asset Prioritization
log "Running asset prioritization model..."
python3 "$ROOT_DIR/scripts/15_prioritize.py" "$OUT_DIR"

# 6) Visual Reconnaissance (gowitness)
log "Running visual reconnaissance..."
bash "$ROOT_DIR/scripts/15_run_gowitness.sh" "$OUT_DIR"

log "=== PIPELINE COMPLETE ==="
echo "$RUN_ID" > "$ROOT_DIR/output/LAST_RUN"
