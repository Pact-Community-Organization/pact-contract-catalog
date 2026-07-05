#!/bin/bash
#
# validate_contract.sh — validate a single contract entry's metadata and docs.
#
# The catalog has two product trees (ADR-001):
#
#   contracts/registry/  — observed contracts (upstream + on-chain census).
#                          Schema A (curated reference) or schema B (census).
#   contracts/library/   — PCO-authored deployable templates.
#                          Schema A required, plus the library quality gate:
#                            - co-located .repl test suite
#                            - audit_status of self-reviewed or better
#
# Common requirements for every entry:
#   - metadata.yaml exists and is valid YAML
#   - README.md and AUDIT.md exist
#   - audit_status is one of the canonical ladder values
#     (see docs/CONTRACT_POLICIES.md §3.1)
#
# Schemas:
#   Schema A: name, slug, version, repository, license, audit_status
#   Schema B: name, namespace, module, version, layer, audit_status
# Inferred from whether `slug` (A) or `namespace` (B) is present.
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

# --- tree detection ----------------------------------------------------------
case "$CONTRACT_DIR" in
    *contracts/library/*)  TREE="library";;
    *contracts/registry/*) TREE="registry";;
    *) TREE="unknown";;
esac

echo "Validating $CONTRACT_DIR ..."
echo "  tree:   $TREE"

if [ "$TREE" = "unknown" ]; then
    err "entry is outside contracts/registry/ and contracts/library/ (ADR-001 layout)"
fi

# --- metadata.yaml presence + YAML validity -------------------------------
if [ ! -f "$METADATA" ]; then
    err "metadata.yaml not found"
    exit 1
fi
if ! yq '.' "$METADATA" > /dev/null 2>&1; then
    err "metadata.yaml is not valid YAML"
    exit 1
fi

# --- schema inference --------------------------------------------------------
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

if [ "$TREE" = "library" ] && [ "$SCHEMA" != "A" ]; then
    err "library/ entries must use schema A (slug/repository/license/authors)"
fi

# --- required fields ---------------------------------------------------------
for field in "${REQUIRED_FIELDS[@]}"; do
    if [ "$(yq "has(\"$field\")" "$METADATA")" != "true" ]; then
        err "missing required field '$field'"
    fi
done

# --- audit_status ladder -----------------------------------------------------
AUDIT_STATUS=$(yq '.audit_status // ""' "$METADATA")
case "$AUDIT_STATUS" in
    reference|unaudited|self-reviewed|community-reviewed|independently-audited) ;;
    *) err "invalid audit_status '$AUDIT_STATUS' — must be one of: reference, unaudited, self-reviewed, community-reviewed, independently-audited (see docs/CONTRACT_POLICIES.md §3.1)";;
esac

# Library quality gate: templates must be at self-reviewed or better.
if [ "$TREE" = "library" ]; then
    case "$AUDIT_STATUS" in
        self-reviewed|community-reviewed|independently-audited) ;;
        *) err "library/ entries require audit_status of self-reviewed or better (got '$AUDIT_STATUS')";;
    esac
fi

# --- companion docs ----------------------------------------------------------
[ -f "$CONTRACT_DIR/README.md" ] || err "README.md not found"
[ -f "$CONTRACT_DIR/AUDIT.md" ]  || err "AUDIT.md not found"

# --- pact source -------------------------------------------------------------
# Pure-interface entries (registry/kip/) may legitimately have no local .pact
# source when the interface is pre-deployed; everything else should ship source.
if [ -z "$PACT_FILE" ]; then
    if [[ "$CONTRACT_DIR" == *"/kip/"* ]]; then
        warn "no .pact file (interface entry — acceptable)"
    elif [ "$TREE" = "library" ]; then
        err "library/ entries must ship .pact source"
    else
        warn "no .pact file found"
    fi
else
    echo "  source: $PACT_FILE"
    if command -v pact >/dev/null 2>&1; then
        # Non-blocking: registry sources have external deps that need full
        # network context; a load failure here is informational.
        pact "$PACT_FILE" > /dev/null 2>&1 || warn "pact could not load $PACT_FILE standalone (may need dependencies)"
    fi
fi

# Library quality gate: co-located REPL test suite is mandatory.
if [ "$TREE" = "library" ]; then
    REPL_COUNT=$(find "$CONTRACT_DIR" -name "*.repl" | wc -l)
    if [ "$REPL_COUNT" -eq 0 ]; then
        err "library/ entries must include a co-located .repl test suite"
    else
        echo "  tests:  $REPL_COUNT .repl file(s)"
    fi
fi

if [ "$FAIL" -eq 1 ]; then
    echo "  RESULT: FAILED"
    exit 1
fi
echo "  RESULT: OK"
