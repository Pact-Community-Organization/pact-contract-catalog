# CyberFly Token (CFLY)

**Module:** `free.cyberfly_token`
**Project:** CyberFly | **Category:** Governance Token | **Layer:** community
**Chain:** 1 | **Network:** mainnet01

> Ranked **#4** by function call frequency in the 90-day KDA-CE mainnet census (4 calls).

## Overview

CFLY is the native token of the CyberFly DePIN network. It implements the standard
`fungible-v2` and `fungible-xchain-v1` interfaces, enabling cross-chain transfers
across all 20 KDA-CE chains. The module uses shared utility libraries from the
`free` namespace for precision enforcement and chain-data access.

## Multiple Blessed Hashes

The module blesses 4 predecessor hashes, indicating an active cross-chain transfer
history with upgrades. This means existing cross-chain transfers created with older
module versions can still be completed.

## Dependencies

- `free.util-fungible` — shared precision and account validation utilities
- `free.util-chain-data` — chain metadata access

## Governance

Controlled by `GOVERNANCE` — enforces keyset guard protecting module upgrades.
