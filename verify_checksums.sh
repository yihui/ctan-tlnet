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

# Verify SHA-512 checksums recorded in texlive.tlpdb against the actual
# archive .tar.xz files.  The database maps each package name to one or more
# container checksums:
#   containerchecksum      -> <name>.tar.xz
#   doccontainerchecksum   -> <name>.doc.tar.xz
#   srccontainerchecksum   -> <name>.source.tar.xz
verify_tlpdb_checksums() {
  local tlpdb="$STAGING_DIR/tlpkg/texlive.tlpdb"
  if [ ! -f "$tlpdb" ]; then
    echo "WARNING: $tlpdb not found, skipping tlpdb checksum verification"
    return
  fi

  local archive_dir="$STAGING_DIR/archive"
  if [ ! -d "$archive_dir" ]; then
    echo "WARNING: $archive_dir not found, skipping tlpdb checksum verification"
    return
  fi

  # Parse the tlpdb with awk and emit "expected_hash filename" lines, then
  # verify each archive file that is present in the staging directory.
  while IFS=' ' read -r expected filename; do
    local tarfile="$archive_dir/$filename"
    if [ ! -f "$tarfile" ]; then
      continue
    fi
    local actual
    actual=$(sha512sum "$tarfile" | awk '{print $1}')
    if [ "$expected" != "$actual" ]; then
      echo "ERROR: SHA-512 mismatch (tlpdb) for $filename"
      echo "  Expected: $expected"
      echo "  Actual:   $actual"
      failed=$((failed + 1))
    fi
  done < <(awk '
    /^name /              { pkgname = $2 }
    /^containerchecksum / { print $2, pkgname ".tar.xz" }
    /^doccontainerchecksum / { print $2, pkgname ".doc.tar.xz" }
    /^srccontainerchecksum / { print $2, pkgname ".source.tar.xz" }
  ' "$tlpdb")
}

verify_tlpdb_checksums

if [ "$failed" -gt 0 ]; then
  echo "FATAL: $failed checksum verification(s) failed. Aborting upload."
  exit 1
fi
echo "All checksum verifications passed."
