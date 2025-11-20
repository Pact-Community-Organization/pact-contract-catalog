#!/usr/bin/env python3
"""
generate_index.py

Scan a `contracts/` directory for `metadata.yaml` files and produce a
canonical `index.json` containing an array of metadata objects.

Usage: ./generate_index.py /path/to/repo-root --out /path/to/index.json

This script performs a lightweight validation and an allowlist of fields
to avoid publishing arbitrary private keys or internal fields.
"""

import argparse
import json
import os
import sys

try:
    import yaml
except Exception as e:
    print("Missing dependency 'PyYAML'. Install with: pip3 install -r requirements.txt", file=sys.stderr)
    raise

ALLOWED_KEYS = [
    "name",
    "description",
    "repository",
    "version",
    "auditState",
    "tags",
    "authors",
]

REQUIRED_KEYS = ["name", "repository", "version"]


def load_meta(path):
    with open(path, "r", encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
    if not isinstance(data, dict):
        raise ValueError(f"metadata at {path} did not parse to a mapping")
    # allowlist keys
    item = {k: data.get(k) for k in ALLOWED_KEYS if k in data}
    # simple validation
    missing = [k for k in REQUIRED_KEYS if k not in item or item.get(k) in (None, "")]
    if missing:
        raise ValueError(f"metadata at {path} missing required keys: {missing}")
    return item


def build_index(root, contracts_dir, out_path):
    items = []
    if os.path.isdir(contracts_dir):
        for slug in sorted(os.listdir(contracts_dir)):
            path = os.path.join(contracts_dir, slug)
            meta = os.path.join(path, "metadata.yaml")
            if os.path.isfile(meta):
                try:
                    item = load_meta(meta)
                    items.append(item)
                except Exception as e:
                    print(f"Warning: skipping {meta}: {e}", file=sys.stderr)
    # write output
    with open(out_path, "w", encoding="utf-8") as o:
        json.dump(items, o, indent=2, ensure_ascii=False)


def main(argv=None):
    p = argparse.ArgumentParser()
    p.add_argument("root", help="Repository root (containing contracts/)")
    p.add_argument("--contracts-dir", help="contracts directory (optional)")
    p.add_argument("--out", help="output path for index.json (optional)")
    args = p.parse_args(argv)

    root = os.path.abspath(args.root)
    contracts_dir = args.contracts_dir or os.path.join(root, "contracts")
    out_path = args.out or os.path.join(root, "index.json")

    build_index(root, contracts_dir, out_path)


if __name__ == "__main__":
    main()
