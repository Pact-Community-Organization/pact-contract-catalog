#!/usr/bin/env bash
set -euo pipefail

# Fetch and dump Pact module code for tokens listed in Mercatus tokens.yaml
# Requirements: curl, pact CLI, and either jq or python for JSON parsing

TOKENS_URL="https://raw.githubusercontent.com/Mercatus-Kadena/kadena_tokens/main/tokens.yaml"
NETWORK_ID="mainnet01"
# Kadena mainnet has chains 0..19
CHAINS=($(seq 0 19))
OUT_DIR="$(dirname "$0")/../module_dump"
TMP_DIR="$(dirname "$0")/../module_dump/tmp"

mkdir -p "$OUT_DIR" "$TMP_DIR"

echo "Fetching tokens.yaml..." >&2
TOKENS_CONTENT=$(curl -sSL "$TOKENS_URL")

# Extract module FQNs (namespace.module) from YAML top-level keys
# Keys look like: two-space indent + identifier ending with colon
mapfile -t MODULES < <(echo "$TOKENS_CONTENT" | awk '/^  [a-zA-Z0-9_\.-]+:/{gsub(":$","",$1); print $1}' | sed 's/^  //')

if [[ ${#MODULES[@]} -eq 0 ]]; then
  echo "No modules found in tokens.yaml" >&2
  exit 1
fi

# Helper: build a local command JSON via pact -a from a YAML here-doc
build_local_cmd() {
  local code="$1" chainId="$2"
  local yaml="$TMP_DIR/cmd_${chainId}.yaml"
  cat > "$yaml" <<YAML
code: |
  $code
data: {}
keyPairs: []
networkId: "$NETWORK_ID"
meta:
  creationTime: 0
  ttl: 600
  chainId: "$chainId"
  gasPrice: 1e-9
  gasLimit: 2000
  sender: "free.local-query"
YAML
  # pact -a emits a /send-compatible envelope with cmds[].cmd (stringified JSON)
  # Extract the inner cmd JSON to use directly with /local
  if command -v jq >/dev/null 2>&1; then
    pact -a "$yaml" | jq -r '.cmds[0].cmd'
  else
    pact -a "$yaml" | python3 - <<'PY'
import sys, json
try:
    j=json.load(sys.stdin)
    print(j['cmds'][0]['cmd'])
except Exception:
    pass
PY
  fi
}

# Helper: extract .result.data.code from local response using jq or python
extract_code() {
  if command -v jq >/dev/null 2>&1; then
    jq -r '.result.data.code // empty'
  else
    python3 - <<'PY'
import sys, json
try:
    j=json.load(sys.stdin)
    d=j.get('result',{}).get('data',{})
    c=d.get('code','')
    if c:
        print(c)
except Exception as e:
    pass
PY
  fi
}

# Allow overriding host via env `API_HOST`; default to community endpoint
API_HOST="${API_HOST:-api.chainweb-community.org}"
API_BASE="https://${API_HOST}/chainweb/0.0/${NETWORK_ID}"

echo "Found ${#MODULES[@]} modules. Querying describe-module..." >&2

for fqn in "${MODULES[@]}"; do
  # Use the full FQN as provided by tokens.yaml; may be single-name like "coin"
  fqn_label="$fqn"
  out_file="$OUT_DIR/${fqn_label}.pact"

  # Always attempt fresh fetch to ensure full content

  ok=0
    for chain in "${CHAINS[@]}"; do
    # Ask node for full module description; we'll construct a proper /local payload envelope
    code="(describe-module \"${fqn_label}\")"
    inner_cmd=$(build_local_cmd "$code" "$chain")
    inner_cmd_file="$TMP_DIR/inner_${fqn_label}_chain${chain}.json"
    printf '%s' "$inner_cmd" > "$inner_cmd_file"
    if [[ ! -s "$inner_cmd_file" ]]; then
      echo "[miss] $fqn chain $chain (cmd build failed)" >&2
      continue
    fi
  # Build the {cmd,hash,sigs:[]} envelope and ensure meta has sensible values
    envelope=$(python3 - <<PY
import json, sys, base64, hashlib
cmd_str = open("$inner_cmd_file").read().strip()
obj = json.loads(cmd_str)
# ensure meta exists
obj.setdefault('meta',{})
obj['meta'].update({
    'creationTime': 0,
    'ttl': 600,
    'gasLimit': 20000,
    'chainId': str(${chain}),
    'gasPrice': 1e-9,
    'sender': 'free.local-query'
})
# compact JSON string for hashing
cmd_compact = json.dumps(obj, separators=(',',':'))
h = hashlib.blake2b(cmd_compact.encode('utf-8'), digest_size=32).digest()
reqKey = base64.urlsafe_b64encode(h).decode('utf-8').rstrip('=')
env = {'cmd': cmd_compact, 'hash': reqKey, 'sigs': []}
print(json.dumps(env))
PY
    )
    resp=$(echo "$envelope" | curl -s -H "Content-Type: application/json" -d @- "$API_BASE/chain/${chain}/pact/api/v1/local" || true)
    # Extract module code strictly from .result.data.code (avoid grabbing markdown snippets)
    module_code=$(echo "$resp" | extract_code)
    if [[ -n "$module_code" ]]; then
      # Write full multi-line code to file
      printf '%s\n' "$module_code" > "$out_file"
      echo "[ok] $fqn chain $chain -> $out_file" >&2
      ok=1
      break
    else
      # Dump raw response for diagnostics on miss
      printf '%s\n' "$resp" > "$TMP_DIR/${fqn_label}.chain${chain}.resp.json"
      echo "[miss] $fqn chain $chain" >&2
    fi
  done
  if [[ "$ok" -ne 1 ]]; then
    echo "[fail] Could not fetch module code for $fqn on chains ${CHAINS[*]}" >&2
  fi
done

echo "Done. Outputs in: $OUT_DIR" >&2
