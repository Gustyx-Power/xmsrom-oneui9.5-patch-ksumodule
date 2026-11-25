#!/usr/bin/env python3
"""
Builds:
  1. Modular .tar.xz add-on packs in dist/packs/ from the ROM dump
  2. Updated catalog.json (exact sha256 + archive_bytes + unpacked_mb)
  3. Thin KernelSU Next module ZIP in dist/xmsrom-oneui9.5-addons-<version>.zip
"""

import argparse
import hashlib
import json
import lzma
import os
import shutil
import tarfile
import time
import zipfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_DUMP = REPO_ROOT.parent
EXTRA_DIR = REPO_ROOT / "extra_sources"
PRESETS_DIR = REPO_ROOT / "presets"
MODULE_DIR = REPO_ROOT / "module"
DIST_DIR = REPO_ROOT / "dist"
PACKS_DIR = DIST_DIR / "packs"
CATALOG_PATH = REPO_ROOT / "catalog.json"

LF_EXTENSIONS = {".sh", ".prop", ".json", ".js", ".css", ".html", ".md"}


def read_version() -> str:
    for line in (MODULE_DIR / "module.prop").read_text(encoding="utf-8").splitlines():
        if line.startswith("version="):
            return line.split("=", 1)[1].strip()
    return "v1.0.0"


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        while chunk := f.read(1024 * 1024):
            h.update(chunk)
    return h.hexdigest()


def build_packs(dump_dir: Path, preset: int, only_ids: set[str] | None = None) -> None:
    PACKS_DIR.mkdir(parents=True, exist_ok=True)
    catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))

    for pack in catalog["packs"]:
        pid = pack["id"]
        if only_ids and pid not in only_ids:
            continue

        targets = pack.get("targets", [])
        out_archive = PACKS_DIR / pack["archive"]
        tmp_archive = PACKS_DIR / (pack["archive"] + ".tmp")

        files_to_add: list[tuple[Path, str]] = []
        total_unpacked = 0
        for rel in targets:
            src_base = next(
                (b for b in (PRESETS_DIR, EXTRA_DIR, dump_dir) if (b / rel).exists()),
                dump_dir,
            )
            src_path = src_base / rel
            if not src_path.exists():
                raise FileNotFoundError(f"[{pid}] Missing source path: {src_path}")
            if src_path.is_file():
                items = [src_path]
            else:
                items = [
                    p
                    for p in src_path.rglob("*")
                    if p.is_file() and p.suffix in {".apk", ".so", ".xml"} and "oat" not in p.parts
                ]
            if not items:
                raise FileNotFoundError(f"[{pid}] No APK/SO/XML files inside: {src_path}")
            for item in sorted(items):
                arcname = f"system/{item.relative_to(src_base).as_posix()}"
                files_to_add.append((item, arcname))
                total_unpacked += item.stat().st_size

        t0 = time.time()
        print(f"[PACK] {pid}: compressing {len(files_to_add)} APK(s) ({total_unpacked / 1048576:.1f} MB raw)...")
        with lzma.open(tmp_archive, "wb", preset=preset) as xzf:
            with tarfile.open(fileobj=xzf, mode="w") as tf:
                added_dirs = set()
                for src, arcname in files_to_add:
                    parts = Path(arcname).parts
                    for i in range(1, len(parts)):
                        d = "/".join(parts[:i])
                        if d not in added_dirs:
                            ti = tarfile.TarInfo(d)
                            ti.type = tarfile.DIRTYPE
                            ti.mode = 0o755
                            ti.uid = 0
                            ti.gid = 0
                            ti.uname = "root"
                            ti.gname = "root"
                            ti.mtime = 1700000000
                            tf.addfile(ti)
                            added_dirs.add(d)
                    ti = tarfile.TarInfo(arcname)
                    ti.size = src.stat().st_size
                    ti.mode = 0o644
                    ti.uid = 0
                    ti.gid = 0
                    ti.uname = "root"
                    ti.gname = "root"
                    ti.mtime = 1700000000
                    with src.open("rb") as f:
                        tf.addfile(ti, f)

        tmp_archive.replace(out_archive)
        pack["archive_bytes"] = out_archive.stat().st_size
        pack["unpacked_mb"] = round(total_unpacked / 1048576, 1)
        pack["sha256"] = sha256_file(out_archive)
        dt = time.time() - t0
        print(
            f"  -> {out_archive.name}: {pack['archive_bytes'] / 1048576:.1f} MB "
            f"(ratio {pack['archive_bytes'] / total_unpacked * 100:.1f}%, {dt:.1f}s) sha256={pack['sha256'][:12]}..."
        )

    CATALOG_PATH.write_text(json.dumps(catalog, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(f"[DONE] Updated {CATALOG_PATH}")


def build_module_zip() -> Path:
    DIST_DIR.mkdir(parents=True, exist_ok=True)
    version = read_version()
    zip_path = DIST_DIR / f"xmsrom-oneui9.5-addons-{version}.zip"
    tmp_zip = zip_path.with_suffix(".zip.tmp")

    # Sync latest catalog.json inside module bundle for offline initial display
    catalog_data = CATALOG_PATH.read_bytes().replace(b"\r\n", b"\n")

    with zipfile.ZipFile(tmp_zip, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for path in sorted(MODULE_DIR.rglob("*")):
            if not path.is_file():
                continue
            rel = path.relative_to(MODULE_DIR).as_posix()
            if rel == "catalog.json":
                continue
            raw = path.read_bytes()
            if path.suffix in LF_EXTENSIONS or path.name == "module.prop":
                raw = raw.replace(b"\r\n", b"\n")
            info = zipfile.ZipInfo(rel, date_time=(2026, 11, 25, 0, 0, 0))
            is_exec = path.suffix == ".sh"
            info.external_attr = ((0o100755 if is_exec else 0o100644) << 16)
            info.compress_type = zipfile.ZIP_DEFLATED
            zf.writestr(info, raw)

        # Include bundled catalog.json
        info = zipfile.ZipInfo("catalog.json", date_time=(2026, 11, 25, 0, 0, 0))
        info.external_attr = (0o100644 << 16)
        info.compress_type = zipfile.ZIP_DEFLATED
        zf.writestr(info, catalog_data)

    tmp_zip.replace(zip_path)
    print(f"[ZIP] Built thin KSU module: {zip_path} ({zip_path.stat().st_size / 1024:.1f} KB)")
    return zip_path


def main() -> None:
    parser = argparse.ArgumentParser(description="Build XMSROM OneUI 9.5 KSU Add-on Module and Packs")
    parser.add_argument("--dump-dir", type=Path, default=DEFAULT_DUMP, help="Path to SM-S948B ROM dump")
    parser.add_argument("--preset", type=int, default=3, help="LZMA compression preset 0..9 (default: 3)")
    parser.add_argument("--zip-only", action="store_true", help="Only build thin module ZIP")
    parser.add_argument("--packs", nargs="*", help="Build only specific pack IDs")
    args = parser.parse_args()

    if not args.zip_only:
        only = set(args.packs) if args.packs else None
        build_packs(args.dump_dir, args.preset, only)
    build_module_zip()


if __name__ == "__main__":
    main()
