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
OUTPUT_JSONL="$OUT_DIR/nuclei.findings.jsonl"
NUCLEI_LOG="$OUT_DIR/nuclei.log"
STATUS_FILE="$OUT_DIR/nuclei.status.json"

# Configuration from environment
TIMEOUT_SECONDS="${NUCLEI_TIMEOUT_SECONDS:-1800}"
RATE_LIMIT="${NUCLEI_RATE_LIMIT:-50}"
RETRIES="${NUCLEI_RETRIES:-2}"
ALLOW_TIMEOUT="${NUCLEI_ALLOW_TIMEOUT:-false}"
UPDATE_TEMPLATES="${NUCLEI_UPDATE_TEMPLATES:-false}"

log "Nuclei configuration:"
log "  Timeout: ${TIMEOUT_SECONDS}s"
log "  Rate limit: $RATE_LIMIT"
log "  Retries: $RETRIES"
log "  Allow timeout: $ALLOW_TIMEOUT"

# Optional template update (costly, off by default)
if [[ "$UPDATE_TEMPLATES" == "true" ]]; then
  log "Updating nuclei templates..."
  nuclei -update-templates -silent || true
fi

# Check if there are targets
if [[ ! -s "$TARGETS" ]]; then
  log "No targets for nuclei, skipping..."
  echo '{"status":"skipped","reason":"no_targets","duration_seconds":0,"findings":0}' > "$STATUS_FILE"
  exit 0
fi

TARGET_COUNT=$(wc -l < "$TARGETS" | tr -d ' ')
log "Targets: $TARGET_COUNT URLs"

run_nuclei() {
  local attempt=$1
  log "Nuclei attempt $attempt/$RETRIES..."

  START_TIME=$(date +%s)

  # Run nuclei in background with PID tracking
  set +e
  nuclei -silent -l "$TARGETS" \
    -rl "$RATE_LIMIT" \
    -jsonl -o "$OUTPUT_JSONL" \
    > "$NUCLEI_LOG" 2>&1 &
  NUCLEI_PID=$!
  set -e

  log "Nuclei running with PID $NUCLEI_PID, timeout in ${TIMEOUT_SECONDS}s..."

  # Watchdog loop - check every 5 seconds
  ELAPSED=0
  while kill -0 "$NUCLEI_PID" 2>/dev/null; do
    sleep 5
    ELAPSED=$((ELAPSED + 5))

    if [[ $ELAPSED -ge $TIMEOUT_SECONDS ]]; then
      log_error "⏱️  Nuclei TIMEOUT reached (${TIMEOUT_SECONDS}s), killing PID $NUCLEI_PID..."

      # Try graceful termination first
      kill -TERM "$NUCLEI_PID" 2>/dev/null || true
      sleep 3

      # Force kill if still alive
      if kill -0 "$NUCLEI_PID" 2>/dev/null; then
        log_error "Force killing nuclei (SIGKILL)..."
        kill -9 "$NUCLEI_PID" 2>/dev/null || true
      fi

      wait "$NUCLEI_PID" 2>/dev/null || true

      END_TIME=$(date +%s)
      DURATION=$((END_TIME - START_TIME))

      echo "{\"status\":\"timeout\",\"duration_seconds\":$DURATION,\"timeout_seconds\":$TIMEOUT_SECONDS,\"attempt\":$attempt,\"killed\":true}" > "$STATUS_FILE"
      return 124
    fi

    # Progress indicator every minute
    if [[ $((ELAPSED % 60)) -eq 0 ]]; then
      log "Nuclei still running... ${ELAPSED}s elapsed (timeout at ${TIMEOUT_SECONDS}s)"
    fi
  done

  # Nuclei finished naturally, get exit code
  wait "$NUCLEI_PID"
  EXIT_CODE=$?

  END_TIME=$(date +%s)
  DURATION=$((END_TIME - START_TIME))

  # Check exit status
  if [[ $EXIT_CODE -eq 0 ]]; then
    FINDINGS=$(test -f "$OUTPUT_JSONL" && wc -l < "$OUTPUT_JSONL" | tr -d ' ' || echo 0)
    log "✓ Nuclei completed successfully in ${DURATION}s, findings: $FINDINGS"
    echo "{\"status\":\"success\",\"duration_seconds\":$DURATION,\"findings\":$FINDINGS,\"attempt\":$attempt}" > "$STATUS_FILE"
    return 0
  else
    log_error "Nuclei failed with exit code $EXIT_CODE (attempt $attempt)"
    echo "{\"status\":\"error\",\"exit_code\":$EXIT_CODE,\"duration_seconds\":$DURATION,\"attempt\":$attempt}" > "$STATUS_FILE"
    return $EXIT_CODE
  fi
}

# Retry logic
FINAL_EXIT=1
for attempt in $(seq 1 "$RETRIES"); do
  if run_nuclei "$attempt"; then
    FINAL_EXIT=0
    break
  else
    LAST_EXIT=$?
    if [[ $attempt -lt $RETRIES ]]; then
      log "Retrying in 10 seconds..."
      sleep 10
    else
      FINAL_EXIT=$LAST_EXIT
    fi
  fi
done

# Handle final result
if [[ $FINAL_EXIT -eq 0 ]]; then
  exit 0
elif [[ $FINAL_EXIT -eq 124 ]]; then
  # Timeout
  if [[ "$ALLOW_TIMEOUT" == "true" ]]; then
    log "Nuclei timeout allowed by config, continuing with degraded results..."
    PARTIAL_FINDINGS=$(test -f "$OUTPUT_JSONL" && wc -l < "$OUTPUT_JSONL" | tr -d ' ' || echo 0)
    echo "{\"status\":\"timeout_allowed\",\"timeout_seconds\":$TIMEOUT_SECONDS,\"findings\":$PARTIAL_FINDINGS,\"note\":\"degraded\"}" > "$STATUS_FILE"
    exit 0
  else
    log_error "Nuclei timeout not allowed, failing pipeline"
    exit 124
  fi
else
  log_error "Nuclei failed after $RETRIES attempts"
  exit $FINAL_EXIT
fi
