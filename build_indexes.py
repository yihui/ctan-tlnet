#!/usr/bin/env python3
"""Build index.html for the tlnet staging tree.

Usage (GitHub Actions — root + one level only):
    build_indexes.py <staging_dir> <to_upload_file> [<template>] [<readme>]

Usage (Cloudflare Pages — all subdirectories):
    build_indexes.py <staging_dir> - [<template>] [<readme>] --all-dirs

When <to_upload_file> is omitted or ``-``, new index paths are not written
to any file (useful when running outside the rsync workflow).
"""

import argparse
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from string import Template

SKIP_DIRS = {".git"}


def human_size(size: int) -> str:
    for unit in ("B", "K", "M", "G"):
        if size < 1024:
            return f"{size} {unit}" if unit == "B" else f"{size:.1f} {unit}"
        size /= 1024
    return f"{size:.1f} T"


def md_to_html(md_path: Path) -> str:
    """Convert a Markdown file to an HTML fragment using cmark."""
    try:
        result = subprocess.run(
            ["cmark", "--unsafe", str(md_path)],
            capture_output=True,
            text=True,
            check=True,
        )
        return result.stdout
    except Exception as e:
        print(f"Warning: cmark failed for {md_path}: {e}", file=sys.stderr)
        return ""


def build_index(
    dirpath: Path,
    staging_dir: Path,
    template: Template,
    footer_html: str,
    all_dirs: bool = False,
) -> str:
    rel = dirpath.relative_to(staging_dir)

    # Breadcrumb
    parts = list(rel.parts)
    crumbs = ['<a href="/index.html">tlnet</a>']
    for i, part in enumerate(parts):
        href = "/" + "/".join(parts[: i + 1]) + "/index.html"
        if i < len(parts) - 1:
            crumbs.append(f'<a href="{href}">{part}</a>')
        else:
            crumbs.append(f"<span>{part}</span>")
    breadcrumb = " / ".join(crumbs) if parts else "<span>tlnet</span>"

    # Directory entries
    try:
        entries = sorted(dirpath.iterdir(), key=lambda p: (p.is_file(), p.name.lower()))
    except PermissionError:
        entries = []
    subdirs = [e for e in entries if e.is_dir() and e.name not in SKIP_DIRS]
    files = [e for e in entries if e.is_file() and e.name != "index.html"]

    # README above listing
    readme_html = ""
    readme_path = dirpath / "README.md"
    if readme_path.exists():
        readme_html = md_to_html(readme_path)
    readme_section = f'<div class="readme">{readme_html}</div>' if readme_html else ""

    # File listing rows
    rows = []
    if dirpath != staging_dir:
        rows.append(
            '<li class="entry dir"><a href="../index.html">../</a><span></span></li>'
        )
    depth = len(rel.parts)
    for d in subdirs:
        # In all_dirs mode every subdir gets an index.html, so always link.
        # In normal mode only root-level subdirs (depth 0) get index.html.
        if all_dirs or depth == 0:
            rows.append(
                f'<li class="entry dir">'
                f'<a href="{d.name}/index.html">{d.name}/</a><span></span></li>'
            )
        else:
            rows.append(
                f'<li class="entry dir">'
                f'<span class="dirname">{d.name}/</span><span></span></li>'
            )
    for f in files:
        try:
            sz = human_size(f.stat().st_size)
        except OSError:
            sz = "?"
        rows.append(
            f'<li class="entry file">'
            f'<a href="{f.name}">{f.name}</a><span>{sz}</span></li>'
        )

    title = f"tlnet/{rel}" if str(rel) != "." else "tlnet"
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")

    return template.substitute(
        title=title,
        breadcrumb=breadcrumb,
        meta=now,
        readme_section=readme_section,
        footer_content=footer_html,
        listing="\n    ".join(rows),
    )


def collect_all_dirs(root: Path) -> list[Path]:
    """Return all directories under *root* in top-down order."""
    result: list[Path] = []
    for dirpath_str, dirnames, _ in os.walk(str(root)):
        dirpath = Path(dirpath_str)
        dirnames[:] = sorted(d for d in dirnames if d not in SKIP_DIRS)
        result.append(dirpath)
    return result


def main():
    parser = argparse.ArgumentParser(
        description="Build index.html pages for the tlnet staging tree."
    )
    parser.add_argument("staging_dir", help="Root of the staging/output directory")
    parser.add_argument(
        "upload_file",
        nargs="?",
        default="-",
        help="File to append new index paths to; use '-' to skip (default: -)",
    )
    parser.add_argument(
        "template_file",
        nargs="?",
        default=None,
        help="HTML template path (default: index_template.html next to this script)",
    )
    parser.add_argument(
        "readme_file",
        nargs="?",
        default=None,
        help="README.md path for the footer (default: README.md next to this script)",
    )
    parser.add_argument(
        "--all-dirs",
        action="store_true",
        help="Build index.html for every subdirectory (not just one level deep)",
    )
    args = parser.parse_args()

    staging_dir = Path(args.staging_dir)
    template_file = (
        Path(args.template_file)
        if args.template_file
        else Path(__file__).with_name("index_template.html")
    )
    readme_file = (
        Path(args.readme_file)
        if args.readme_file
        else Path(__file__).with_name("README.md")
    )

    template = Template(template_file.read_text(encoding="utf-8"))
    footer_html = md_to_html(readme_file) if readme_file.exists() else ""
    new_indexes = []

    if args.all_dirs:
        dirs_to_index = collect_all_dirs(staging_dir)
    else:
        # Default: root + one level down (original behaviour)
        dirs_to_index = [staging_dir] + [
            d
            for d in sorted(staging_dir.iterdir())
            if d.is_dir() and d.name not in SKIP_DIRS
        ]

    for dp in dirs_to_index:
        html = build_index(dp, staging_dir, template, footer_html, all_dirs=args.all_dirs)
        index_path = dp / "index.html"
        index_path.write_text(html, encoding="utf-8")
        rel = index_path.relative_to(staging_dir)
        new_indexes.append(str(rel))

    # Write new index paths to the upload-tracking file (skipped when "-")
    upload_file = args.upload_file
    if upload_file and upload_file != "-":
        with open(upload_file, "a") as f:
            for p in new_indexes:
                f.write(p + "\n")

    print(f"Built {len(new_indexes)} index pages.")


if __name__ == "__main__":
    main()

