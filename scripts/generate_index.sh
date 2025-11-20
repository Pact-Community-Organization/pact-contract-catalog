#!/usr/bin/env bash
set -euo pipefail
ROOT="$(dirname "$0")/.."
OUT="$ROOT/index.json"

# Generate index.json (written to $OUT). This script calls the
# Python CLI `generate_index.py` which performs validation and an
# allowlist of fields before writing JSON to the output file.

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required to run this script" >&2
  exit 2
fi

PY_SCRIPT="$ROOT/scripts/generate_index.py"
if [ ! -f "$PY_SCRIPT" ]; then
  echo "Missing $PY_SCRIPT" >&2
  exit 2
fi

python3 "$PY_SCRIPT" "$ROOT" --out "$OUT"

exit 0
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(dirname "$0")/.."
OUT="$ROOT/index.json"

# Generate index.json (written to $OUT). No other stdout should be emitted
python3 - "$ROOT" <<'PY' > "$OUT"
import sys, os, yaml, json
root = os.path.abspath(sys.argv[1])
contracts_dir = os.path.join(root, 'contracts')
items = []
if os.path.isdir(contracts_dir):
    for slug in sorted(os.listdir(contracts_dir)):
        path = os.path.join(contracts_dir, slug)
        meta = os.path.join(path, 'metadata.yaml')
        if os.path.isfile(meta):
            with open(meta,'r') as f:
                data = yaml.safe_load(f) or {}
                items.append(data)
print(json.dumps(items, indent=2))
PY

exit 0
