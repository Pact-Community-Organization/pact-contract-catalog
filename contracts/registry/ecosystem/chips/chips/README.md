# Chips Protocol

**Module:** `n_e98a056e3e14203e6ec18fada427334b21b667d8.chips`
**Project:** Chips Protocol | **Category:** DeFi Protocol | **Layer:** ecosystem
**Chain:** 1 | **Network:** mainnet01

> Ranked **#3** by function call frequency in the 90-day KDA-CE mainnet census (9 calls).

## Overview

Chips is a DeFi and gaming protocol. The main module (1,549 lines) provides:
- **Token locking & staking** with configurable durations and early-withdraw penalties
- **Multi-coin reward distribution** (kWATT and external coin rewards)
- **Order book mechanics** for CHIPS token trading
- **NFT integration** via chips-oracle price feeds
- **Presale integration** via chips-presale dependency

## Dependencies

- `fungible-v2` — standard fungible token interface
- `coin` — KDA gas coin
- `chips-oracle` (same namespace) — NFT/upgrade price feed
- `chips-presale` — initial distribution module

## Key Constants

| Constant                   | Description                               |
|----------------------------|-------------------------------------------|
| `CHIPS_BANK`               | Protocol treasury account                 |
| `CHIPS_LOCKED_WALLET`      | Staking vault account                     |
| `EARLY_WITHDRAW_PENALTY`   | kWATT penalty on early withdrawal         |
| `MINIMUM_LOCK_DURATION`    | Minimum lock period (configurable)        |
| `SUPPORTED_COINS`          | List of coins eligible for rewards        |

## On-Chain Provenance

Source fetched via `(describe-module "...")` on chain 1, mainnet01.
