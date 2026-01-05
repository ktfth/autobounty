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

# 1) Normaliza escopo (cache: skip se já existe)
if [[ -f "$OUT_DIR/scope.normalized.txt" ]]; then
  log "⚡ Skipping scope normalization (cached)"
  SCOPE_COUNT=$(wc -l < "$OUT_DIR/scope.normalized.txt" | tr -d ' ')
else
  log "Normalizing scope..."
  cat "$SCOPE_FILE" \
    | sed 's#https\?://##g' \
    | sed 's#/.*$##g' \
    | sed 's/:.*$//g' \
    | awk 'NF' \
    | sort -u > "$OUT_DIR/scope.normalized.txt"
  SCOPE_COUNT=$(wc -l < "$OUT_DIR/scope.normalized.txt" | tr -d ' ')
  log "✓ Normalized scope: $SCOPE_COUNT domains"
fi

# 2) Subdomain enum (passivo) - cache
if [[ -f "$OUT_DIR/subdomains.txt" ]]; then
  log "⚡ Skipping subfinder (cached)"
  SUB_COUNT=$(wc -l < "$OUT_DIR/subdomains.txt" | tr -d ' ')
else
  log "Subfinder enumeration..."
  subfinder -silent -dL "$OUT_DIR/scope.normalized.txt" \
    | sort -u > "$OUT_DIR/subdomains.txt"
  SUB_COUNT=$(wc -l < "$OUT_DIR/subdomains.txt" | tr -d ' ')
  log "✓ Subdomains found: $SUB_COUNT"
fi

# 3) Alive check + enrich (tech detection) - cache
if [[ -f "$OUT_DIR/httpx.json" ]]; then
  log "⚡ Skipping httpx (cached)"
  jq -r '.url' "$OUT_DIR/httpx.json" 2>/dev/null | sort -u > "$OUT_DIR/alive.urls.txt" || echo -n "" > "$OUT_DIR/alive.urls.txt"
  jq -r '.host' "$OUT_DIR/httpx.json" 2>/dev/null | sort -u > "$OUT_DIR/alive.hosts.txt" || echo -n "" > "$OUT_DIR/alive.hosts.txt"
  ALIVE_COUNT=$(wc -l < "$OUT_DIR/alive.urls.txt" | tr -d ' ')
else
  log "Httpx probing + tech detection..."
  httpx -silent -l "$OUT_DIR/subdomains.txt" \
    -json \
    -title -tech-detect -status-code -content-type -server \
    -o "$OUT_DIR/httpx.json"

  jq -r '.url' "$OUT_DIR/httpx.json" 2>/dev/null | sort -u > "$OUT_DIR/alive.urls.txt" || echo -n "" > "$OUT_DIR/alive.urls.txt"
  jq -r '.host' "$OUT_DIR/httpx.json" 2>/dev/null | sort -u > "$OUT_DIR/alive.hosts.txt" || echo -n "" > "$OUT_DIR/alive.hosts.txt"

  ALIVE_COUNT=$(wc -l < "$OUT_DIR/alive.urls.txt" | tr -d ' ')
  log "✓ Alive URLs: $ALIVE_COUNT"
fi

# 4) Port scan (controle de taxa) - cache
if [[ -f "$OUT_DIR/naabu.json" ]]; then
  log "⚡ Skipping naabu (cached)"
  jq -r '.host + ":" + (.port|tostring)' "$OUT_DIR/naabu.json" 2>/dev/null \
    | sort -u > "$OUT_DIR/open.ports.txt" || echo -n "" > "$OUT_DIR/open.ports.txt"
  PORTS_COUNT=$(wc -l < "$OUT_DIR/open.ports.txt" | tr -d ' ')
else
  log "Naabu port scanning..."
  MAX_RATE="${MAX_PORT_SCAN_RATE:-1000}"
  naabu -silent -list "$OUT_DIR/alive.hosts.txt" \
    -rate "$MAX_RATE" \
    -json -o "$OUT_DIR/naabu.json" || true

  jq -r '.host + ":" + (.port|tostring)' "$OUT_DIR/naabu.json" 2>/dev/null \
    | sort -u > "$OUT_DIR/open.ports.txt" || echo -n "" > "$OUT_DIR/open.ports.txt"

  PORTS_COUNT=$(wc -l < "$OUT_DIR/open.ports.txt" | tr -d ' ')
  log "✓ Open ports: $PORTS_COUNT"
fi

# 5) Technology extraction and analysis
log "Extracting technologies and building analysis..."
bash "$ROOT_DIR/scripts/15_analyze_tech.sh" "$OUT_DIR"

# 6) Visual Reconnaissance (gowitness)
log "Running visual reconnaissance..."
bash "$ROOT_DIR/scripts/15_run_gowitness.sh" "$OUT_DIR"

log "=== PIPELINE COMPLETE ==="
echo "$RUN_ID" > "$ROOT_DIR/output/LAST_RUN"

log "Results:"
log "  - Subdomains: $SUB_COUNT"
log "  - Alive URLs: $ALIVE_COUNT"
log "  - Open Ports: $PORTS_COUNT"
log "  - Technologies analyzed: $OUT_DIR/technologies.json"
log ""
log "Next steps:"
log "  1. Generate report: bash scripts/20_build_reports.sh"
log "  2. Review technologies: $OUT_DIR/technologies.json"
log "  3. Analyze targets: $OUT_DIR/REPORT.md"

