#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib.sh"

log "=== PREFLIGHT CHECKS ==="

# 1) Check for CRLF in shell scripts
log "Checking for CRLF in scripts..."
CRLF_FOUND=0
for script in "$ROOT_DIR/scripts"/*.sh; do
  [[ -f "$script" ]] || continue
  if check_crlf "$script"; then
    log_error "CRLF detected in: $script"
    CRLF_FOUND=1
  fi
done

if [[ $CRLF_FOUND -eq 1 ]]; then
  log_error "CRLF line endings detected in shell scripts!"
  log_error "Fix with: git add --renormalize . && git commit -m 'Normalize line endings'"
  log_error "Or manually: dos2unix scripts/*.sh"
  exit 1
fi
log "✓ No CRLF found in scripts"

# 2) Check required commands
log "Checking required dependencies..."
for cmd in subfinder httpx naabu jq; do
  require_command "$cmd"
  log "✓ $cmd: $(command -v $cmd)"
done

# 3) Check input scope file
log "Checking input scope..."
SCOPE_FILE="$ROOT_DIR/input/scope.txt"
require_file "$SCOPE_FILE"

if [[ ! -s "$SCOPE_FILE" ]]; then
  log_error "Scope file is empty: $SCOPE_FILE"
  exit 1
fi

SCOPE_LINES=$(wc -l < "$SCOPE_FILE" | tr -d ' ')
log "✓ Scope file: $SCOPE_LINES domains"

# 4) Check output directory is writable
log "Checking output directory..."
mkdir -p "$ROOT_DIR/output"
if ! is_writable_dir "$ROOT_DIR/output"; then
  log_error "Output directory is not writable: $ROOT_DIR/output"
  exit 1
fi
log "✓ Output directory writable"

log "=== PREFLIGHT OK ==="
