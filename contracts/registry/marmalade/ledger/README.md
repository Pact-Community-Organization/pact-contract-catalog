# marmalade-v2.ledger

> **Pre-deployed · Module · Audited**  
> The Marmalade v2 NFT ledger for KDA-CE. Central registry for all non-fungible and poly-fungible token operations: minting, burning, transferring, and offering/buying tokens in sales.

---

## Overview

`marmalade-v2.ledger` is the core ledger module of KDA-CE's Marmalade v2 NFT framework. It manages token definitions, account balances, and the SALE defpact (offer → buy/withdraw). Policies are attached per token and enforced by `marmalade-v2.policy-manager`.

Marmalade v2 significantly upgrades v1:
- Multiple policies per token (composable policy slots)
- `policy-manager` decouples policy logic from ledger logic
- Improved sale pact with conventional auction and Dutch auction support
- On-chain token manifest via `kip.token-manifest`

---

## On-Chain Identity

| Property | Value |
|----------|-------|
| Module name | `marmalade-v2.ledger` |
| Namespace | `marmalade-v2` |
| Chain(s) | 0–19 (all chains) |
| Network | `mainnet01`, `testnet06` |
| Source | [`kda-community/chainweb-node`](https://github.com/kda-community/chainweb-node) |

---

## Implements

| Interface | Purpose |
|-----------|---------|
| `marmalade-v2.ledger-v2` | Extended ledger interface (v2); defines token-id, create-token, create-account, mint, burn, transfer signatures |
| `kip.poly-fungible-v3` | Poly-fungible standard; unifies fungible + NFT under a single composable interface |

---

## Capabilities

| Capability | Type | Description |
|-----------|------|-------------|
| `GOVERNANCE` | admin | Module upgrade control |
| `TOKEN (id)` | | Internal: asserts token existence |
| `ACCOUNT_GUARD (id account)` | | Internal: verifies account guard ownership |
| `ROTATE (id account)` | | Rotate account guard for a token |
| `TRANSFER (id sender receiver amount)` | `@managed` | Authorise token transfer; enforced by policies |
| `XTRANSFER (id sender receiver target-chain amount)` | `@managed` | Cross-chain token transfer authorisation |
| `SUPPLY (id)` | | Read token total supply |
| `RECONCILE (id amount debit-account credit-account)` | `@event` | Emitted on every balance change |
| `ACCOUNT_GUARD (id account guard)` | `@event` | Emitted on guard update |
| `UPDATE_SUPPLY (id supply)` | `@event` | Emitted when total supply changes |
| `MINT (id account amount)` | `@event` | Emitted on mint |
| `BURN (id account amount)` | `@event` | Emitted on burn |
| `DEBIT (id account amount)` | | Internal: debit token balance |
| `CREDIT (id account amount)` | | Internal: credit token balance |

---

## Key Functions

| Function | Description |
|----------|-------------|
| `create-token-id` | Generate a deterministic token ID from manifest + policies |
| `create-token` | Register a new token with manifest and policy list |
| `create-account` | Create a token account for a given token |
| `mint` | Mint tokens to an account (policy-guarded) |
| `burn` | Burn tokens from an account (policy-guarded) |
| `transfer` | Transfer tokens between accounts (policy-guarded) |
| `transfer-create` | Transfer + create receiver account if needed |
| `get-balance` | Return token balance of an account |
| `details` | Return account details for a token |
| `total-supply` | Return total supply of a token |
| `get-token-info` | Return token record (id, supply, precision, uri, policies) |
| `get-policy-info` | Return the policy configuration for a token |
| `ledger-guard` | Return the ledger's capability guard (used by policy-manager) |
| `account-guard` | Return the guard for a token account |

### SALE defpact (offer → buy / withdraw)

```
SALE
 ├── step 0  offer(id, seller, amount, timeout)   — locks tokens, calls enforce-offer on all policies
 ├── step 1a buy(id, seller, buyer, buyer-guard, amount, sale-id)  — transfers + calls enforce-buy
 └── step 1b withdraw(id, seller, amount, sale-id)  — returns tokens + calls enforce-withdraw
```

---

## Dependency Graph

```
marmalade-v2.ledger
 ├── implements  marmalade-v2.ledger-v2    (interface — on-chain only)
 ├── implements  kip.poly-fungible-v3      (interface — on-chain only)
 │     └── uses  kip.token-policy-v2      (interface — policy enforcement hooks)
 │     └── uses  kip.token-manifest       (manifest standard — token metadata)
 └── delegates policy enforcement to  marmalade-v2.policy-manager
```

---

## Usage Example

```pact
;; Create a token manifest
(let* ((uri (kip.token-manifest.uri "image/png" "https://example.com/img.png"))
       (datum (kip.token-manifest.create-datum (uri "text/plain" "My NFT") {}))
       (manifest (kip.token-manifest.create-manifest uri [datum])))

  ;; Create token (assign policies)
  (marmalade-v2.ledger.create-token
    (marmalade-v2.ledger.create-token-id manifest "free")
    1                                    ;; precision (0 = NFT, 1+ = semi-fungible)
    manifest
    marmalade-v2.guard-policy-v1         ;; policy module reference
    )

  ;; Mint
  (marmalade-v2.ledger.mint token-id "alice" (read-keyset "alice-ks") 1.0)
)
```

---

## Related Modules

- [`marmalade-v2.policy-manager`](../policy-manager/README.md) — policy orchestration for this ledger
- [`kip.token-policy-v2`](../../kip/token-policy-v2/README.md) — interface each policy module implements
- [`kip.token-manifest`](../../kip/token-manifest/README.md) — on-chain token metadata standard
- [`coin`](../../core/coin/README.md) — KDA payments in SALE defpact
