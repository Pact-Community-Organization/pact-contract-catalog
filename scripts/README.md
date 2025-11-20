generate_index
===============

This folder contains the `generate_index.py` utility used to build a
canonical `index.json` for the `pact-contract-catalog` repository.

What it does
- Scans `contracts/<slug>/metadata.yaml` files
- Performs lightweight validation and an allowlist of safe fields
- Emits an `index.json` file at the repository root (or a specified path)

Usage

Install dependencies:

```bash
cd pact-contract-catalog
pip3 install --user -r requirements.txt
```

Run the generator:

```bash
./scripts/generate_index.sh
# or
python3 ./scripts/generate_index.py . --out ./index.json
```

Notes
- The script will warn and skip metadata files that are missing required
  fields.
- Keep `metadata.yaml` files free of secrets; the generator will
  include permitted fields in the published `index.json`.
