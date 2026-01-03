#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib.sh"

OUT_DIR="${1:-}"
if [[ -z "$OUT_DIR" ]]; then
  log_error "Usage: $0 <output_dir>"
  exit 1
fi

require_dir "$OUT_DIR"

HTTPX_JSON="$OUT_DIR/httpx.json"
TECH_JSON="$OUT_DIR/technologies.json"
TARGETS_JSON="$OUT_DIR/targets_analysis.json"

log "=== TECHNOLOGY ANALYSIS ==="

# Check if httpx results exist
if [[ ! -s "$HTTPX_JSON" ]]; then
  log "No httpx results, skipping analysis..."
  echo '{"status":"skipped","reason":"no_httpx_results"}' > "$OUT_DIR/tech_analysis.status.json"
  exit 0
fi

# Extract technologies from httpx
log "Extracting technologies from httpx results..."
jq -r '[.[] | select(.technologies != null and (.technologies | length) > 0) | {url: .url, title: .title, status_code: .status_code, server: .server, technologies: .technologies, content_type: .content_type}]' \
  "$HTTPX_JSON" > "$TECH_JSON" 2>/dev/null || echo '[]' > "$TECH_JSON"

TECH_COUNT=$(jq 'length' "$TECH_JSON" 2>/dev/null || echo 0)
log "✓ Technologies detected on $TECH_COUNT URLs"

# Create comprehensive targets analysis
log "Building comprehensive targets analysis..."
jq -r '[.[] | {
  url: .url,
  title: .title // "No title",
  status_code: .status_code,
  server: .server // "Unknown",
  content_type: .content_type // "Unknown",
  technologies: .technologies // [],
  is_admin: (.title // "" | ascii_downcase | test("admin|dashboard|panel|login|portal|cpanel|plesk|phpmyadmin")),
  is_dev: (.url | test("dev|stag|test|uat|qa|demo"; "i")),
  has_interesting_tech: ((.technologies // []) | map(ascii_downcase) | any(test("wordpress|drupal|joomla|magento|laravel|django|rails|spring|tomcat|jenkins|gitlab|grafana|kibana")))
}]' "$HTTPX_JSON" > "$TARGETS_JSON" 2>/dev/null || echo '[]' > "$TARGETS_JSON"

# Count interesting targets
ADMIN_COUNT=$(jq '[.[] | select(.is_admin == true)] | length' "$TARGETS_JSON" 2>/dev/null || echo 0)
DEV_COUNT=$(jq '[.[] | select(.is_dev == true)] | length' "$TARGETS_JSON" 2>/dev/null || echo 0)
INTERESTING_COUNT=$(jq '[.[] | select(.has_interesting_tech == true)] | length' "$TARGETS_JSON" 2>/dev/null || echo 0)

log "✓ Analysis complete:"
log "  - Potential admin panels: $ADMIN_COUNT"
log "  - Dev/staging environments: $DEV_COUNT"
log "  - Interesting technologies: $INTERESTING_COUNT"

echo "{\"status\":\"success\",\"tech_urls\":$TECH_COUNT,\"admin_panels\":$ADMIN_COUNT,\"dev_envs\":$DEV_COUNT,\"interesting_tech\":$INTERESTING_COUNT}" \
  > "$OUT_DIR/tech_analysis.status.json"

log "=== ANALYSIS COMPLETE ==="
