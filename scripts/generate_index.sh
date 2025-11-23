#!/bin/bash

# generate_index.sh - Build an index from contracts/*/metadata.yaml

set -e

OUTPUT_DIR="docs"
INDEX_JSON="$OUTPUT_DIR/index.json"
INDEX_MD="$OUTPUT_DIR/index.md"

mkdir -p "$OUTPUT_DIR"

echo "Generating contract index..."

# Collect all metadata.yaml files
METADATA_FILES=$(find contracts -name "metadata.yaml" | sort)

# Start JSON array
echo "[" > "$INDEX_JSON"

FIRST=true
for file in $METADATA_FILES; do
    if [ "$FIRST" = true ]; then
        FIRST=false
    else
        echo "," >> "$INDEX_JSON"
    fi
    cat "$file" | yq -o=json >> "$INDEX_JSON"
done

echo "]" >> "$INDEX_JSON"

# Generate Markdown index
echo "# Contract Index" > "$INDEX_MD"
echo "" >> "$INDEX_MD"
echo "| Name | Slug | Version | Audit Status | Tags |" >> "$INDEX_MD"
echo "|------|------|---------|--------------|------|" >> "$INDEX_MD"

for file in $METADATA_FILES; do
    name=$(yq '.name' "$file")
    slug=$(yq '.slug' "$file")
    version=$(yq '.version' "$file")
    audit_status=$(yq '.audit_status' "$file")
    tags=$(yq '.tags | join(", ")' "$file")
    echo "| $name | $slug | $version | $audit_status | $tags |" >> "$INDEX_MD"
done

echo "Index generated in $OUTPUT_DIR/"