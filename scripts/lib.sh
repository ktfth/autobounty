#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "[$(date +'%F %T')] $*"
}

log_error() {
  echo "[$(date +'%F %T')] ERROR: $*" >&2
}

require_file() {
  [[ -f "$1" ]] || { log_error "Missing file: $1"; exit 1; }
}

require_dir() {
  [[ -d "$1" ]] || { log_error "Missing dir: $1"; exit 1; }
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || { log_error "Missing command: $1"; exit 1; }
}

check_crlf() {
  local file="$1"
  if file "$file" 2>/dev/null | grep -q "CRLF"; then
    return 0  # has CRLF
  fi
  if grep -q $'\r' "$file" 2>/dev/null; then
    return 0  # has CRLF
  fi
  return 1  # no CRLF
}

is_writable_dir() {
  [[ -d "$1" ]] && [[ -w "$1" ]]
}

