# Chips Oracle

**Module:** `n_e98a056e3e14203e6ec18fada427334b21b667d8.chips-oracle`
**Project:** Chips Protocol | **Category:** Oracle | **Layer:** ecosystem
**Chain:** 1 | **Network:** mainnet01

> Ranked **#6** by function call frequency in the 90-day KDA-CE mainnet census (4 calls).

## Overview

Chips Oracle is the price-feed dependency for the Chips DeFi protocol. It stores
decimal prices for NFT types and upgrade items keyed by item type, and maintains a
price history log keyed by `(coin, count)`. Write access is restricted to the protocol
admin and a designated Discord integration account.

## Schemas

| Schema             | Fields                      | Purpose                     |
|--------------------|-----------------------------|-----------------------------|
| `price-schema`     | `price:decimal`             | Current item price          |
| `counts-schema`    | `count:integer`             | Sequential write counter    |
| `price-history-schema` | (key = coin + count)   | Immutable price history log |

## Dependencies

- `coin` — KDA coin (for fee handling in the Discord integration path)

## On-Chain Provenance

Source fetched via `(describe-module "...")` on chain 1, mainnet01.
