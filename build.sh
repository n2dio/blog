#!/usr/bin/env bash
# Vercel build: fetch the papyr binary from its GitHub release, then build ./site.
set -euo pipefail

REPO="n2dio/papyr"
# Pin to a tag (e.g. v0.1.0) for reproducible builds, or "latest".
# Override via the PAPYR_VERSION env var in the Vercel project settings.
VERSION="${PAPYR_VERSION:-latest}"
ASSET="papyr-x86_64-unknown-linux-musl.tar.gz"

if [ "$VERSION" = "latest" ]; then
  BASE="https://github.com/$REPO/releases/latest/download"
else
  BASE="https://github.com/$REPO/releases/download/$VERSION"
fi

echo "Installing papyr ($VERSION)..."
curl -fsSL -o "$ASSET" "$BASE/$ASSET"
curl -fsSL -o "$ASSET.sha256" "$BASE/$ASSET.sha256"
sha256sum -c "$ASSET.sha256"
tar -xzf "$ASSET"

echo "Building site..."
./papyr build
