#!/usr/bin/env python3
"""
census_by_calls.py — Rank Pact modules by function call frequency on KDA-CE mainnet01.

Methodology
-----------
The /txs/events endpoint is NOT available on KDA-CE (returns 404).
This script instead uses direct block-payload scanning, which is MORE comprehensive
than events-only — it captures both state-changing and read-only calls.

For each sampled block:
  1. GET /chain/{id}/header?limit=1&minheight={h}  → payloadHash
  2. GET /chain/{id}/payload/{payloadHash}/outputs  → raw transactions
  3. base64-decode each transaction → parse exec.code JSON string
  4. Regex-extract all qualified Pact function calls: (namespace.module.function ...)
  5. Module FQN = everything before the last dot-segment (the function name)

Sampling strategy:
  - 90 days ≈ 259,200 blocks/chain (2 blocks/min × 60 × 24 × 90)
  - Default stride=1000 → ~259 samples/chain × 20 chains = ~5,180 payload fetches
  - ThreadPoolExecutor runs N chains in parallel; per-chain payload fetches run
    in an inner worker pool for throughput.

Usage
-----
  python3 scripts/census_by_calls.py [options]

Options
-------
  --stride N      Sample every Nth block (default: 1000)
  --chains N      Number of chains to scan (default: 20)
  --workers N     Concurrency for payload fetches (default: 16)
  --top N         How many non-cataloged modules to show (default: 20)
  --out FILE      Write full JSON results to FILE
  --no-filter     Include already-cataloged modules in ranking

Network: mainnet01 @ https://api.chainweb-community.org
"""

import argparse
import base64
import json
import re
import sys
import time
import urllib.error
import urllib.request
from collections import Counter
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

BASE = "https://api.chainweb-community.org/chainweb/0.0/mainnet01"
ALL_CHAINS = list(range(20))

# Approximate block count for 90 days on a single chain
# Kadena: ~1 block every 30s per chain = 2/min × 60min × 24h × 90d
BLOCKS_PER_CHAIN_90D = 259_200

# Modules / interfaces already present in the catalog (excluded from results by default)
ALREADY_CATALOGED: set[str] = {
    # kip — standard interfaces
    "fungible-v2",
    "fungible-xchain-v1",
    "gas-payer-v1",
    "poly-fungible-v1",
    # core
    "coin",
    # marmalade base
    "marmalade-v2.ledger",
    "marmalade-v2.policy-manager",
    "marmalade-v2.guard-policy-v1",
    "marmalade-v2.non-fungible-policy-v1",
    "marmalade-v2.royalty-policy-v1",
    "marmalade-sale.dutch-auction",
    "marmalade-sale.conventional-auction",
    # ecosystem (from previous PR — top-10 by deployment breadth)
    "kaddex.kdx",
    "kaddex.exchange",
    "runonflux.flux",
    "lago.kwBTC",
    "lago.kwUSDC",
    "lago.USD2",
    "kadena.spirekey",
    "mok.token",
    "arkade.token",
    "arkade.exchange",
}

# Regex: match qualified Pact calls: (namespace.module.function  or  (module.function
# Pact identifier chars: [a-zA-Z0-9_\-\/\*\+\<\>=\?] — we cover the common subset
_ID = r"[a-zA-Z][a-zA-Z0-9_\-]*"
CALL_RE = re.compile(
    r"\((" + _ID + r"(?:\." + _ID + r")+)" + r"[\s\n(]"
)

# Noise: built-in Pact forms that look like module calls but aren't
BUILTIN_PREFIXES = {
    "pact",       # pact.version etc. — built-in
}


# ---------------------------------------------------------------------------
# HTTP helpers
# ---------------------------------------------------------------------------

def _fetch(url: str, retries: int = 3, timeout: int = 12,
           extra_headers: dict | None = None) -> dict | list:
    headers = {"User-Agent": "pact-catalog-census/1.0"}
    if extra_headers:
        headers.update(extra_headers)
    req = urllib.request.Request(url, headers=headers)
    last_err = None
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return json.loads(r.read())
        except (urllib.error.URLError, TimeoutError, ConnectionResetError) as e:
            last_err = e
            if attempt < retries - 1:
                time.sleep(0.8 * (attempt + 1))
    raise RuntimeError(f"Failed after {retries} attempts: {url} — {last_err}")


# ---------------------------------------------------------------------------
# Pact call extraction
# ---------------------------------------------------------------------------

def decode_exec_code(tx_entry: list) -> str | None:
    """
    Decode a raw transaction [cmd_b64, output_b64] list and return exec.code.
    Returns None for cont (defpact continuation) transactions or decode errors.
    """
    try:
        cmd_b64 = tx_entry[0]
        # The outer layer is a base64url-encoded JSON {hash, sigs, cmd}
        pad = 4 - len(cmd_b64) % 4
        outer = json.loads(
            base64.urlsafe_b64decode(cmd_b64 + ("=" * pad if pad < 4 else ""))
        )
        # .cmd is a JSON-stringified inner payload
        cmd_str = outer.get("cmd", "")
        if not isinstance(cmd_str, str) or not cmd_str:
            return None
        inner = json.loads(cmd_str)
        payload = inner.get("payload", {})
        if "exec" in payload:
            return payload["exec"].get("code", "")
        # cont transactions: reference a defpact step — not a direct module call
        return None
    except Exception:
        return None


