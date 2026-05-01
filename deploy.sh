#!/usr/bin/env bash
# Cloudflare Pages build script.
#
# tlnet.tar.zst (uploaded to GitHub Releases by create_release.sh) already
# contains the full site: all CTAN files (except large ones served via
# GitHub Releases directly), pre-built index.html for every subdirectory,
# and _redirects.  This script just downloads and extracts it.
#
# Tools available on the Cloudflare Pages build image: zstd, jq, curl, git.
# No apt-get or sudo available.
#
# Build command : bash deploy.sh    (configured via [build] in wrangler.toml)
# Output directory: dist            (configured via pages_build_output_dir)

set -euo pipefail

# ---------------------------------------------------------------------------
# 1. Determine the GitHub repository (owner/repo)
# ---------------------------------------------------------------------------
REPO="${GITHUB_REPOSITORY:-}"
if [ -z "$REPO" ]; then
  REPO=$(git remote get-url origin 2>/dev/null \
    | sed 's|.*github\.com[:/]\(.*\)\.git|\1|; s|.*github\.com[:/]\(.*\)|\1|')
fi
if [ -z "$REPO" ]; then
  echo "ERROR: could not determine GitHub repository" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 2. Determine which release holds the current archive
# ---------------------------------------------------------------------------
RECORD_FILE="release-record.json"
archive_release=$(jq -r '.archive.release // "v1"' "$RECORD_FILE")

# ---------------------------------------------------------------------------
# 3. Download and extract the archive
# ---------------------------------------------------------------------------
mkdir -p dist

echo "Downloading tlnet.tar.zst from release $archive_release of $REPO ..."
curl -fsSL "https://github.com/${REPO}/releases/download/${archive_release}/tlnet.tar.zst" \
  | tar -C dist --zstd -xf -

echo "Build complete: $(find dist -type f | wc -l) files in dist/"

