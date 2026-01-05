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
  jq -s -r '[.[] | select(.tech != null) | {url: .url, title: .title, status_code: .status_code, server: .server, technologies: .tech}]' \
    "$HTTPX_JSON" > "$TECH_JSON" 2>/dev/null || echo '[]' > "$TECH_JSON"

  TECH_COUNT=$(jq 'length' "$TECH_JSON" 2>/dev/null || echo 0)
  log "✓ Technologies detected on $TECH_COUNT URLs"
fi

# Run gowitness (skip if already done)
if [[ -f "$GOWITNESS_DB" ]] && [[ -d "$SCREENSHOTS_DIR" ]] && [[ -n "$(ls -A "$SCREENSHOTS_DIR" 2>/dev/null)" ]]; then
  log "⚡ Skipping gowitness (cached - screenshots exist)"
  SCREENSHOT_COUNT=$(find "$SCREENSHOTS_DIR" -type f \( -name "*.png" -o -name "*.webp" -o -name "*.jpeg" -o -name "*.jpg" \) | wc -l || echo 0)
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
CHROME_PATH=$(which google-chrome || which google-chrome-stable || which chromium-browser || which chromium || echo "/usr/bin/google-chrome")
log "Using Chrome at: $CHROME_PATH"

gowitness scan file \
  -f "$TARGETS" \
  --screenshot-path "$SCREENSHOTS_DIR" \
  --chrome-path "$CHROME_PATH" \
  --timeout 15 \
  --delay 2 \
  --write-db \
  --write-db-uri "sqlite://$GOWITNESS_DB" \
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
SCREENSHOT_COUNT=$(find "$SCREENSHOTS_DIR" -type f \( -name "*.png" -o -name "*.webp" -o -name "*.jpeg" -o -name "*.jpg" \) 2>/dev/null | wc -l || echo 0)

if [[ $EXIT_CODE -eq 0 ]] || [[ $SCREENSHOT_COUNT -gt 0 ]]; then
  log "✓ gowitness finished (Screenshots: $SCREENSHOT_COUNT)"

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
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 0; background: #1a1a1a; color: #eee; }
        header { background: #333; padding: 20px; text-align: center; border-bottom: 2px solid #555; }
        h1 { margin: 0; color: #00d2ff; }
        .stats { margin-top: 10px; font-size: 0.9em; opacity: 0.8; }
        .gallery { display: grid; grid-template-columns: repeat(auto-fill, minmax(450px, 1fr)); gap: 25px; padding: 30px; }
        .screenshot { background: #2d2d2d; border-radius: 12px; overflow: hidden; box-shadow: 0 10px 20px rgba(0,0,0,0.5); transition: transform 0.2s; border: 1px solid #444; }
        .screenshot:hover { transform: translateY(-5px); border-color: #00d2ff; }
        .screenshot-img-container { width: 100%; aspect-ratio: 16/10; overflow: hidden; background: #000; display: flex; align-items: center; justify-content: center; }
        .screenshot img { width: 100%; height: 100%; object-fit: cover; }
        .info { padding: 15px; }
        .info h3 { margin: 0; font-size: 14px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; color: #fff; }
        .info a { color: #00d2ff; text-decoration: none; display: block; margin-top: 8px; font-size: 12px; opacity: 0.7; }
        .info a:hover { opacity: 1; text-decoration: underline; }
    </style>
</head>
<body>
    <header>
        <h1>Visual Reconnaissance Gallery</h1>
        <div class="stats">
            <strong>Total Captured:</strong> SCREENSHOT_COUNT_PLACEHOLDER
        </div>
    </header>
    <div class="gallery">
HTMLEOF

  # Add each screenshot
  find "$SCREENSHOTS_DIR" -type f \( -name "*.png" -o -name "*.webp" -o -name "*.jpeg" -o -name "*.jpg" \) | sort | while read -r screenshot; do
    filename=$(basename "$screenshot")
    # Pretty name: remove common artifacts from gowitness naming
    display_name=$(echo "$filename" | sed 's/https---//' | sed 's/-443//' | sed 's/\.[^.]*$//' | sed 's/-/./g')

    cat >> "$OUT_DIR/report.html" <<ITEMEOF
        <div class="screenshot">
            <div class="screenshot-img-container">
                <a href="screenshots/$filename" target="_blank">
                    <img src="screenshots/$filename" alt="Screenshot" loading="lazy">
                </a>
            </div>
            <div class="info">
                <h3>$display_name</h3>
                <a href="screenshots/$filename" target="_blank">Open Full Image</a>
            </div>
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
