#!/bin/bash
# Rsync CTAN tlnet to a local staging directory.
# Usage: rsync_ctan.sh <staging-dir>
# Itemized changes are written to /tmp/rsync-changes.txt.

set -euo pipefail

STAGING_DIR="${1:?Usage: $0 <staging-dir>}"

# --itemize-changes prints one line per changed file:
#   >f+++++++++ path/to/new-or-changed-file
#   >L+++++++++ path/to/new-or-changed-symlink
#   *deleting   path/to/removed-file-or-symlink
# Redirect all output to the changes file; no progress or stats.
rsync \
  --archive \
  --delete \
  --delete-excluded \
  --hard-links \
  --partial \
  --itemize-changes \
  --exclude='/archive/*.doc.tar.xz' \
  --exclude='/archive/*.doc.*.tar.xz' \
  --exclude='/archive/*.source.tar.xz' \
  --exclude='/archive/*.source.*.tar.xz' \
  --exclude='/update-tlmgr-*' \
  --exclude='/archive/*.amd64-freebsd.tar.xz' \
  --exclude='/archive/*.amd64-freebsd.*.tar.xz' \
  --exclude='/archive/*.amd64-netbsd.tar.xz' \
  --exclude='/archive/*.amd64-netbsd.*.tar.xz' \
  --exclude='/archive/*.armhf-linux.tar.xz' \
  --exclude='/archive/*.armhf-linux.*.tar.xz' \
  --exclude='/archive/*.i386-freebsd.tar.xz' \
  --exclude='/archive/*.i386-freebsd.*.tar.xz' \
  --exclude='/archive/*.i386-linux.tar.xz' \
  --exclude='/archive/*.i386-linux.*.tar.xz' \
  --exclude='/archive/*.i386-netbsd.tar.xz' \
  --exclude='/archive/*.i386-netbsd.*.tar.xz' \
  --exclude='/archive/*.i386-solaris.tar.xz' \
  --exclude='/archive/*.i386-solaris.*.tar.xz' \
  --exclude='/archive/*.x86_64-cygwin.tar.xz' \
  --exclude='/archive/*.x86_64-cygwin.*.tar.xz' \
  --exclude='/archive/*.x86_64-darwinlegacy.tar.xz' \
  --exclude='/archive/*.x86_64-darwinlegacy.*.tar.xz' \
  --exclude='/archive/*.x86_64-solaris.tar.xz' \
  --exclude='/archive/*.x86_64-solaris.*.tar.xz' \
  rsync://rsync.dante.ctan.org/CTAN/systems/texlive/tlnet/ \
  "$STAGING_DIR/" \
  >> /tmp/rsync-changes.txt
