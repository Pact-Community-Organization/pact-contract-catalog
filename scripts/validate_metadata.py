#!/usr/bin/env python3
"""Validate pact contract metadata YAML files against the JSON Schema.

Usage:
  validate_metadata.py <path> [--schema metadata/schema.json]

If <path> is a directory, it will scan for `contracts/*/metadata.yaml` files.
"""
import argparse
import json
import os
import sys
from glob import glob

try:
    import yaml
    from jsonschema import validate, ValidationError
except Exception:
    print("Missing dependencies. Please install requirements: pip install -r requirements.txt", file=sys.stderr)
    raise


def load_schema(schema_path):
    with open(schema_path, 'r', encoding='utf-8') as f:
        return json.load(f)


def load_yaml(path):
    with open(path, 'r', encoding='utf-8') as f:
        return yaml.safe_load(f)


def find_metadata_files(root):
    # check direct path
    p = os.path.join(root, 'metadata.yaml')
    if os.path.isfile(p):
        return [p]
    # if root already points to 'contracts', search contracts/*/metadata.yaml
    if os.path.basename(os.path.normpath(root)) == 'contracts':
        pattern = os.path.join(root, '*', 'metadata.yaml')
    else:
        pattern = os.path.join(root, 'contracts', '*', 'metadata.yaml')
    return sorted(glob(pattern))


def validate_file(path, schema):
    try:
        data = load_yaml(path)
    except Exception as e:
        return False, f"YAML load error: {e}"
    try:
        validate(instance=data, schema=schema)
        return True, None
    except ValidationError as e:
        return False, str(e)


def main():
    parser = argparse.ArgumentParser(description='Validate contract metadata YAML files')
    parser.add_argument('path', help='File or directory to validate')
    parser.add_argument('--schema', default='metadata/schema.json', help='Path to JSON schema')
    args = parser.parse_args()

    schema_path = args.schema
    if not os.path.isfile(schema_path):
        print(f"Schema not found at {schema_path}", file=sys.stderr)
        sys.exit(2)

    schema = load_schema(schema_path)

    targets = []
    if os.path.isdir(args.path):
        targets = find_metadata_files(args.path)
    elif os.path.isfile(args.path):
        targets = [args.path]
    else:
        print(f"Path not found: {args.path}", file=sys.stderr)
        sys.exit(2)

    if not targets:
        print("No metadata files found.")
        sys.exit(0)

    all_ok = True
    for t in targets:
        ok, err = validate_file(t, schema)
        if ok:
            print(f"OK: {t}")
        else:
            all_ok = False
            print(f"FAIL: {t}\n  {err}\n")

    sys.exit(0 if all_ok else 3)


if __name__ == '__main__':
    main()
