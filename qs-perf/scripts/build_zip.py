#!/usr/bin/env python3
"""Normalize module scripts to LF and package xmsrom-qs-perf-v2.0.0.zip."""

import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MOD_DIR = ROOT / "module"
STAGING_DIR = ROOT / "staging"
OUT_ZIP = ROOT / "dist" / "xmsrom-qs-perf-v2.0.0.zip"
TEXT_NAMES = {"module.prop", "skip_mount", "sysui_ver"}


def write_tree(zf: zipfile.ZipFile, base_dir: Path, written: set[str]) -> None:
    if not base_dir.is_dir():
        return
    for p in sorted(base_dir.rglob("*")):
        if p.is_dir():
            continue
        rel = p.relative_to(base_dir).as_posix()
        if rel in written:
            continue
        written.add(rel)
        if p.suffix == ".sh" or p.name in TEXT_NAMES:
            data = p.read_bytes().replace(b"\r\n", b"\n")
            p.write_bytes(data)
            info = zipfile.ZipInfo(rel)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = (0o755 if p.suffix == ".sh" else 0o644) << 16
            zf.writestr(info, data)
        else:
            zf.write(p, rel)


def main() -> None:
    OUT_ZIP.parent.mkdir(parents=True, exist_ok=True)
    written: set[str] = set()
    with zipfile.ZipFile(OUT_ZIP, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        write_tree(zf, STAGING_DIR, written)
        write_tree(zf, MOD_DIR, written)
    print(f"Built {OUT_ZIP} ({OUT_ZIP.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
