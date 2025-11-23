#!/bin/bash

# validate_contract.sh - Validate contract metadata and basic checks

set -e

CONTRACT_DIR="$1"

if [ -z "$CONTRACT_DIR" ]; then
    echo "Usage: $0 <contract-directory>"
    exit 1
fi

METADATA="$CONTRACT_DIR/metadata.yaml"
PACT_FILE=$(find "$CONTRACT_DIR" -name "*.pact" | head -1)

echo "Validating contract in $CONTRACT_DIR..."

# Check if metadata.yaml exists
if [ ! -f "$METADATA" ]; then
    echo "ERROR: metadata.yaml not found in $CONTRACT_DIR"
    exit 1
fi

# Validate YAML syntax
if ! yq '.' "$METADATA" > /dev/null; then
    echo "ERROR: Invalid YAML in $METADATA"
    exit 1
fi

# Check required fields
REQUIRED_FIELDS=("name" "slug" "version" "repository" "license" "audit_status")
for field in "${REQUIRED_FIELDS[@]}"; do
    if ! yq -e ".$field" "$METADATA" > /dev/null; then
        echo "ERROR: Missing required field '$field' in $METADATA"
        exit 1
    fi
done

# Check audit_status values
AUDIT_STATUS=$(yq '.audit_status' "$METADATA")
if [[ "$AUDIT_STATUS" != "audited" && "$AUDIT_STATUS" != "in-review" && "$AUDIT_STATUS" != "not-audited" ]]; then
    echo "ERROR: Invalid audit_status '$AUDIT_STATUS'. Must be 'audited', 'in-review', or 'not-audited'"
    exit 1
fi

# Check if README.md exists
if [ ! -f "$CONTRACT_DIR/README.md" ]; then
    echo "ERROR: README.md not found in $CONTRACT_DIR"
    exit 1
fi

# Basic Pact file check (if exists)
if [ -n "$PACT_FILE" ]; then
    echo "Found Pact file: $PACT_FILE"
    # Add basic syntax check if pact tool is available
    if command -v pact &> /dev/null; then
        if ! pact -r "$PACT_FILE" > /dev/null 2>&1; then
            echo "WARNING: Pact file may have syntax issues"
        fi
    else
        echo "INFO: Pact CLI not available for syntax check"
    fi
else
    echo "WARNING: No .pact file found in $CONTRACT_DIR"
fi

echo "Validation passed for $CONTRACT_DIR"