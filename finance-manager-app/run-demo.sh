#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$ROOT_DIR/finance_manager_app"

export PATH="$PATH:/opt/flutter/bin"

cd "$APP_DIR"

echo "[demo] Building Linux release..."
flutter build linux --release

BIN="$APP_DIR/build/linux/x64/release/bundle/finance_manager_app"

if [[ ! -x "$BIN" ]]; then
  echo "[demo] ERROR: binary not found: $BIN" >&2
  exit 1
fi

echo "[demo] Launching: $BIN"
exec "$BIN"
