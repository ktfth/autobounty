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

TARGETS="$OUT_DIR/alive.urls.txt"
HTTPX_JSON="$OUT_DIR/httpx.json"
SCREENSHOTS_DIR="$OUT_DIR/screenshots"
TECH_JSON="$OUT_DIR/technologies.json"
GOWITNESS_DB="$OUT_DIR/gowitness.sqlite3"

log "=== GOWITNESS VISUAL RECON ==="

# Check if there are targets
if [[ ! -s "$TARGETS" ]]; then
  log "No targets for screenshots, skipping..."
  echo '{"status":"skipped","reason":"no_targets"}' > "$OUT_DIR/screenshots.status.json"
  exit 0
fi

TARGET_COUNT=$(wc -l < "$TARGETS" | tr -d ' ')
log "Targets: $TARGET_COUNT URLs"

# Extract technologies from httpx
if [[ -f "$HTTPX_JSON" ]]; then
  log "Extracting technologies from httpx results..."
  jq -r '[.[] | select(.technologies != null) | {url: .url, title: .title, status_code: .status_code, server: .server, technologies: .technologies}]' \
    "$HTTPX_JSON" > "$TECH_JSON" 2>/dev/null || echo '[]' > "$TECH_JSON"

  TECH_COUNT=$(jq 'length' "$TECH_JSON" 2>/dev/null || echo 0)
  log "✓ Technologies detected on $TECH_COUNT URLs"
fi

# Run gowitness (skip if already done)
if [[ -f "$GOWITNESS_DB" ]] && [[ -d "$SCREENSHOTS_DIR" ]]; then
  log "⚡ Skipping gowitness (cached - screenshots exist)"
  SCREENSHOT_COUNT=$(find "$SCREENSHOTS_DIR" -name "*.png" 2>/dev/null | wc -l || echo 0)
  echo "{\"status\":\"cached\",\"screenshots\":$SCREENSHOT_COUNT,\"screenshots_dir\":\"screenshots/\"}" > "$OUT_DIR/screenshots.status.json"
  exit 0
fi

mkdir -p "$SCREENSHOTS_DIR"

log "Running gowitness (screenshots)..."
START_TIME=$(date +%s)

# gowitness scan options:
# scan: scan mode
# file: read URLs from file
# -f: input file
# --screenshot-path: where to save screenshots
# --chrome-path: chromium browser location

set +e
cd "$OUT_DIR"

# Find chromium executable
CHROME_PATH=$(which chromium-browser || which chromium || which google-chrome || echo "/usr/bin/chromium-browser")
log "Using Chrome at: $CHROME_PATH"

gowitness scan file \
  -f "$TARGETS" \
  --screenshot-path "$SCREENSHOTS_DIR" \
  --chrome-path "$CHROME_PATH" \
  --timeout 10 \
  --delay 1 \
  > "$OUT_DIR/gowitness.log" 2>&1
EXIT_CODE=$?
set -e

# Show error log if failed
if [[ $EXIT_CODE -ne 0 ]]; then
  log_error "gowitness failed, showing last 20 lines of log:"
  tail -n 20 "$OUT_DIR/gowitness.log" | while IFS= read -r line; do
    log_error "  $line"
  done
fi

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Count screenshots (even if some failed)
SCREENSHOT_COUNT=$(find "$SCREENSHOTS_DIR" -name "*.png" 2>/dev/null | wc -l || echo 0)

