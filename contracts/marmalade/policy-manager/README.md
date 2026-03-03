# marmalade-v2.policy-manager

> **Pre-deployed · Module · Audited**  
> The Marmalade v2 policy orchestration layer. Routes token mint/burn/transfer/sale events to all registered policies for a token, enforcing the full policy stack in a single callsite.

---

## Overview

`marmalade-v2.policy-manager` is the middleware between `marmalade-v2.ledger` and individual policy modules. When the ledger executes a token operation (mint, burn, transfer, offer, buy, withdraw), it calls the policy-manager, which in turn calls every policy module attached to that token.

This design:
- Keeps the ledger lightweight and policy-agnostic
- Allows tokens to compose multiple policies (e.g., royalty + whitelist + non-fungible)
- Makes policy enforcement deterministic and auditable — all policies always run

---

## On-Chain Identity

| Property | Value |
|----------|-------|
| Module name | `marmalade-v2.policy-manager` |
| Namespace | `marmalade-v2` |
| Chain(s) | 0–19 (all chains) |
| Network | `mainnet01`, `testnet06` |
| Source | [`kda-community/chainweb-node`](https://github.com/kda-community/chainweb-node) |

---

## Capabilities

| Capability | Type | Description |
|-----------|------|-------------|
| `GOVERNANCE` | admin | Controls module upgrades |
| `CALL_LEDGER` | | Internal: only ledger can call this module's enforce-* functions |

---

## Key Functions

All `enforce-*` functions are called by `marmalade-v2.ledger` during the corresponding token operation. They iterate over the token's policy list and call each policy module's corresponding `enforce-*` function.

| Function | Called During | Description |
|----------|---------------|-------------|
| `enforce-mint` | `ledger.mint` | Calls each policy's `enforce-mint` |
| `enforce-burn` | `ledger.burn` | Calls each policy's `enforce-burn` |
| `enforce-offer` | `ledger.offer` (SALE step 0) | Calls each policy's `enforce-offer` |
| `enforce-buy` | `ledger.buy` (SALE step 1a) | Calls each policy's `enforce-buy` |
| `enforce-withdraw` | `ledger.withdraw` (SALE step 1b) | Calls each policy's `enforce-withdraw` |
| `enforce-transfer` | `ledger.transfer` | Calls each policy's `enforce-transfer` |

---

## Dependency Graph

```
marmalade-v2.policy-manager
 ├── called by  marmalade-v2.ledger  (enforce-* delegation)
 ├── calls each  <policy module>  (implements kip.token-policy-v2)
 │     └── marmalade-v2.guard-policy-v1
 │     └── marmalade-v2.royalty-policy-v1
 │     └── marmalade-v2.non-fungible-policy-v1
 │     └── marmalade-v2.collection-policy-v1
 │     └── marmalade-v2.non-updatable-uri-policy-v1
 │     └── <any custom policy implementing kip.token-policy-v2>
 └── uses  kip.token-policy-v2  (interface that all policies must implement)
```

---

## Built-in Policy Modules (Pre-deployed)

| Module | Policy Type | Description |
|--------|-------------|-------------|
| `marmalade-v2.guard-policy-v1` | Guard | Simple keyset/guard-based mint/transfer control |
| `marmalade-v2.royalty-policy-v1` | Royalty | Enforces creator royalty payment on `buy` |
| `marmalade-v2.non-fungible-policy-v1` | Non-fungible | Enforces precision=0 and supply=1 (true NFTs) |
| `marmalade-v2.collection-policy-v1` | Collection | Groups tokens into collections with a max supply |
| `marmalade-v2.non-updatable-uri-policy-v1` | URI lock | Prevents URI updates after creation |
| `marmalade-sale.conventional-auction` | Sale | Highest-bid auction sale mechanism |
| `marmalade-sale.dutch-auction` | Sale | Descending-price Dutch auction sale mechanism |

---

## Creating a Custom Policy

To write a custom Marmalade policy, implement `kip.token-policy-v2`:

```pact
(module my-whitelist-policy GOVERNANCE
  (implements kip.token-policy-v2)

  (defun enforce-mint:bool (token:object{kip.token-policy-v2.token-info}
                             account:string amount:decimal)
    @doc "Only allow whitelisted accounts to mint"
    (with-read whitelist-table account { "approved": approved }
      (enforce approved "Account not whitelisted for mint")))

  ;; ... implement all 7 enforce-* functions
)
```

Then reference it when creating a token:
```pact
(marmalade-v2.ledger.create-token token-id precision manifest
  my-whitelist-policy)
```

---

## Related Modules

- [`marmalade-v2.ledger`](../ledger/README.md) — the ledger that calls this manager
- [`kip.token-policy-v2`](../../kip/token-policy-v2/README.md) — interface that all policies implement
- [`kip.token-manifest`](../../kip/token-manifest/README.md) — token metadata standard
- [`coin`](../../core/coin/README.md) — used by royalty-policy-v1 for KDA royalty payments
