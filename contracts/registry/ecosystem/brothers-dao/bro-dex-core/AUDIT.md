# Security Assessment — BRO DEX Core (BRO/KDA Market)

**Module:** `n_f6aa9328b19b8bf7e788603bd669dcf549e07575.bro-dex-core-BRO-KDA-M`
**License:** BUSL-1.1
**Status:** community-reviewed | **Date:** 2026-03 | **Reviewer:** Pact Community Org

## Capability Model

| Capability      | Guard                     | Managed | Event | Risk  |
|-----------------|---------------------------|---------|-------|-------|
| `GOVERNANCE`    | bro-dex-admin keyset (ns) | No      | No    | Low   |
| `MAKE-ORDER`    | Composes sub-caps         | No      | ✅    | Low   |
| `TAKE-ORDER`    | Composes sub-caps         | No      | ✅    | Low   |
| `INSERT-ORDER`  | Internal                  | No      | No    | Low   |
| `REMOVE-ORDER`  | Internal                  | No      | No    | Low   |
| `POINTER-SWAP`  | Internal                  | No      | No    | Low   |
| `UPDATE-TREE`   | Internal                  | No      | No    | Low   |

Primary user-facing capabilities emit `@event` — good for off-chain indexing.

## Risk Profile

| Area              | Finding                                              | Risk   |
|-------------------|------------------------------------------------------|--------|
| Governance        | Hash-namespace admin keyset — well isolated          | Low    |
| Order book        | Binary tree order book — complex but auditable       | Medium |
| License           | BUSL-1.1 — source-available, not fully open source   | Low    |
| Event coverage    | MAKE/TAKE emit @event — indexable                    | Low    |
| Tree integrity    | Balanced tree rebalancing — verify edge cases        | Medium |

## Recommendations

1. The order book binary tree implementation is the most complex part. A deep audit
   of `INSERT-ORDER`/`REMOVE-ORDER`/`POINTER-SWAP` tree invariants is recommended.
2. BUSL-1.1 license restricts production deployment in competing DEX products.
   Verify license compliance before forking.
3. No critical capability issues found.
