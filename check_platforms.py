#!/usr/bin/env python3
"""Check that all platform binaries in tlnet/archive belong to supported platforms.

Usage:
    check_platforms.py <staging_dir>

Exits with code 1 if any unexpected platform is found.
"""

import os
import re
import sys
from pathlib import Path

SUPPORTED = {
    'x86_64-linux',
    'aarch64-linux',
    'universal-darwin',
    'windows',
    'x86_64-linuxmusl',
}

# Matches filenames like:
#   foo.x86_64-linux.tar.xz
#   foo.x86_64-linux.r12345.tar.xz
# Does NOT match plain runtime tarballs like:
#   foo.tar.xz  or  foo.r12345.tar.xz
PATTERN = re.compile(r'^[^.]+\.(?!r\d+\.tar\.xz)((?:[a-z0-9_]+-[a-z0-9]+[a-z0-9_-]*)|windows)\.(?:r\d+\.)?tar\.xz$')

def main():
    staging_dir = Path(sys.argv[1])
    archive = staging_dir / 'archive'

    found = set()
    for f in archive.iterdir():
        m = PATTERN.match(f.name)
        if m:
            found.add(m.group(1))

    unexpected = found - SUPPORTED
    if unexpected:
        print(f"ERROR: unexpected platforms found: {', '.join(sorted(unexpected))}")
        sys.exit(1)
    else:
        print(f"OK: platforms found: {', '.join(sorted(found))}")

if __name__ == '__main__':
    main()