def extract_module_calls(code: str) -> list[str]:
    """
    Parse Pact exec code and return list of module FQNs being called.

    Pact call syntax: (module.function args...)  or  (ns.module.function args...)
    Module FQN = everything before the final dot-segment (which is the function name).
    """
    modules = []
    for m in CALL_RE.finditer(code):
        qualified = m.group(1)          # e.g. "coin.transfer" or "kaddex.exchange.swap"
        parts = qualified.split(".")
        if len(parts) < 2:
            continue
        module_fqn = ".".join(parts[:-1])   # drop the function name (last segment)
        # Skip pure builtins
        if module_fqn in BUILTIN_PREFIXES:
            continue
        modules.append(module_fqn)
    return modules


# ---------------------------------------------------------------------------
# Chain scanning
# ---------------------------------------------------------------------------

def fetch_payload_hashes(chain_id: int, sample_heights: list[int]) -> list[tuple[int, str]]:
    """
    For each sample height, fetch one block header and return (actual_height, payloadHash).
    Uses limit=1&minheight=h to get the block at or just after `h`.
    """
    results = []
    hdr = {"Accept": "application/json;blockheader-encoding=object"}
    for h in sample_heights:
        try:
            url = f"{BASE}/chain/{chain_id}/header?limit=1&minheight={h}"
            data = _fetch(url, extra_headers=hdr)
            items = data.get("items", [])
            if items:
                results.append((items[0]["height"], items[0]["payloadHash"]))
        except Exception:
            pass
    return results


def fetch_block_calls(chain_id: int, payload_hash: str) -> Counter:
    """Fetch one block's transactions and count module calls."""
    counter: Counter = Counter()
    try:
        url = f"{BASE}/chain/{chain_id}/payload/{payload_hash}/outputs"
        data = _fetch(url)
        for tx in data.get("transactions", []):
            code = decode_exec_code(tx)
            if code:
                for mod in extract_module_calls(code):
                    counter[mod] += 1
    except Exception:
        pass
    return counter


