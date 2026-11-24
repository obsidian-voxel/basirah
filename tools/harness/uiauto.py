#!/usr/bin/env python3
"""Reads a `uiautomator dump` XML and answers questions about it.

The Phase 1 harness drives Chrome's first-run flow, its prompts and the address
bar by node identity rather than hardcoded tap coordinates, because both change
with screen size and Chrome version. Kept dependency-free so it runs with
whatever Python the machine already has.

Usage:
  uiauto.py labels <ui.xml>                  one "text<TAB>bounds" line per labelled node
  uiauto.py center <ui.xml> <regex>           "x y" centre of the first node whose
                                              text or content-desc matches
  uiauto.py center-id <ui.xml> <regex>        same, but matched against resource-id
  uiauto.py has <ui.xml> <regex>              exit 0 when a label matches

Exit status is 1 when nothing matches, 2 on a usage error.
"""

import re
import sys

NODE = re.compile(r"<node\b[^>]*>")
TEXT = re.compile(r'text="([^"]*)"')
DESC = re.compile(r'content-desc="([^"]*)"')
BOUNDS = re.compile(r'bounds="([^"]*)"')
RES_ID = re.compile(r'resource-id="([^"]*)"')


def nodes(path):
    """Yields (label, bounds, resource_id) for every node in the dump."""
    with open(path, encoding="utf-8", errors="replace") as handle:
        raw = handle.read()
    for tag in NODE.findall(raw):
        text = TEXT.search(tag)
        desc = DESC.search(tag)
        bounds = BOUNDS.search(tag)
        resource = RES_ID.search(tag)
        label = (text.group(1).strip() if text else "") or (
            desc.group(1).strip() if desc else ""
        )
        yield (
            label,
            bounds.group(1) if bounds else "",
            resource.group(1) if resource else "",
        )


def bounds_center(bounds):
    match = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", bounds or "")
    if not match:
        return None
    x1, y1, x2, y2 = (int(value) for value in match.groups())
    return ((x1 + x2) // 2, (y1 + y2) // 2)


def main(argv):
    if len(argv) < 3:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    command, path = argv[1], argv[2]
    pattern = re.compile(argv[3], re.IGNORECASE) if len(argv) > 3 else None

    if command == "labels":
        for label, bounds, _ in nodes(path):
            if label:
                print(f"{label}\t{bounds}")
        return 0

    if command not in ("center", "center-id", "has"):
        print(f"unknown command: {command}", file=sys.stderr)
        return 2
    if pattern is None:
        print("a search pattern is required", file=sys.stderr)
        return 2

    for label, bounds, resource in nodes(path):
        subject = resource if command == "center-id" else label
        if not subject or not pattern.search(subject):
            continue
        if command == "has":
            return 0
        centre = bounds_center(bounds)
        if centre:
            print(f"{centre[0]} {centre[1]}")
            return 0
        break
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
