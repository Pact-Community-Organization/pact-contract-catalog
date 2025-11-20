#!/usr/bin/env bash
set -euo pipefail
ROOT="$(dirname "$0")/.."
OUT="$ROOT/index.json"

# Generate index.json (written to $OUT). No other stdout should be emitted
python3 - <<'PY' > "$OUT"
import os, yaml, json
root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
contracts_dir = os.path.join(root, 'contracts')
items = []
if os.path.isdir(contracts_dir):
    for slug in sorted(os.listdir(contracts_dir)):
        path = os.path.join(root, 'contracts', slug)
        meta = os.path.join(path, 'metadata.yaml')
        if os.path.isfile(meta):
            with open(meta,'r') as f:
                data = yaml.safe_load(f) or {}
                items.append(data)
print(json.dumps(items, indent=2))
PY

exit 0
