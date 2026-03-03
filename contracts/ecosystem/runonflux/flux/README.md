# runonflux.flux — FLUX Token

| Field | Value |
|---|---|
| **Module** | `runonflux.flux` |
| **Project** | RunOnFlux Decentralized Cloud |
| **Category** | Utility Token |
| **Chains Deployed** | 20 / 20 (all mainnet01 chains) |
| **Blockchain Hash** | `zV-EMOLy3olqMfwO9Ck9…` |
| **Source** | [RunOnFlux/flux-kadena-contracts](https://github.com/RunOnFlux/flux-kadena-contracts) |

## Overview

**FLUX** is the native token of the [RunOnFlux](https://runonflux.io) network,
a decentralized cloud-computing platform providing Web3 infrastructure.
On Kadena, FLUX is bridged from its native networks (Ethereum, BSC, etc.)
and deployed as a standard `fungible-v2` token across all 20 chains.

FLUX on Kadena enables:

- **Cloud service payments**: Pay for RunOnFlux hosting and compute in KDA ecosystem.
- **Multi-chain interoperability**: FLUX exists natively on 10+ blockchains;
  the Kadena deployment enables KDA-native DeFi integrations.
- **Gas-free transfers**: `runonflux.flux-gas-station` provides subsidized transfers.

## Interfaces Implemented

| Interface | Purpose |
|---|---|
| `fungible-v2` | Standard fungible token (transfer, supply, balances) |

## Companion Modules

| Module | Purpose | Chains |
|---|---|---|
| `runonflux.flux-gas-station` | Subsidised gas payments in FLUX | 20/20 |
| `runonflux.fungible-util` | Utility helpers for FLUX | 20/20 |
| `runonflux.testflux` | Test/sandbox version of FLUX | 20/20 |

## Key Functions

```pact
;; Transfer FLUX
(runonflux.flux.transfer sender receiver amount)

;; Get balance
(runonflux.flux.get-balance account)

;; Total supply
(runonflux.flux.total-supply)
```

## References

- Website: https://runonflux.io
- GitHub: https://github.com/RunOnFlux/flux-kadena-contracts
- Explorer: https://explorer.chainweb-community.org (search `runonflux.flux`)
