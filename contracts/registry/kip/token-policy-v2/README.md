# kip.token-policy-v2

> **Pre-deployed · Interface · Audited**  
> The standard Marmalade v2 token policy interface (KIP standard). Every policy module in the Marmalade ecosystem must implement this interface to integrate with `marmalade-v2.policy-manager`.

---

## Overview

`kip.token-policy-v2` is the **Pact interface** that defines the seven enforcement hooks that Marmalade policy modules must implement. The `marmalade-v2.policy-manager` calls these hooks during token operations, enabling custom business logic for minting, burning, sales, and transfers.

This is the interface every community-built policy must implement to work with the Marmalade v2 framework.

---

## On-Chain Identity

| Property | Value |
|----------|-------|
| Module name | `kip.token-policy-v2` |
| Namespace | `kip` |
| Type | `interface` |
| Chain(s) | 0–19 (all chains) |
| Network | `mainnet01`, `testnet06` |
| Source | [`kda-community/chainweb-node`](https://github.com/kda-community/chainweb-node) |

---

## Required Schemas

```pact
(defschema token-info
  @doc "Token details passed to policy hooks"
  id:string
  supply:decimal
  precision:integer
  uri:string
  policies:[module{kip.token-policy-v2}])
```

---

## Required Functions (Interface Signatures)

All functions receive a `token:object{token-info}` as first argument, providing full token context.

| Function | Additional Args | Called During |
|----------|----------------|---------------|
| `enforce-mint` | `account:string amount:decimal` | `ledger.mint` |
| `enforce-burn` | `account:string amount:decimal` | `ledger.burn` |
| `enforce-offer` | `account:string amount:decimal timeout:integer sale-id:string` | `ledger.offer` (SALE step 0) |
| `enforce-buy` | `account:string seller:string buyer:string buyer-guard:guard amount:decimal sale-id:string` | `ledger.buy` (SALE step 1a) |
| `enforce-withdraw` | `account:string amount:decimal timeout:integer sale-id:string` | `ledger.withdraw` (SALE step 1b) |
| `enforce-transfer` | `sender:string receiver:string guard:guard amount:decimal` | `ledger.transfer` |
| `enforce-sale-pact` | `sale:object{marmalade-v2.ledger-v2.sale-info}` | sale defpact validation |

---

## Dependency Graph

```
kip.token-policy-v2  (interface — no dependencies)
 └── called by  marmalade-v2.policy-manager  (enforce-* delegation)
 └── implemented by  marmalade-v2.guard-policy-v1
 └── implemented by  marmalade-v2.royalty-policy-v1
 └── implemented by  marmalade-v2.non-fungible-policy-v1
 └── implemented by  marmalade-v2.collection-policy-v1
 └── implemented by  marmalade-v2.non-updatable-uri-policy-v1
 └── implemented by  <any custom policy module>
```

---

## Full Policy Implementation Template

```pact
(module my-policy GOVERNANCE
  (implements kip.token-policy-v2)

  (defun enforce-mint:bool
    ( token:object{kip.token-policy-v2.token-info}
      account:string
      amount:decimal )
    @doc "Called before mint — enforce minting rules"
    ;; Add your mint logic here; return true to allow, enforce false to reject
    true)

  (defun enforce-burn:bool
    ( token:object{kip.token-policy-v2.token-info}
      account:string
      amount:decimal )
    @doc "Called before burn — enforce burn rules"
    true)

  (defun enforce-offer:bool
    ( token:object{kip.token-policy-v2.token-info}
      account:string
      amount:decimal
      timeout:integer
      sale-id:string )
    @doc "Called when a sale offer is created"
    true)

  (defun enforce-buy:bool
    ( token:object{kip.token-policy-v2.token-info}
      account:string      ;; seller
      seller:string
      buyer:string
      buyer-guard:guard
      amount:decimal
      sale-id:string )
    @doc "Called when a sale is completed (buyer pays)"
    true)

  (defun enforce-withdraw:bool
    ( token:object{kip.token-policy-v2.token-info}
      account:string
      amount:decimal
      timeout:integer
      sale-id:string )
    @doc "Called when a sale offer is withdrawn"
    true)

  (defun enforce-transfer:bool
    ( token:object{kip.token-policy-v2.token-info}
      sender:string
      receiver:string
      guard:guard
      amount:decimal )
    @doc "Called before token transfer"
    true)

  (defun enforce-sale-pact:bool (sale:string)
    @doc "Called to validate the sale pact ID"
    true)
)
```

---

## Related Modules

- [`marmalade-v2.policy-manager`](../../marmalade/policy-manager/README.md) — orchestrates all policy calls
- [`marmalade-v2.ledger`](../../marmalade/ledger/README.md) — the ledger that triggers policy enforcement
- [`kip.token-manifest`](../token-manifest/README.md) — companion interface for token metadata
