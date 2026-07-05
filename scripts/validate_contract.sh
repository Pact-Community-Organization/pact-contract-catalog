#!/bin/bash
#
# validate_contract.sh — validate a single contract entry's metadata and docs.
#
# Enforces the catalog's structural contract for one directory:
#   - metadata.yaml exists and is valid YAML
#   - README.md and AUDIT.md exist
#   - audit_status is one of the canonical ladder values
#     (see docs/CONTRACT_POLICIES.md §3.1)
#   - a .pact source file is present (unless the entry is a pure interface)
#
# Two metadata schemas are accepted:
#   Schema A (kip/core/marmalade/community): name, slug, version, repository,
#            license, audit_status
#   Schema B (ecosystem):                    name, namespace, module, version,
#            layer, audit_status
# The union requirement is: `name`, `version`, and `audit_status` must always be
# present; the schema is inferred from whether `slug` (A) or `namespace` (B) exists.
#
# Exit codes: 0 = valid, 1 = validation error (blocking).

set -euo pipefail

CONTRACT_DIR="${1:-}"

if [ -z "$CONTRACT_DIR" ]; then
    echo "Usage: $0 <contract-directory>"
    exit 1
fi

if ! command -v yq >/dev/null 2>&1; then
    echo "ERROR: 'yq' is required but not installed."
    exit 1
fi

METADATA="$CONTRACT_DIR/metadata.yaml"
PACT_FILE=$(find "$CONTRACT_DIR" -maxdepth 2 -name "*.pact" | head -1 || true)
FAIL=0

err()  { echo "  VIOLATION: $1"; FAIL=1; }
warn() { echo "  WARNING:   $1"; }

echo "Validating $CONTRACT_DIR ..."

# --- metadata.yaml presence + YAML validity -------------------------------
if [ ! -f "$METADATA" ]; then
    err "metadata.yaml not found"
    exit 1
fi
if ! yq '.' "$METADATA" > /dev/null 2>&1; then
    err "metadata.yaml is not valid YAML"
    exit 1
fi

# --- schema inference ------------------------------------------------------
HAS_SLUG=$(yq 'has("slug")' "$METADATA")
HAS_NS=$(yq 'has("namespace")' "$METADATA")

if [ "$HAS_SLUG" = "true" ]; then
    SCHEMA="A"
    REQUIRED_FIELDS=(name slug version repository license audit_status)
elif [ "$HAS_NS" = "true" ]; then
    SCHEMA="B"
    REQUIRED_FIELDS=(name namespace module version layer audit_status)
else
    err "metadata.yaml matches neither schema A (needs 'slug') nor schema B (needs 'namespace')"
    exit 1
fi
echo "  schema: $SCHEMA"

# --- required fields -------------------------------------------------------
for field in "${REQUIRED_FIELDS[@]}"; do
    if [ "$(yq "has(\"$field\")" "$METADATA")" != "true" ]; then
        err "missing required field '$field'"
    fi
done

# --- audit_status ladder ---------------------------------------------------
AUDIT_STATUS=$(yq '.audit_status // ""' "$METADATA")
case "$AUDIT_STATUS" in
    reference|unaudited|self-reviewed|community-reviewed|independently-audited) ;;
    *) err "invalid audit_status '$AUDIT_STATUS' — must be one of: reference, unaudited, self-reviewed, community-reviewed, independently-audited (see docs/CONTRACT_POLICIES.md §3.1)";;
esac

# --- companion docs --------------------------------------------------------
[ -f "$CONTRACT_DIR/README.md" ] || err "README.md not found"
[ -f "$CONTRACT_DIR/AUDIT.md" ]  || err "AUDIT.md not found"

# --- pact source -----------------------------------------------------------
# Pure-interface entries (kip/) may legitimately have no local .pact source
# when the interface is pre-deployed; everything else should ship source.
if [ -z "$PACT_FILE" ]; then
    if [[ "$CONTRACT_DIR" == *"/kip/"* ]]; then
        warn "no .pact file (interface entry — acceptable)"
    else
        warn "no .pact file found"
    fi
else
    echo "  source: $PACT_FILE"
    if command -v pact >/dev/null 2>&1; then
        # Non-blocking: ecosystem/reference sources have external deps that
        # need full network context; a load failure here is informational.
        pact "$PACT_FILE" > /dev/null 2>&1 || warn "pact could not load $PACT_FILE standalone (may need dependencies)"
    fi
fi

if [ "$FAIL" -eq 1 ]; then
    echo "  RESULT: FAILED"
    exit 1
fi
echo "  RESULT: OK"
