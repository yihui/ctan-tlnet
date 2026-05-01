#!/usr/bin/env bash
# create_release.sh - Upload large files and the tlnet archive to GitHub Releases.
#
# Two permanent releases (v1 and v2) are maintained. When a file's content
# changes, it is uploaded to the *other* release so the previous version
# stays accessible for any in-progress downloads. The same alternating logic
# applies to the main tlnet archive (tlnet.tar.zst).
#
# A JSON record file (release-record.json) is committed to the repository
# root after each run. The Cloudflare Pages build (deploy.sh) reads this
# record to generate _redirects and to know which release holds the current
# tlnet.tar.zst.
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

upload_with_retry() {
  local tag="$1" file="$2" name="$3"
  local attempt
  for attempt in $(seq 1 5); do
    if gh release upload "$tag" "$file" \
         --name "$name" \
         --repo "$REPO" \
         --clobber; then
      return 0
    fi
    if [ "$attempt" -lt 5 ]; then
      echo "Upload attempt $attempt failed, retrying in 30 s ..."
      sleep 30
    fi
  done
  echo "ERROR: failed to upload $name after 5 attempts" >&2
  return 1
}

file_sha256() { sha256sum "$1" | awk '{print $1}'; }

# ---------------------------------------------------------------------------
# 1. Load existing record (or start fresh)
# ---------------------------------------------------------------------------
if [ -f "$RECORD_FILE" ]; then
  record=$(cat "$RECORD_FILE")
else
  record='{"files":{},"archive":{}}'
fi

# v1 always exists; v2 is created on demand.
ensure_release "$V1_TAG"

changed=false
new_record="$record"

# ---------------------------------------------------------------------------
# 2. Process large files (> 24 MiB)
# ---------------------------------------------------------------------------
echo "==> Scanning for files larger than 24 MiB in $STAGING_DIR ..."

while IFS= read -r filepath; do
  relpath="${filepath#${STAGING_DIR}/}"
  assetname="${relpath//\//=}"
  checksum=$(file_sha256 "$filepath")

  existing_checksum=$(echo "$new_record" | jq -r --arg k "$relpath" '.files[$k].checksum // ""')
  existing_release=$(echo "$new_record"  | jq -r --arg k "$relpath" '.files[$k].release  // ""')

  if [ -z "$existing_release" ]; then
    # New file — upload to v1.
    target="$V1_TAG"
    echo "NEW: $relpath -> $target"
  elif [ "$checksum" = "$existing_checksum" ]; then
    echo "UNCHANGED: $relpath"
    continue
  else
    # Content changed — upload to the other release.
    target=$(other_release "$existing_release")
    ensure_release "$target"
    echo "CHANGED: $relpath (was $existing_release) -> $target"
  fi

  upload_with_retry "$target" "$filepath" "$assetname"
  changed=true

  new_record=$(echo "$new_record" | jq \
    --arg k     "$relpath"   \
    --arg cs    "$checksum"  \
    --arg rel   "$target"    \
    --arg asset "$assetname" \
    '.files[$k] = {checksum: $cs, release: $rel, asset: $asset}')

done < <(find "$STAGING_DIR" -type f -size +24M | sort)

# ---------------------------------------------------------------------------
# 3. Compress the remaining files (excluding large files) into tlnet.tar.zst
# ---------------------------------------------------------------------------
echo "==> Compressing remaining files into tlnet.tar.zst ..."
command -v zstd &>/dev/null || sudo apt-get install -y zstd -qq

# Build tar --exclude arguments for every large file recorded so far
# (covers previously recorded files and those just uploaded above).
mapfile -t exclude_args < <(
  echo "$new_record" | jq -r '.files | keys[] | "--exclude=./\(.)"'
)

tar_file="/tmp/tlnet.tar.zst"
  # ${exclude_args[@]+"${exclude_args[@]}"}: safe expansion that avoids
  # "unbound variable" errors under set -u when the array is empty.
tar -C "$STAGING_DIR" \
    ${exclude_args[@]+"${exclude_args[@]}"} \
    --zstd -cf "$tar_file" .
du -sh "$tar_file"

# ---------------------------------------------------------------------------
# 4. Upload tlnet.tar.zst (only if its checksum changed)
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
  upload_with_retry "$archive_target" "$tar_file" "tlnet.tar.zst"
  changed=true
  new_record=$(echo "$new_record" | jq \
    --arg cs  "$archive_checksum" \
    --arg rel "$archive_target"   \
    '.archive = {checksum: $cs, release: $rel}')
fi

rm -f "$tar_file"

# ---------------------------------------------------------------------------
# 5. Commit the updated record to the repository
# ---------------------------------------------------------------------------
if [ "$changed" = "true" ]; then
  echo "$new_record" | jq '.' > "$RECORD_FILE"
  git config user.email "github-actions[bot]@users.noreply.github.com"
  git config user.name  "github-actions[bot]"
  git add "$RECORD_FILE"
  if git diff --staged --quiet; then
    echo "Record file unchanged on disk — nothing to commit."
  else
    git commit -m "Update release-record.json [skip ci]"
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

