#!/usr/bin/env python3
"""Build index.html for every directory in the tlnet staging tree.

Usage:
    build_indexes.py <staging_dir> <to_upload_file> <to_delete_file> <template> [force]

Exits early (no-op) if both to_upload_file and to_delete_file are empty,
i.e. rsync found no changes since the last sync, unless force=true.
"""

import os
import sys
import subprocess
from pathlib import Path
from datetime import datetime, timezone
from string import Template

SKIP_DIRS = {'.git'}

def human_size(size: int) -> str:
    for unit in ('B', 'K', 'M', 'G'):
        if size < 1024:
            return f"{size} {unit}" if unit == 'B' else f"{size:.1f} {unit}"
        size /= 1024
    return f"{size:.1f} T"

def md_to_html(md_path: Path) -> str:
    """Convert a Markdown file to an HTML fragment using cmark."""
    try:
        result = subprocess.run(
            ['cmark', '--unsafe', str(md_path)],
            capture_output=True, text=True, check=True
        )
        return result.stdout
    except Exception as e:
        print(f"Warning: cmark failed for {md_path}: {e}", file=sys.stderr)
        return ''

def build_index(dirpath: Path, staging_dir: Path, template: Template) -> str:
    rel = dirpath.relative_to(staging_dir)

    # Breadcrumb
    parts = list(rel.parts)
    crumbs = ['<a href="/">tlnet</a>']
    for i, part in enumerate(parts):
        href = '/' + '/'.join(parts[:i+1]) + '/'
        if i < len(parts) - 1:
            crumbs.append(f'<a href="{href}">{part}</a>')
        else:
            crumbs.append(f'<span>{part}</span>')
    breadcrumb = ' / '.join(crumbs) if parts else '<span>tlnet</span>'

    # Directory entries
    try:
        entries = sorted(dirpath.iterdir(), key=lambda p: (p.is_file(), p.name.lower()))
    except PermissionError:
        entries = []
    subdirs = [e for e in entries if e.is_dir()  and e.name not in SKIP_DIRS]
    files   = [e for e in entries if e.is_file() and e.name != 'index.html']

    # README
    readme_html = ''
    readme_path = dirpath / 'README.md'
    if readme_path.exists():
        readme_html = md_to_html(readme_path)

    # File listing rows
    rows = []
    if dirpath != staging_dir:
        rows.append('<li class="entry dir"><a href="../">../</a><span></span></li>')
    for d in subdirs:
        rows.append(
            f'<li class="entry dir">'
            f'<a href="{d.name}/">{d.name}/</a><span></span></li>'
        )
    for f in files:
        try:
            sz = human_size(f.stat().st_size)
        except OSError:
            sz = '?'
        rows.append(
            f'<li class="entry file">'
            f'<a href="{f.name}">{f.name}</a><span>{sz}</span></li>'
        )

    title  = f'tlnet/{rel}' if str(rel) != '.' else 'tlnet'
    now    = datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M UTC')
    readme_section = f'<div class="readme">{readme_html}</div>' if readme_html else ''

    return template.substitute(
        title=title,
        breadcrumb=breadcrumb,
        meta=now,
        readme_section=readme_section,
        listing='\n    '.join(rows),
    )

def main():
    staging_dir   = Path(sys.argv[1])
    upload_file   = sys.argv[2]
    delete_file   = sys.argv[3]
    template_file = Path(sys.argv[4]) if len(sys.argv) > 4 \
                    else Path(__file__).with_name('index_template.html')
    force         = len(sys.argv) > 5 and sys.argv[5].lower() == 'true'

    # No-op if nothing changed and force flag is not set
    upload_empty = not Path(upload_file).exists() or Path(upload_file).stat().st_size == 0
    delete_empty = not Path(delete_file).exists() or Path(delete_file).stat().st_size == 0
    if upload_empty and delete_empty and not force:
        print("No changes detected — skipping index rebuild.")
        return

    template = Template(template_file.read_text(encoding='utf-8'))
    new_indexes = []

    for dirpath, dirnames, _ in os.walk(staging_dir):
        dirnames[:] = sorted(d for d in dirnames if d not in SKIP_DIRS)
        dp = Path(dirpath)
        html = build_index(dp, staging_dir, template)
        index_path = dp / 'index.html'
        index_path.write_text(html, encoding='utf-8')
        rel = index_path.relative_to(staging_dir)
        new_indexes.append(str(rel))

    with open(upload_file, 'a') as f:
        for p in new_indexes:
            f.write(p + '\n')

    print(f"Built {len(new_indexes)} index pages.")

if __name__ == '__main__':
    main()
