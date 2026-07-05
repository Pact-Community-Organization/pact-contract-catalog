#!/bin/bash

# generate_index.sh - Build an index from contracts/**/metadata.yaml
# Two-tree layout per ADR-001:
#   contracts/registry/{kip,core,marmalade,ecosystem,community}
#   contracts/library/
# Census sections (ecosystem, registry community) render a 6-column table
# with a Chains column; curated sections render a 5-column table with Tags.

set -e

OUTPUT_DIR="docs"
INDEX_JSON="$OUTPUT_DIR/index.json"
INDEX_MD="$OUTPUT_DIR/index.md"

mkdir -p "$OUTPUT_DIR"

echo "Generating contract index..."

# --- JSON index: all metadata, recursive -------------------------------------
METADATA_FILES=$(find contracts -name "metadata.yaml" | sort)

echo "[" > "$INDEX_JSON"
FIRST=true
for file in $METADATA_FILES; do
    if [ "$FIRST" = true ]; then
        FIRST=false
    else
        echo "," >> "$INDEX_JSON"
    fi
    yq -o=json '.' "$file" >> "$INDEX_JSON"
done
echo "]" >> "$INDEX_JSON"

# --- Markdown index -----------------------------------------------------------
echo "# Contract Index" > "$INDEX_MD"
echo "" >> "$INDEX_MD"
echo "_Generated from \`contracts/**/metadata.yaml\`._" >> "$INDEX_MD"
echo "" >> "$INDEX_MD"
echo "- **Library** — PCO-authored deployable templates: copy, adapt, deploy." >> "$INDEX_MD"
echo "- **Registry** — observed contracts (upstream standards + on-chain census): read-only reference." >> "$INDEX_MD"
echo "" >> "$INDEX_MD"

# emit_section <dir> <heading> <style>
#   style "tags"   — 5 columns: Name | Slug | Version | Audit Status | Tags
#   style "census" — 6 columns: Name | Slug | Version | Audit Status | Category | Chains
emit_section() {
    local dir="$1" heading="$2" style="$3"
    local files
    files=$(find "$dir" -name "metadata.yaml" 2>/dev/null | sort)
    [ -z "$files" ] && return 0

    echo "## $heading" >> "$INDEX_MD"
    echo "" >> "$INDEX_MD"
    if [ "$style" = "census" ]; then
        echo "| Name | Slug | Version | Audit Status | Category | Chains |" >> "$INDEX_MD"
        echo "|------|------|---------|--------------|----------|--------|" >> "$INDEX_MD"
    else
        echo "| Name | Slug | Version | Audit Status | Tags |" >> "$INDEX_MD"
        echo "|------|------|---------|--------------|------|" >> "$INDEX_MD"
    fi

    local file name slug version audit_status tags category chains
    for file in $files; do
        name=$(yq '.name // ""' "$file")
        slug=$(yq '.slug // .name // ""' "$file")
        version=$(yq '.version // ""' "$file")
        audit_status=$(yq '.audit_status // ""' "$file")
        if [ "$style" = "census" ]; then
            category=$(yq '.category // ""' "$file")
            if [ "$(yq 'has("chains_deployed")' "$file")" = "true" ]; then
                chains="$(yq '.chains_deployed' "$file")/20"
            else
                chains="—"
            fi
            echo "| $name | $slug | $version | $audit_status | $category | $chains |" >> "$INDEX_MD"
        else
            if [ "$(yq 'has("tags")' "$file")" = "true" ]; then
                tags=$(yq '.tags | join(", ")' "$file")
            else
                tags=$(yq '.category // ""' "$file")
            fi
            echo "| $name | $slug | $version | $audit_status | $tags |" >> "$INDEX_MD"
        fi
    done
    echo "" >> "$INDEX_MD"
}

emit_section "contracts/library"            "Library — Deployable Templates (\`library/\`)"                       "tags"
emit_section "contracts/registry/kip"       "Registry — KIP Standards (\`registry/kip/\`)"                        "tags"
emit_section "contracts/registry/core"      "Registry — Core Infrastructure (\`registry/core/\`)"                 "tags"
emit_section "contracts/registry/marmalade" "Registry — Marmalade NFT Framework (\`registry/marmalade/\`)"        "tags"
emit_section "contracts/registry/ecosystem" "Registry — Ecosystem Modules (\`registry/ecosystem/\`) — census"     "census"
emit_section "contracts/registry/community" "Registry — Community On-Chain Modules (\`registry/community/\`) — census" "census"

echo "Index generated in $OUTPUT_DIR/"
