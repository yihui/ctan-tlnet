#!/bin/bash
# Verify MD5 and SHA256 checksums for all files in a staging directory.
# Usage: verify_checksums.sh <staging-dir>
# Exits with a non-zero status if any checksum does not match.

set -euo pipefail

STAGING_DIR="${1:?Usage: $0 <staging-dir>}"
failed=0

verify_checksums() {
  local ext="$1"   # e.g. "md5" or "sha256"
  local cmd="$2"   # e.g. "md5sum" or "sha256sum"
  while IFS= read -r sumfile; do
    basefile="${sumfile%.$ext}"
    if [ ! -f "$basefile" ]; then
      echo "WARNING: $basefile not found, skipping ${ext^^} check"
      continue
    fi
    expected=$(awk '{print $1}' "$sumfile")
    actual=$("$cmd" "$basefile" | awk '{print $1}')
    if [ "$expected" != "$actual" ]; then
      echo "ERROR: ${ext^^} mismatch for $basefile"
      echo "  Expected: $expected"
      echo "  Actual:   $actual"
      failed=$((failed + 1))
    fi
  done < <(find "$STAGING_DIR" -name "*.$ext" -type f)
}

verify_checksums md5    md5sum
verify_checksums sha256 sha256sum

if [ "$failed" -gt 0 ]; then
  echo "FATAL: $failed checksum verification(s) failed. Aborting upload."
  exit 1
fi
echo "All checksum verifications passed."
