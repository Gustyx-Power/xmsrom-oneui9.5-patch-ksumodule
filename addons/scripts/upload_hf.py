#!/usr/bin/env python3
"""
Upload built dist/packs/*.tar.xz and catalog.json to a Hugging Face Dataset repo.
Usage:
  pip install huggingface_hub
  set HF_TOKEN=hf_xxxxxxxxxxxxxxxxx
  python scripts/upload_hf.py --repo GustyxPower/xmsrom-oneui9.5-addons
"""

import argparse
import os
from pathlib import Path

from huggingface_hub import HfApi

REPO_ROOT = Path(__file__).resolve().parent.parent
PACKS_DIR = REPO_ROOT / "dist" / "packs"
CATALOG_PATH = REPO_ROOT / "catalog.json"


def main() -> None:
    parser = argparse.ArgumentParser(description="Upload add-on packs to Hugging Face Dataset")
    parser.add_argument("--repo", default="GustyxPower/xmsrom-oneui9.5-addons", help="Hugging Face dataset repo id")
    parser.add_argument("--token", default=os.environ.get("HF_TOKEN"), help="Hugging Face Write Token")
    parser.add_argument(
        "--packs",
        nargs="*",
        help="Only upload these pack IDs (e.g. samsung-camera); catalog.json is always synced",
    )
    args = parser.parse_args()

    if not PACKS_DIR.is_dir():
        raise SystemExit(f"Missing {PACKS_DIR}; run scripts/build_all.py first.")

    api = HfApi(token=args.token)
    api.create_repo(repo_id=args.repo, repo_type="dataset", exist_ok=True)

    if args.packs:
        paths = [PACKS_DIR / f"{pid}.tar.xz" for pid in args.packs]
        missing = [str(p) for p in paths if not p.is_file()]
        if missing:
            raise SystemExit(f"Missing pack archive(s): {', '.join(missing)}")
        print(f"[HF] Uploading {len(paths)} pack(s) to datasets/{args.repo}...")
        for path in paths:
            api.upload_file(
                path_or_fileobj=str(path),
                path_in_repo=path.name,
                repo_id=args.repo,
                repo_type="dataset",
                commit_message=f"Upload {path.name}",
            )
            print(f"  -> {path.name} ({path.stat().st_size / 1048576:.1f} MB)")
    else:
        print(f"[HF] Uploading packs from {PACKS_DIR} to datasets/{args.repo}...")
        api.upload_folder(
            folder_path=str(PACKS_DIR),
            repo_id=args.repo,
            repo_type="dataset",
            commit_message="Upload XMSROM OneUI 9.5 modular add-on packs",
        )
    api.upload_file(
        path_or_fileobj=str(CATALOG_PATH),
        path_in_repo="catalog.json",
        repo_id=args.repo,
        repo_type="dataset",
        commit_message="Sync catalog.json",
    )
    print(f"[HF] Done: https://huggingface.co/datasets/{args.repo}")


if __name__ == "__main__":
    main()