def scan_chain(chain_id: int, current_height: int, stride: int,
               inner_workers: int = 8) -> tuple[int, int, Counter]:
    """
    Scan one chain for 90 days of block history.

    Returns (chain_id, n_blocks_sampled, Counter_of_module_calls).
    """
    start_height = max(0, current_height - BLOCKS_PER_CHAIN_90D)
    sample_heights = list(range(start_height, current_height, stride))

    # Fetch all payload hashes for this chain's samples
    pairs = fetch_payload_hashes(chain_id, sample_heights)

    # Fetch payloads in parallel
    global_counter: Counter = Counter()
    with ThreadPoolExecutor(max_workers=inner_workers) as pool:
        futs = {pool.submit(fetch_block_calls, chain_id, ph): ph for _, ph in pairs}
        for fut in as_completed(futs):
            try:
                global_counter.update(fut.result())
            except Exception:
                pass

    return chain_id, len(pairs), global_counter


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Rank Pact modules by call frequency on KDA-CE mainnet01 (90 days)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("--stride", type=int, default=1000,
                        help="Sample every N-th block (default: 1000)")
    parser.add_argument("--chains", type=int, default=20,
                        help="Number of chains to scan (default: 20)")
    parser.add_argument("--workers", type=int, default=4,
                        help="Parallel outer chain workers (default: 4)")
    parser.add_argument("--inner-workers", type=int, default=8,
                        help="Parallel payload fetchers per chain (default: 8)")
    parser.add_argument("--top", type=int, default=20,
                        help="Show top N non-cataloged modules (default: 20)")
    parser.add_argument("--out", type=str, default=None,
                        help="Write full JSON results to FILE")
    parser.add_argument("--no-filter", action="store_true",
                        help="Include already-cataloged modules in ranking output")
    args = parser.parse_args()

    ts_start = datetime.now(timezone.utc)
    print(f"[{ts_start.isoformat()}]  KDA-CE mainnet01 — module call census")
    print(f"  stride={args.stride} | chains={args.chains} | "
          f"outer_workers={args.workers} | inner_workers={args.inner_workers}")
    print()

    # ------------------------------------------------------------------
    # 1. Get current heights
    # ------------------------------------------------------------------
    print("► Fetching current chain heights from /cut …", flush=True)
    try:
        cut = _fetch(f"{BASE}/cut")
        heights = {int(k): v["height"] for k, v in cut["hashes"].items()}
    except Exception as e:
        print(f"  ERROR: could not fetch /cut — {e}", file=sys.stderr)
        sys.exit(1)

    chains_to_scan = sorted(heights.keys())[: args.chains]
    samples_per_chain = BLOCKS_PER_CHAIN_90D // args.stride
    total_samples = samples_per_chain * len(chains_to_scan)

    print(f"  Chain heights: {min(heights[c] for c in chains_to_scan):,} – "
          f"{max(heights[c] for c in chains_to_scan):,}")
    print(f"  Scan window: ~90 days ({BLOCKS_PER_CHAIN_90D:,} blocks/chain)")
    print(f"  Block samples: ~{samples_per_chain} per chain × {len(chains_to_scan)} chains "
          f"= ~{total_samples:,} total")
    print()

    # ------------------------------------------------------------------
    # 2. Scan chains
    # ------------------------------------------------------------------
    print("► Scanning chains …", flush=True)
    global_counter: Counter = Counter()
    total_blocks_scanned = 0
    wall_start = time.monotonic()

    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        futs = {
            pool.submit(scan_chain, c, heights[c], args.stride, args.inner_workers): c
            for c in chains_to_scan
        }
        for fut in as_completed(futs):
            chain_id = futs[fut]
            try:
                cid, n_blocks, chain_cnt = fut.result()
                global_counter.update(chain_cnt)
                total_blocks_scanned += n_blocks
                elapsed = time.monotonic() - wall_start
                calls_this_chain = sum(chain_cnt.values())
                print(
                    f"  chain {cid:2d}: {n_blocks:4d} blocks | "
                    f"{calls_this_chain:6,} calls | "
                    f"unique mods so far: {len(global_counter):4d} | "
                    f"elapsed {elapsed:5.0f}s",
                    flush=True,
                )
            except Exception as e:
                print(f"  chain {chain_id}: ERROR — {e}", flush=True)

    elapsed_total = time.monotonic() - wall_start
    ts_end = datetime.now(timezone.utc)
    print()
    print(f"► Scan complete in {elapsed_total:.0f}s")
    print(f"  Blocks sampled: {total_blocks_scanned:,}")
    print(f"  Total calls seen: {sum(global_counter.values()):,}")
    print(f"  Unique module FQNs detected: {len(global_counter)}")
    print()

    # ------------------------------------------------------------------
    # 3. Rank and display
    # ------------------------------------------------------------------
    all_ranked = global_counter.most_common()

    # Full ranking (top 40 for context)
    width = max((len(m) for m, _ in all_ranked[:40]), default=20) + 2
    print(f"{'='*72}")
    print(f"  FULL RANKING — top 40 modules (all, including already cataloged)")
    print(f"{'='*72}")
    print(f"  {'Rank':<5} {'Module FQN':<{width}} {'Calls':>10}  Status")
    print(f"  {'-'*5} {'-'*width} {'-'*10}  ------")
    for rank, (mod, cnt) in enumerate(all_ranked[:40], 1):
        tag = "[cataloged]" if mod in ALREADY_CATALOGED else ""
        print(f"  {rank:<5} {mod:<{width}} {cnt:>10,}  {tag}")
    print()

    # New modules only
    new_modules = [(m, c) for m, c in all_ranked if m not in ALREADY_CATALOGED]
    print(f"{'='*72}")
    print(f"  TOP {args.top} — NEW modules not yet in catalog (candidates to add)")
    print(f"{'='*72}")
    print(f"  {'Rank':<5} {'Module FQN':<{width}} {'Calls':>10}")
    print(f"  {'-'*5} {'-'*width} {'-'*10}")
    for rank, (mod, cnt) in enumerate(new_modules[: args.top], 1):
        print(f"  {rank:<5} {mod:<{width}} {cnt:>10,}")
    print()

    # ------------------------------------------------------------------
    # 4. JSON output
    # ------------------------------------------------------------------
    if args.out:
        output = {
            "generated_at": ts_end.isoformat(),
            "methodology": "block-payload-sampling",
            "note": (
                "Events endpoint (/txs/events) is not available on KDA-CE; "
                "this script uses direct exec.code payload parsing which covers "
                "both state-changing and read-only Pact calls."
            ),
            "parameters": {
                "network": "mainnet01",
                "chains_scanned": len(chains_to_scan),
                "stride": args.stride,
                "coverage_blocks_per_chain": BLOCKS_PER_CHAIN_90D,
            },
            "stats": {
                "elapsed_seconds": round(elapsed_total),
                "blocks_sampled": total_blocks_scanned,
                "total_calls": sum(global_counter.values()),
                "unique_modules": len(global_counter),
            },
            "all_modules_ranked": [
                {
                    "rank": i,
                    "module": m,
                    "calls": c,
                    "in_catalog": m in ALREADY_CATALOGED,
                }
                for i, (m, c) in enumerate(all_ranked, 1)
            ],
            "new_candidates_top": [
                {"rank": i, "module": m, "calls": c}
                for i, (m, c) in enumerate(new_modules[: args.top], 1)
            ],
        }
        with open(args.out, "w") as f:
            json.dump(output, f, indent=2)
        print(f"► Results written to {args.out}")
    else:
        print("  (use --out results.json to save full ranked list)")

    print()
    print("Next steps:")
    print("  1. Review the 'NEW candidates' list above.")
    print("  2. Run: pact-contract-catalog/scripts/describe_tokens.sh to fetch source.")
    print("  3. Create catalog entries under contracts/ecosystem/ or contracts/community/.")
    print()


if __name__ == "__main__":
    main()