if [[ $EXIT_CODE -eq 0 ]]; then
  log "✓ gowitness completed in ${DURATION}s"

  # Generate simple HTML report listing all screenshots
  log "Generating HTML report..."

  cat > "$OUT_DIR/report.html" <<'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Screenshot Gallery</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        h1 { color: #333; }
        .gallery { display: grid; grid-template-columns: repeat(auto-fill, minmax(400px, 1fr)); gap: 20px; }
        .screenshot { background: white; padding: 15px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .screenshot img { width: 100%; border: 1px solid #ddd; border-radius: 4px; }
        .screenshot h3 { margin: 10px 0 5px 0; font-size: 14px; word-wrap: break-word; }
        .screenshot a { color: #0066cc; text-decoration: none; }
        .screenshot a:hover { text-decoration: underline; }
    </style>
</head>
<body>
    <h1>Visual Reconnaissance Gallery</h1>
    <p><strong>Total Screenshots:</strong> SCREENSHOT_COUNT_PLACEHOLDER</p>
    <div class="gallery">
HTMLEOF

  # Add each screenshot
  for screenshot in "$SCREENSHOTS_DIR"/*.png; do
    [[ -f "$screenshot" ]] || continue
    filename=$(basename "$screenshot")
    # Extract URL from filename (gowitness uses URL-based naming)
    url_hint=$(echo "$filename" | sed 's/\.png$//' | sed 's/_/:/1' | sed 's/_/\//g')

    cat >> "$OUT_DIR/report.html" <<ITEMEOF
        <div class="screenshot">
            <a href="screenshots/$filename" target="_blank">
                <img src="screenshots/$filename" alt="Screenshot" loading="lazy">
            </a>
            <h3><a href="screenshots/$filename" target="_blank">$filename</a></h3>
        </div>
ITEMEOF
  done

  cat >> "$OUT_DIR/report.html" <<'HTMLEOF'
    </div>
</body>
</html>
HTMLEOF

  # Replace count placeholder
  sed -i "s/SCREENSHOT_COUNT_PLACEHOLDER/$SCREENSHOT_COUNT/g" "$OUT_DIR/report.html" 2>/dev/null || \
    sed -i '' "s/SCREENSHOT_COUNT_PLACEHOLDER/$SCREENSHOT_COUNT/g" "$OUT_DIR/report.html" 2>/dev/null || true

  echo "{\"status\":\"success\",\"duration_seconds\":$DURATION,\"screenshots\":$SCREENSHOT_COUNT,\"report\":\"report.html\"}" \
    > "$OUT_DIR/screenshots.status.json"

  log "📸 Screenshots: $SCREENSHOT_COUNT"
  log "📊 Report: $OUT_DIR/report.html"

else
  log_error "gowitness failed with exit code $EXIT_CODE"

  # Partial success if we have some screenshots
  if [[ $SCREENSHOT_COUNT -gt 0 ]]; then
    log "⚠️  Partial success: $SCREENSHOT_COUNT screenshots captured before failure"

    # Generate simple report with what we have
    cat > "$OUT_DIR/report.html" <<EOF
<!DOCTYPE html>
<html><head><meta charset="UTF-8"><title>Partial Results</title></head>
<body><h1>Partial Screenshot Results</h1>
<p>gowitness encountered errors but captured $SCREENSHOT_COUNT screenshots.</p>
<p>Check <code>gowitness.log</code> for details.</p>
<ul>
$(for s in "$SCREENSHOTS_DIR"/*.png; do [[ -f "$s" ]] && echo "<li><a href=\"screenshots/$(basename "$s")\">$(basename "$s")</a></li>"; done)
</ul>
</body></html>
EOF

    echo "{\"status\":\"partial\",\"exit_code\":$EXIT_CODE,\"duration_seconds\":$DURATION,\"screenshots\":$SCREENSHOT_COUNT}" \
      > "$OUT_DIR/screenshots.status.json"
  else
    echo "{\"status\":\"error\",\"exit_code\":$EXIT_CODE,\"duration_seconds\":$DURATION,\"log\":\"gowitness.log\"}" \
      > "$OUT_DIR/screenshots.status.json"

    log_error "No screenshots captured. Check $OUT_DIR/gowitness.log for errors."
    log_error "Common issues:"
    log_error "  - Chrome/Chromium not properly installed"
    log_error "  - Network connectivity problems"
    log_error "  - Invalid URLs in target file"
    exit $EXIT_CODE
  fi
fi

log "=== VISUAL RECON COMPLETE ==="
