#!/usr/bin/env python3
"""Resolve all symlinks in the tlnet staging tree in-place.

For each symlink foo.tar.xz -> foo.r12345.tar.xz:
  1. Copy the target file content to the symlink path (making it a real file)
  2. Delete the versioned target file

After this, staging contains only unversioned filenames as real files.
Versioned files and all symlinks are gone.

Usage:
    resolve_symlinks.py <staging_dir>
"""

import os
import shutil
import sys
from pathlib import Path

def main():
    staging_dir = Path(sys.argv[1])
    resolved = 0
    errors = 0

    for dirpath, dirnames, filenames in os.walk(staging_dir):
        dp = Path(dirpath)
        for name in filenames:
            full = dp / name
            if not full.is_symlink():
                continue
            target_name = os.readlink(full)
            target = dp / target_name
            if not target.exists():
                print(f"Warning: target not found: {target}", file=sys.stderr)
                errors += 1
                continue
            # Replace symlink with a real copy of the target
            full.unlink()
            shutil.copy2(target, full)
            # Delete the versioned file
            target.unlink()
            resolved += 1

    print(f"Resolved {resolved} symlinks, {errors} errors.")

if __name__ == '__main__':
    main()