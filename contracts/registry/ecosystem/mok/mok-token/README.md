# mok.token — MOK Governance Token

| Field | Value |
|---|---|
| **Module** | `mok.token` |
| **Project** | Momentum |
| **Category** | Governance Token |
| **Chains Deployed** | 20 / 20 |
| **Blockchain Hash** | `C5-h2VEfldax1-BsXfR5…` |

## Overview

**MOK** is the governance token of the Momentum project, a DeFi protocol on
Kadena. It follows the standard `fungible-v2` and `fungible-xchain-v1` dual
interface pattern, enabling both in-chain transfers and native SPV-based
cross-chain transfers across all 20 Kadena chains.

## Interfaces Implemented

| Interface | Purpose |
|---|---|
| `fungible-v2` | Standard fungible token |
| `fungible-xchain-v1` | Cross-chain transfers via SPV |

## Companion Modules

| Module | Purpose |
|---|---|
| `mok.staking` | MOK staking for governance/yield |
| `mok.gas-station` | Subsidised gas in MOK |
| `mok.utils` | Utility helpers |

## Usage

```pact
;; Transfer MOK
(mok.token.transfer sender receiver amount)

;; Cross-chain transfer
(mok.token.transfer-crosschain sender receiver guard target-chain amount)
```

## References
- Hypercent launchpad: https://hypercent.io
