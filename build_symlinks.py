#!/usr/bin/env python3
"""Build symlinks.json mapping every symlink in the tlnet staging tree
to its link target (filename only, not full path).

Usage:
    build_symlinks.py <staging_dir> <to_upload_file>

Walks the entire staging tree, finds all symlinks, and records:
    { "relative/path/to/link": "target-filename" }

e.g. "archive/hyphen-base.tar.xz": "hyphen-base.r78076.tar.xz"

The JSON is written to <staging_dir>/symlinks.json and its path is
appended to to_upload_file so rclone picks it up.
"""

import json
import os
import sys
from pathlib import Path

def main():
    staging_dir = Path(sys.argv[1])
    upload_file = sys.argv[2]

    mapping = {}
    for dirpath, dirnames, filenames in os.walk(staging_dir):
        # Also check symlinked dirs and files via lstat
        dp = Path(dirpath)
        for name in filenames + dirnames:
            full = dp / name
            if full.is_symlink():
                target = os.readlink(full)
                # Store only the filename of the target, not any path component
                rel = str(full.relative_to(staging_dir))
                mapping[rel] = Path(target).name

    out = staging_dir / 'symlinks.json'
    out.write_text(json.dumps(mapping, sort_keys=True, indent=2), encoding='utf-8')
    print(f"Built symlinks.json with {len(mapping)} entries.")

    with open(upload_file, 'a') as f:
        f.write('symlinks.json\n')

if __name__ == '__main__':
    main()
