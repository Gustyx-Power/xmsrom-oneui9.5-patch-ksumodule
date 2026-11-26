#!/usr/bin/env python3
"""Normalize module scripts to LF and package xmsrom-thermal-fix-v1.0.0.zip."""

import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MOD_DIR = ROOT / "module"
OUT_ZIP = ROOT / "dist" / "xmsrom-thermal-fix-v1.0.0.zip"
TEXT_NAMES = {"module.prop", "skip_mount"}


def main() -> None:
    OUT_ZIP.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(OUT_ZIP, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for p in sorted(MOD_DIR.rglob("*")):
            if p.is_dir():
                continue
            rel = p.relative_to(MOD_DIR).as_posix()
            if p.suffix == ".sh" or p.name in TEXT_NAMES:
                data = p.read_bytes().replace(b"\r\n", b"\n")
                p.write_bytes(data)
                info = zipfile.ZipInfo(rel)
                info.compress_type = zipfile.ZIP_DEFLATED
                info.external_attr = (0o755 if p.suffix == ".sh" else 0o644) << 16
                zf.writestr(info, data)
            else:
                zf.write(p, rel)
    print(f"Built {OUT_ZIP} ({OUT_ZIP.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
