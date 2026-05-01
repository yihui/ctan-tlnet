#!/usr/bin/env bash
# create_release.sh - Upload large files and the tlnet archive to GitHub Releases.
#
# Architecture:
#   - Two permanent releases (v1 and v2). Files alternate between them when updated.
#   - release-record.json tracks checksums, release assignments, and pending deletions.
#   - index.html pages (_all_ subdirs) and _redirects are built here (GHA) and
#     bundled inside tlnet.tar.zst so Cloudflare just downloads and extracts.
#   - Deleted large files are kept accessible for one full day (grace period):
#     they are added to pending_delete and removed on the *next* daily run.
#
# Usage: bash create_release.sh <staging_dir>
#
# Required environment variables (set automatically in GitHub Actions):
#   GITHUB_REPOSITORY   owner/repo
#   GH_TOKEN or GITHUB_TOKEN

set -euo pipefail

STAGING_DIR="${1:?Usage: $0 <staging_dir>}"
RECORD_FILE="release-record.json"
V1_TAG="v1"
V2_TAG="v2"
REPO="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY must be set}"

# Directory containing this script (repo root); used to locate helper scripts.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

other_release() { [ "$1" = "$V1_TAG" ] && echo "$V2_TAG" || echo "$V1_TAG"; }

ensure_release() {
  local tag="$1"
  if ! gh release view "$tag" --repo "$REPO" &>/dev/null; then
    echo "Creating release $tag ..."
    gh release create "$tag" \
      --repo "$REPO" \
      --title "CTAN tlnet assets ($tag)" \
      --notes "Permanent release holding large files and archives for the CTAN tlnet mirror. Do not delete manually." \
      --prerelease
  fi
}

# gh release upload uses the basename of the file as the asset name.
# Callers must mv/cp the source to /tmp/<desired-asset-name> before calling.
upload_with_retry() {
  local tag="$1" file="$2"
  local attempt
  for attempt in $(seq 1 5); do
    if gh release upload "$tag" "$file" \
         --repo "$REPO" \
         --clobber; then
      return 0
    fi
    if [ "$attempt" -lt 5 ]; then
      echo "Upload attempt $attempt failed, retrying in 30 s ..."
      sleep 30
    fi
  done
  echo "ERROR: failed to upload $(basename "$file") after 5 attempts" >&2
  return 1
}

file_sha256() { sha256sum "$1" | awk '{print $1}'; }

# ---------------------------------------------------------------------------
# 1. Load existing record (or start fresh)
# ---------------------------------------------------------------------------
if [ -f "$RECORD_FILE" ]; then
  record=$(cat "$RECORD_FILE")
else
  record='{"files":{},"archive":{},"pending_delete":[]}'
fi

# v1 always exists; v2 is created on demand.
ensure_release "$V1_TAG"

changed=false
new_record="$record"

# ---------------------------------------------------------------------------
# 2. Delete assets that were marked for deletion in the previous run
#    (one-day grace period: assets are removed the day after they disappear)
# ---------------------------------------------------------------------------
echo "==> Processing pending deletions from previous run ..."
while IFS= read -r entry; do
  [ -z "$entry" ] && continue
  pd_release=$(echo "$entry" | jq -r '.release')
  pd_asset=$(echo "$entry"   | jq -r '.asset')
  echo "Deleting stale asset: $pd_asset from release $pd_release ..."
  gh release delete-asset "$pd_release" "$pd_asset" \
    --repo "$REPO" --yes 2>/dev/null || true
done < <(echo "$new_record" | jq -c '.pending_delete // [] | .[]')

new_record=$(echo "$new_record" | jq '.pending_delete = []')

# ---------------------------------------------------------------------------
# 3. Capture the current set of large files BEFORE moving any of them out
# ---------------------------------------------------------------------------
echo "==> Scanning for files larger than 24 MiB in $STAGING_DIR ..."
mapfile -t current_large_files < <(find "$STAGING_DIR" -type f -size +24M | sort)

# Build an associative set of relative paths for O(1) membership tests.
declare -A current_large_set
for _large_file in "${current_large_files[@]}"; do
  current_large_set["${_large_file#${STAGING_DIR}/}"]=1
done

# ---------------------------------------------------------------------------
# 4. Build index.html for every subdirectory (files are still in STAGING_DIR)
# ---------------------------------------------------------------------------
echo "==> Building index pages ..."
python3 "$SCRIPT_DIR/build_indexes.py" \
  "$STAGING_DIR" \
  "-" \
  "$SCRIPT_DIR/index_template.html" \
  "$SCRIPT_DIR/README.md" \
  --all-dirs

