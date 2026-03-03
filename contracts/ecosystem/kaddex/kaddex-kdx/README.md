# kaddex.kdx — KDX Governance Token

| Field | Value |
|---|---|
| **Module** | `kaddex.kdx` |
| **Project** | Ecko DEX (formerly Kaddex) |
| **Category** | Governance & Utility Token |
| **Chains Deployed** | 20 / 20 (all mainnet01 chains) |
| **Blockchain Hash** | `UbAj2RYupaT-x4vrBv8VcSzY9VN7EV…` |
| **Source** | [kaddex-org/swap-v2](https://github.com/kaddex-org/swap-v2) |

## Overview

KDX is the native governance and utility token of **Ecko DEX** (ecko.finance),
Kadena's largest decentralized exchange by trading volume and total value locked.
It is deployed on all 20 Kadena chains and enables:

- **Governance**: KDX holders vote on fee parameters, liquidity incentives, and
  protocol upgrades via `kaddex.dao`.
- **Staking (sKDX)**: KDX can be staked to receive protocol fee revenue, earning
  `kaddex.skdx` staked tokens.
- **Gas station**: KDX holders can pay for gas-fee-free transactions.
- **Cross-chain transfers**: Native SPV-based cross-chain transfers via `fungible-xchain-v1`.

## Interfaces Implemented

| Interface | Purpose |
|---|---|
| `fungible-v2` | Standard fungible token (transfer, mint, burn) |
| `fungible-xchain-v1` | Cross-chain transfer via SPV proof |
| `kaddex.supply-control-v1` | Supply control for mint/burn governance |
| `kaddex.special-accounts-v1` | Protected special-purpose accounts |

## Key Functions

```pact
;; Standard transfer
(kaddex.kdx.transfer sender receiver amount)

;; Cross-chain initiation (returns a defpact ID)
(kaddex.kdx.transfer-crosschain sender receiver receiver-guard target-chain amount)

;; Get total supply
(kaddex.kdx.total-supply)

;; Get balance
(kaddex.kdx.get-balance account)
```

## Deployment

KDX is deployed identically on chains 0–19. Cross-chain transfers use Kadena's
SPV proof mechanism — initiate on source chain, complete on target chain.

```pact
;; Initiate cross-chain transfer from chain 1 → chain 2
(kaddex.kdx.transfer-crosschain
  "k:sender-pubkey"
  "k:receiver-pubkey"
  (keyset-ref-guard "user-keyset")
  "2"           ;; target-chain
  10.0)         ;; amount
```

## Related Modules

- [`kaddex.supply-control-v1`](../kaddex-supply-control/) — supply control interface
- [`kaddex.special-accounts-v1`](../kaddex-special-accounts/) — special accounts
- `kaddex.staking` (chain 1 only) — KDX staking for protocol fees
- `kaddex.skdx` (chain 1 only) — Staked KDX token

## References

- Website: https://ecko.finance
- Explorer: https://explorer.chainweb-community.org (search `kaddex.kdx`)
- Source: https://github.com/kaddex-org/swap-v2
