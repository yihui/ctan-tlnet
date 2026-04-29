#!/usr/bin/env bash
# Cloudflare Pages build script.
#
# Downloads the latest CTAN tlnet archive from the most recent GitHub Release
# and extracts it into the Pages output directory (dist/).  The _redirects file
# committed to this repository is also copied into dist/ so Cloudflare Pages
# can redirect requests for large files to the appropriate GitHub Release asset.
#
# Build command (set in Cloudflare Pages dashboard or wrangler.toml):
#   bash deploy.sh
# Output directory: dist

set -euo pipefail

# ---------------------------------------------------------------------------
# 1. Ensure zstd is available (Cloudflare Pages build image is Ubuntu-based)
# ---------------------------------------------------------------------------
if ! command -v zstd &>/dev/null; then
  echo "Installing zstd..."
  apt-get install -y zstd 2>/dev/null \
    || sudo apt-get install -y zstd
fi

# ---------------------------------------------------------------------------
# 2. Determine the GitHub repository (owner/repo)
# ---------------------------------------------------------------------------
REPO="${GITHUB_REPOSITORY:-}"
if [ -z "$REPO" ]; then
  # Derive from git remote when running outside of GitHub Actions
  REPO=$(git remote get-url origin 2>/dev/null \
    | sed 's|.*github\.com[:/]\(.*\)\.git|\1|; s|.*github\.com[:/]\(.*\)|\1|')
fi

if [ -z "$REPO" ]; then
  echo "ERROR: could not determine GitHub repository" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 3. Download and extract the latest release archive
# ---------------------------------------------------------------------------
mkdir -p dist

echo "Downloading tlnet.tar.zst from latest release of $REPO ..."
curl -fsSL "https://github.com/${REPO}/releases/latest/download/tlnet.tar.zst" \
  | tar -C dist --zstd -xf -

# ---------------------------------------------------------------------------
# 4. Copy _redirects into the output directory
#    (redirects large files to the matching GitHub Release asset)
# ---------------------------------------------------------------------------
if [ -f "_redirects" ]; then
  cp _redirects dist/
  echo "_redirects: $(wc -l < _redirects) entries"
fi

echo "Build complete: $(find dist -type f | wc -l) files in dist/"
