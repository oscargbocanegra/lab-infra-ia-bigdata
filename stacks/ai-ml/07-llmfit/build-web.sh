#!/usr/bin/env bash
set -euo pipefail

UPSTREAM_COMMIT="e11c6e1925118423ce20aeb8bc20c2ffcc07081b"
WORKDIR="${TMPDIR:-/tmp}/llmfit-upstream-${UPSTREAM_COMMIT}"
DEST="/srv/fastdata/llmfit-web"

if [ ! -d "$WORKDIR/.git" ]; then
  git clone https://github.com/AlexsJones/llmfit.git "$WORKDIR"
fi
git -C "$WORKDIR" fetch --quiet origin "$UPSTREAM_COMMIT"
git -C "$WORKDIR" checkout --quiet "$UPSTREAM_COMMIT"
cd "$WORKDIR/llmfit-web"
npm ci
npm run build
rm -rf "$DEST"
install -d "$DEST"
cp -a dist/. "$DEST/"
printf 'Dashboard instalado en %s (commit %s)\n' "$DEST" "$UPSTREAM_COMMIT"
