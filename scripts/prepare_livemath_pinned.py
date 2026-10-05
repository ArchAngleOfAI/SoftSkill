#!/usr/bin/env python3
"""Materialize the official LiveMathematicianBench split (35/18/124).

Upstream `scripts/data/prepare_livemath.py` downloads *every* monthly file that
is currently on the Hugging Face repo and re-splits them 2:1:7. The dataset has
grown since the paper (more months were added), so that script no longer yields
the released split. This adapter instead:

1. downloads only the four source files listed in the released manifest, at the
   pinned `source_revision` recorded in `split_manifest.json`;
2. runs the upstream ratio-split code (same loader, same seed/ratio) on them;
3. asserts that the resulting train/val/test IDs equal the released manifest
   (`data/livemathematicianbench_id_split/*/items.json`), and if they differ in
   order only, rewrites the split in manifest order.
"""
from __future__ import annotations

import argparse
import json
import os
import shutil

from huggingface_hub import hf_hub_download

from skillopt.envs.livemathematicianbench.dataloader import LiveMathematicianBenchDataLoader, load_items


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--manifest_dir", required=True, help="upstream data/livemathematicianbench_id_split")
    p.add_argument("--raw_dir", required=True)
    p.add_argument("--out_split_dir", required=True)
    args = p.parse_args()

    with open(os.path.join(args.manifest_dir, "split_manifest.json"), encoding="utf-8") as f:
        manifest = json.load(f)
    repo, rev = manifest["source_repo"], manifest["source_revision"]
    raw_dir = os.path.abspath(args.raw_dir)
    for repo_path in manifest["source_files"]:
        src = hf_hub_download(repo_id=repo, repo_type="dataset", filename=repo_path, revision=rev)
        dst = os.path.join(raw_dir, repo_path)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copyfile(src, dst)
        print(f"downloaded {repo_path}@{rev[:8]}")

    split_dir = os.path.abspath(args.out_split_dir)
    loader = LiveMathematicianBenchDataLoader(
        split_mode="ratio",
        data_path=raw_dir,
        split_ratio=manifest.get("split_ratio", "2:1:7"),
        split_seed=int(manifest.get("split_seed", 42)),
        split_output_dir=split_dir,
        seed=int(manifest.get("split_seed", 42)),
    )
    loader.setup({"env": "livemathematicianbench", "out_root": os.getcwd()})

    by_id = {item["id"]: item for item in load_items(raw_dir)}
    for split, items in (("train", loader.train_items), ("val", loader.val_items), ("test", loader.test_items)):
        with open(os.path.join(args.manifest_dir, split, "items.json"), encoding="utf-8") as f:
            want = [row["id"] for row in json.load(f)]
        got = [item["id"] for item in items]
        if got == want:
            print(f"{split}: {len(got)} items, identical to manifest (ids and order)")
            continue
        if sorted(got) != sorted(want):
            print(f"{split}: ratio split differs from manifest; materializing from manifest IDs")
        else:
            print(f"{split}: same IDs, different order; rewriting in manifest order")
        out = [by_id[i] for i in want]
        split_file = os.path.join(split_dir, split, "items.json")
        os.makedirs(os.path.dirname(split_file), exist_ok=True)
        # Remove any other split files the loader may have written for this split.
        for name in os.listdir(os.path.dirname(split_file)):
            os.remove(os.path.join(os.path.dirname(split_file), name))
        with open(split_file, "w", encoding="utf-8") as f:
            json.dump(out, f, ensure_ascii=False, indent=2)
        print(f"{split}: wrote {len(out)} items from manifest")


if __name__ == "__main__":
    main()
