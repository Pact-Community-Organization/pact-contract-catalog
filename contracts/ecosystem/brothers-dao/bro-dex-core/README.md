# BRO DEX Core (BRO/KDA Market)

**Module:** `n_f6aa9328b19b8bf7e788603bd669dcf549e07575.bro-dex-core-BRO-KDA-M`
**Project:** Brothers DAO | **Category:** DEX (Order Book) | **Layer:** ecosystem
**Chain:** 2 | **Network:** mainnet01
**License:** BUSL-1.1 — https://github.com/brothers-DAO/bro-dex/blob/main/LICENSE

> Ranked **#7** by function call frequency in the 90-day KDA-CE mainnet census (2 calls).

## Overview

BRO DEX Core is an on-chain limit order book for the BRO/KDA trading pair. Unlike AMM
designs, it stores individual limit orders in a balanced binary tree sorted by price,
enabling price-time-priority matching. Core operations (MAKE-ORDER, TAKE-ORDER) emit
`@event` capabilities for off-chain indexing.

## Key Capabilities

| Capability      | @event | Description                              |
|-----------------|--------|------------------------------------------|
| `MAKE-ORDER`    | ✅     | Creates a new limit order                |
| `TAKE-ORDER`    | ✅     | Fills an existing limit order            |
| `INSERT-ORDER`  | —      | Internal tree insert                     |
| `REMOVE-ORDER`  | —      | Internal tree remove                     |
| `POINTER-SWAP`  | —      | Internal tree rebalancing                |
| `UPDATE-TREE`   | —      | Internal balanced-tree update            |

## Dependencies

- `free.util-lists` — list manipulation utilities
- `free.util-math` — math helpers (for price/amount calculations)
- `n_582fed11af00dc626812cd7890bb88e72067f28c.bro` — BRO token
- `coin` — KDA coin (quote/settlement asset)

## Source

Open source: https://github.com/brothers-DAO/bro-dex (BUSL-1.1)
