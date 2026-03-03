#!/bin/bash

# generate_index.sh - Build an index from contracts/**/metadata.yaml
# Supports layered directory structure: kip/ core/ marmalade/ ecosystem/ community/

set -e

OUTPUT_DIR="docs"
INDEX_JSON="$OUTPUT_DIR/index.json"
INDEX_MD="$OUTPUT_DIR/index.md"

mkdir -p "$OUTPUT_DIR"

echo "Generating contract index..."

# Collect all metadata.yaml files recursively (supports nested layers)
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

# Generate Markdown index — grouped by layer
echo "# Contract Index" > "$INDEX_MD"
echo "" >> "$INDEX_MD"
echo "_Generated from \`contracts/**/metadata.yaml\`. Entries grouped by dependency layer._" >> "$INDEX_MD"
echo "" >> "$INDEX_MD"

for layer in kip core marmalade ecosystem community; do
    LAYER_FILES=$(find "contracts/$layer" -name "metadata.yaml" 2>/dev/null | sort)
    [ -z "$LAYER_FILES" ] && continue

    case "$layer" in
        kip)       LAYER_LABEL="KIP Standards (\`kip/\`)";;
        core)      LAYER_LABEL="Core Infrastructure (\`core/\`)";;
        marmalade) LAYER_LABEL="Marmalade NFT Framework (\`marmalade/\`)";;
        ecosystem) LAYER_LABEL="Ecosystem Modules (\`ecosystem/\`) — ranked by blockchain data";;
        community) LAYER_LABEL="Community Contracts (\`community/\`)";;
    esac

    echo "## $LAYER_LABEL" >> "$INDEX_MD"
    echo "" >> "$INDEX_MD"
    if [ "$layer" = "ecosystem" ]; then
        echo "| Name | Slug | Version | Audit Status | Category | Chains |" >> "$INDEX_MD"
        echo "|------|------|---------|--------------|----------|--------|" >> "$INDEX_MD"
    else
        echo "| Name | Slug | Version | Audit Status | Tags |" >> "$INDEX_MD"
        echo "|------|------|---------|--------------|------|" >> "$INDEX_MD"
    fi

    for file in $LAYER_FILES; do
        name=$(yq '.name // ""' "$file" 2>/dev/null || echo "")
        slug=$(yq '.slug // .name // ""' "$file" 2>/dev/null || echo "")
        version=$(yq '.version // ""' "$file" 2>/dev/null || echo "")
        audit_status=$(yq '.audit_status // ""' "$file" 2>/dev/null || echo "")
        # tags: join array if present, else fall back to category string
        has_tags=$(yq 'has("tags")' "$file" 2>/dev/null || echo "false")
        if [ "$has_tags" = "true" ]; then
            tags=$(yq '.tags | join(", ")' "$file" 2>/dev/null || echo "")
        else
            tags=$(yq '.category // ""' "$file" 2>/dev/null || echo "")
        fi
        # chains_deployed: append /20 if field exists
        has_chains=$(yq 'has("chains_deployed")' "$file" 2>/dev/null || echo "false")
        if [ "$has_chains" = "true" ]; then
            chains_num=$(yq '.chains_deployed' "$file" 2>/dev/null || echo "")
            chains="${chains_num}/20"
            echo "| $name | $slug | $version | $audit_status | $tags | $chains |" >> "$INDEX_MD"
        else
            echo "| $name | $slug | $version | $audit_status | $tags |" >> "$INDEX_MD"
        fi
    done
    echo "" >> "$INDEX_MD"
done

echo "Index generated in $OUTPUT_DIR/"
echo "Index generated in $OUTPUT_DIR/"