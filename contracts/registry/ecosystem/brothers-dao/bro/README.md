# BRO Token

**Module:** `n_582fed11af00dc626812cd7890bb88e72067f28c.bro`
**Project:** Brothers DAO | **Category:** Governance Token | **Layer:** ecosystem
**Chain:** primary chain 2 (cross-chain all) | **Network:** mainnet01

## Overview

BRO is the governance token for Brothers DAO, a community-run DEX ecosystem on KDA-CE.
Implements `fungible-v2` and `fungible-xchain-v1` for full cross-chain portability.
Initial supply is minted on `SUPPLY-CHAIN = "2"`. Multiple blessed hashes in the module
indicate an active cross-chain transfer history.

## Token Details

- **Precision:** 12 decimal places (`MINIMUM_PRECISION`)
- **Supply chain:** 2
- **Interfaces:** `fungible-v2`, `fungible-xchain-v1`

## Dependencies

- `free.util-fungible` — shared fungible token utilities
- `free.util-chain-data` — cross-chain data helpers

## On-Chain Provenance

Source fetched via `(describe-module "n_582fed11af00dc626812cd7890bb88e72067f28c.bro")` on chain 1, mainnet01.
