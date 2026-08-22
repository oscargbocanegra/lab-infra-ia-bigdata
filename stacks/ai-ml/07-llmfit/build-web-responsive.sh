#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$ROOT_DIR/web-responsive"
DEST="/srv/fastdata/llmfit-web-responsive"
cd "$APP_DIR"
npm ci
npm run build
rm -rf "$DEST"
install -d "$DEST"
cp -a dist/. "$DEST/"
printf 'Dashboard moderno instalado en %s\n' "$DEST"
