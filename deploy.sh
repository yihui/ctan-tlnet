#!/usr/bin/env bash
# Cloudflare Pages build script.
#
# 1. Reads release-record.json (committed to this repo) to determine which
#    GitHub Release holds the current tlnet.tar.zst archive.
# 2. Downloads and extracts the archive into dist/.
# 3. Generates _redirects dynamically from release-record.json so that
#    requests for large files are redirected to the correct GitHub Release asset.
# 4. Builds index.html pages for every subdirectory using build_indexes.py.
#
# Build command : bash deploy.sh
# Output directory: dist   (set via pages_build_output_dir in wrangler.toml)

set -euo pipefail

# ---------------------------------------------------------------------------
# 1. Install required tools (Cloudflare Pages build image is Ubuntu-based)
# ---------------------------------------------------------------------------
need_pkg() {
  command -v "$1" &>/dev/null && return 0
  echo "Installing $1 ..."
  apt-get install -y "$1" 2>/dev/null || sudo apt-get install -y "$1"
}
need_pkg zstd
need_pkg jq
# cmark is optional — build_indexes.py already handles its absence gracefully.
if ! command -v cmark &>/dev/null; then
  apt-get install -y cmark 2>/dev/null || sudo apt-get install -y cmark || true
fi

# ---------------------------------------------------------------------------
# 2. Determine the GitHub repository (owner/repo)
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
# 3. Determine which release holds the current archive
# ---------------------------------------------------------------------------
RECORD_FILE="release-record.json"
if [ -f "$RECORD_FILE" ]; then
  archive_release=$(jq -r '.archive.release // "v1"' "$RECORD_FILE")
else
  archive_release="v1"
fi

# ---------------------------------------------------------------------------
# 4. Download and extract the archive
# ---------------------------------------------------------------------------
mkdir -p dist
echo "Downloading tlnet.tar.zst from release $archive_release of $REPO ..."
curl -fsSL "https://github.com/${REPO}/releases/download/${archive_release}/tlnet.tar.zst" \
  | tar -C dist --zstd -xf -

# ---------------------------------------------------------------------------
# 5. Generate _redirects for large files
# ---------------------------------------------------------------------------
echo "Generating _redirects ..."
if [ -f "$RECORD_FILE" ]; then
  jq -r --arg repo "$REPO" '
    .files | to_entries[] |
    "/\(.key)  https://github.com/\($repo)/releases/download/\(.value.release)/\(.value.asset)  302"
  ' "$RECORD_FILE" > dist/_redirects
  echo "_redirects: $(wc -l < dist/_redirects) entries"
fi

# ---------------------------------------------------------------------------
# 6. Build index.html pages for all subdirectories
# ---------------------------------------------------------------------------
echo "Building index pages ..."
python3 build_indexes.py \
  "dist" \
  "-" \
  "index_template.html" \
  "README.md" \
  --all-dirs

echo "Build complete: $(find dist -type f | wc -l) files in dist/"

