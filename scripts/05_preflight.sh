#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib.sh"

log "=== RUNNING PREFLIGHT CHECKS ==="

# 1) Check directory permissions
if [[ ! -w "$ROOT_DIR/output" ]]; then
  log_error "Output directory is not writable: $ROOT_DIR/output"
  exit 1
fi
log "✓ Output directory writable"

log "=== PREFLIGHT OK ==="
