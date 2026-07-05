# arkade.token — ARKADE Gaming Token

| Field | Value |
|---|---|
| **Module** | `arkade.token` |
| **Project** | Arkade |
| **Category** | Gaming Utility Token |
| **Chains Deployed** | 20 / 20 |
| **Blockchain Hash** | `noElac-ldWYHMLDINfZR6busoYrJ1K…` |

## Overview

**ARKADE** is the utility token for the Arkade gaming platform on Kadena — a
blockchain gaming ecosystem offering play-to-earn tournaments, in-game purchases,
and NFT marketplaces. Deployed on all 20 Kadena chains with cross-chain transfer
support via `fungible-xchain-v1`.

## Interfaces Implemented

| Interface | Purpose |
|---|---|
| `fungible-v2` | Standard fungible token |
| `fungible-xchain-v1` | Cross-chain transfers |

## Companion Modules

| Module | Purpose | Chains |
|---|---|---|
| `arkade.arkade-staking` | Token staking / yield | 1/20 |
| `arkade.airdrop` | Community airdrop distribution | 1/20 |
| `arkade.brawler-bears` | NFT collection | 1/20 |

## Usage

```pact
;; Transfer ARKADE
(arkade.token.transfer sender receiver amount)

;; Cross-chain
(arkade.token.transfer-crosschain sender receiver guard target-chain amount)
```

## References
- Website: https://arkade.fun
