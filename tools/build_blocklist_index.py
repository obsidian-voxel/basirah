#!/usr/bin/env python3
"""Build the bundled adult-domain index.

The app matches page hosts against about 953k adult domains. Shipping the
text list would cost 25 MB on disk and roughly 85 MB of heap once parsed into
strings, so the lookup table is a sorted array of 64-bit FNV-1a hashes of the
domains: 7.6 MB in the APK, a 7.6 MB LongArray at runtime, and a binary search
per host label. `AdultDomainIndex.kt` uses the same hash and the same signed
ordering, so the two must stay in step.

Sources, in order:
  * tools/blocklists/porn.txt          (blocklistproject/Lists, Unlicense)
  * tools/blocklists/extra_domains.txt (the list the app shipped before this)
  * any --source files passed on the command line

Run from the repository root:

    python tools/build_blocklist_index.py

Writes assets/blocklists/adult_domains.idx and prints the entry count.
"""

from __future__ import annotations

import argparse
import struct
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_SOURCES = [
    ROOT / "tools" / "blocklists" / "porn.txt",
    ROOT / "tools" / "blocklists" / "extra_domains.txt",
]
UPSTREAM = (
    "https://raw.githubusercontent.com/blocklistproject/Lists/master/porn.txt"
)
OUTPUT = ROOT / "assets" / "blocklists" / "adult_domains.idx"

MASK = (1 << 64) - 1
FNV_OFFSET = 0xCBF29CE484222325
FNV_PRIME = 0x100000001B3


def fnv1a_64(value: str) -> int:
    """FNV-1a over the UTF-8 bytes, as an unsigned 64-bit integer."""
    digest = FNV_OFFSET
    for byte in value.encode("utf-8"):
        digest ^= byte
        digest = (digest * FNV_PRIME) & MASK
    return digest


def signed(value: int) -> int:
    """Two's-complement reinterpretation, so Kotlin's Long sort order matches."""
    return value - (1 << 64) if value >= (1 << 63) else value


def normalise(line: str) -> str | None:
    """One hosts-format line to a bare lowercase host, or None to skip it."""
    entry = line.split("#", 1)[0].strip()
    if not entry:
        return None
    # "0.0.0.0 example.com" / "127.0.0.1 example.com" / "example.com"
    host = entry.split()[-1].strip().lower().rstrip(".")
    if not host or "." not in host:
        return None
    if "*" in host or "/" in host or " " in host:
        return None
    if host.startswith("www."):
        host = host[4:]
    return host


def read_source(path: Path, *, download: bool) -> set[str]:
    if not path.exists():
        if download:
            print(f"downloading {UPSTREAM} -> {path}", file=sys.stderr)
            path.parent.mkdir(parents=True, exist_ok=True)
            with urllib.request.urlopen(UPSTREAM, timeout=120) as response:
                path.write_bytes(response.read())
        else:
            raise SystemExit(f"missing source file: {path}")
    domains: set[str] = set()
    with path.open(encoding="utf-8", errors="ignore") as handle:
        for line in handle:
            host = normalise(line)
            if host:
                domains.add(host)
    print(f"{path.name}: {len(domains)} domains", file=sys.stderr)
    return domains


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--source",
        action="append",
        type=Path,
        default=None,
        help="extra hosts file (repeatable); defaults to tools/blocklists/*",
    )
    parser.add_argument(
        "--no-download",
        action="store_true",
        help="fail instead of downloading the upstream list",
    )
    args = parser.parse_args()

    sources = args.source or DEFAULT_SOURCES
    domains: set[str] = set()
    for path in sources:
        domains |= read_source(path, download=not args.no_download)

    if not domains:
        raise SystemExit("no domains found; nothing written")

    hashes = sorted(signed(fnv1a_64(domain)) for domain in domains)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with OUTPUT.open("wb") as handle:
        for value in hashes:
            handle.write(struct.pack("<q", value))

    print(
        f"{OUTPUT.relative_to(ROOT)}: {len(hashes)} entries, "
        f"{OUTPUT.stat().st_size / (1024 * 1024):.1f} MB",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
