# kadena.spirekey — WebAuthn Account & Gas Payer

| Field | Value |
|---|---|
| **Module** | `kadena.spirekey` |
| **Project** | Kadena Inc. |
| **Category** | Authentication / Gas Payer |
| **Chains Deployed** | 20 / 20 |
| **Blockchain Hash** | `wZIoPnkgwaXYenTfUTYP…` |
| **Source** | [kadena-io/spirekey](https://github.com/kadena-io/spirekey) |

## Overview

**SpireKey** is Kadena's passkey-based account system. Users authenticate with
biometrics (Face ID, Touch ID, Windows Hello) instead of seed phrases. The
on-chain module implements `gas-payer-v1`, allowing dApps to sponsor gas fees
for their users — a key enabler for frictionless onboarding.

## Key Capabilities

| Capability | Purpose |
|---|---|
| `GAS_PAYER` | Sponsors gas for user transactions |
| `ROTATE` | Rotate WebAuthn credential (passkey) |
| `TRANSFER` | Transfer value from SpireKey account |

## Interfaces Implemented

| Interface | Purpose |
|---|---|
| `gas-payer-v1` | Allows the account to pay gas on behalf of users |

## Integration Example

```pact
;; Use a SpireKey account as gas payer
(env-data {"spirekey-account": "c:..."})
(kadena.spirekey.GAS_PAYER "user-account" (read-integer "limit") 1.0)
```

## How It Works

1. User registers a passkey (WebAuthn credential) via the SpireKey app or SDK.
2. The passkey's public key is stored on-chain as the account guard.
3. When signing transactions, the user approves with biometrics instead of a private key.
4. The `GAS_PAYER` capability lets the dApp sponsor gas, so users can transact without KDA.

## References

- Website: https://spirekey.kadena.io
- GitHub: https://github.com/kadena-io/spirekey
- Docs: https://kda-chain.org/docs