# ---------------------------------------------------------------------------
# 5. Process each large file:
#    - mv out of STAGING_DIR (excluded from the archive automatically)
#    - upload to the appropriate release if checksum changed
# ---------------------------------------------------------------------------
for filepath in "${current_large_files[@]}"; do
  relpath="${filepath#${STAGING_DIR}/}"
  assetname="${relpath//\//@}"

  existing_checksum=$(echo "$new_record" | jq -r --arg k "$relpath" '.files[$k].checksum // ""')
  existing_release=$(echo "$new_record"  | jq -r --arg k "$relpath" '.files[$k].release  // ""')

  # Always move the large file out so it is not included in the archive.
  # Asset names use '@' instead of '/' (unique within /tmp since rel paths are unique).
  tmpfile="/tmp/$assetname"
  mv "$filepath" "$tmpfile"

  checksum=$(file_sha256 "$tmpfile")

  if [ -z "$existing_release" ]; then
    # New file — upload to v1.
    target="$V1_TAG"
    echo "NEW: $relpath -> $target"
  elif [ "$checksum" = "$existing_checksum" ]; then
    echo "UNCHANGED: $relpath (in $existing_release)"
    continue
  else
    # Content changed — upload to the other release.
    target=$(other_release "$existing_release")
    ensure_release "$target"
    echo "CHANGED: $relpath (was $existing_release) -> $target"
  fi

  upload_with_retry "$target" "$tmpfile"
  changed=true

  new_record=$(echo "$new_record" | jq \
    --arg k     "$relpath"   \
    --arg cs    "$checksum"  \
    --arg rel   "$target"    \
    --arg asset "$assetname" \
    '.files[$k] = {checksum: $cs, release: $rel, asset: $asset}')
done

# ---------------------------------------------------------------------------
# 6. Mark large files removed from CTAN for deletion next run
#    (compare the original record against the current large-file set)
# ---------------------------------------------------------------------------
echo "==> Checking for removed large files ..."
while IFS= read -r relpath; do
  [ -z "$relpath" ] && continue
  if [ -z "${current_large_set[$relpath]+x}" ]; then
    pd_release=$(echo "$new_record" | jq -r --arg k "$relpath" '.files[$k].release')
    pd_asset=$(echo "$new_record"   | jq -r --arg k "$relpath" '.files[$k].asset')
    echo "REMOVED: $relpath (asset $pd_asset will be deleted from $pd_release next run)"
    new_record=$(echo "$new_record" | jq \
      --arg rel   "$pd_release" \
      --arg asset "$pd_asset"   \
      '.pending_delete += [{release: $rel, asset: $asset}]')
    new_record=$(echo "$new_record" | jq --arg k "$relpath" 'del(.files[$k])')
    changed=true
  fi
done < <(echo "$record" | jq -r '.files | keys[]')

# ---------------------------------------------------------------------------
# 7. Generate _redirects (written into STAGING_DIR → bundled in the archive)
# ---------------------------------------------------------------------------
echo "==> Generating _redirects ..."
echo "$new_record" | jq -r --arg repo "$REPO" '
  .files | to_entries[] |
  "/\(.key)  https://github.com/\($repo)/releases/download/\(.value.release)/\(.value.asset)  302"
' > "$STAGING_DIR/_redirects"
echo "_redirects: $(wc -l < "$STAGING_DIR/_redirects") entries"

# ---------------------------------------------------------------------------
# 8. Compress STAGING_DIR into tlnet.tar.zst
#    Large files were already mv'd out; index.html and _redirects are now inside.
# ---------------------------------------------------------------------------
echo "==> Compressing $STAGING_DIR into tlnet.tar.zst ..."
# All large files were mv'd out in the loop above; index.html and _redirects
# are now present in STAGING_DIR, so they are included automatically.
command -v zstd &>/dev/null || sudo apt-get install -y zstd -qq

tar_file="/tmp/tlnet.tar.zst"
tar -C "$STAGING_DIR" --zstd -cf "$tar_file" .
du -sh "$tar_file"

# ---------------------------------------------------------------------------
# 9. Upload tlnet.tar.zst (only when its checksum changed)
# ---------------------------------------------------------------------------
archive_checksum=$(file_sha256 "$tar_file")
existing_archive_cs=$(echo "$new_record"  | jq -r '.archive.checksum // ""')
existing_archive_rel=$(echo "$new_record" | jq -r '.archive.release  // ""')

if [ "$archive_checksum" = "$existing_archive_cs" ]; then
  echo "ARCHIVE UNCHANGED: skipping upload."
else
  if [ -z "$existing_archive_rel" ]; then
    archive_target="$V1_TAG"
  else
    archive_target=$(other_release "$existing_archive_rel")
    ensure_release "$archive_target"
  fi
  echo "Uploading tlnet.tar.zst to $archive_target ..."
  upload_with_retry "$archive_target" "$tar_file"
  changed=true
  new_record=$(echo "$new_record" | jq \
    --arg cs  "$archive_checksum" \
    --arg rel "$archive_target"   \
    '.archive = {checksum: $cs, release: $rel}')
fi

rm -f "$tar_file"

# ---------------------------------------------------------------------------
# 10. Commit the updated record to the repository
# ---------------------------------------------------------------------------
if [ "$changed" = "true" ]; then
  echo "$new_record" | jq '.' > "$RECORD_FILE"
  git config user.email "github-actions[bot]@users.noreply.github.com"
  git config user.name  "github-actions[bot]"
  git add "$RECORD_FILE"
  if git diff --staged --quiet; then
    echo "Record file unchanged on disk — nothing to commit."
  else
    git commit -m "Update release-record.json"
    for attempt in $(seq 1 3); do
      if git pull --rebase && git push; then
        break
      fi
      [ "$attempt" -lt 3 ] && sleep 10
    done
  fi
else
  echo "Nothing changed — skipping record update."
fi

echo "==> create_release.sh completed."
