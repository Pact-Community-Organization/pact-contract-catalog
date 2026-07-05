# fungible-v2

> **Pre-deployed · Interface · Audited**  
> The canonical Pact interface for fungible tokens on KDA-CE. Every fungible token module — including `coin` — must implement this interface.

---

## Overview

`fungible-v2` is a **Pact interface** (not a module). It defines the required function and capability signatures that all standard fungible tokens on KDA-CE must satisfy. Any contract calling `(implement fungible-v2)` is guaranteed to expose the full set of typed functions declared here.

This interface is the foundation of the KDA-CE token ecosystem. It enables composable DeFi tooling: any code that calls `fungible-v2` functions works uniformly across all compliant tokens.

---

## On-Chain Identity

| Property | Value |
|----------|-------|
| Module name | `fungible-v2` |
| Type | `interface` |
| Chain(s) | 0–19 (all chains) |
| Network | `mainnet01`, `testnet06` |
| Source | [`kda-community/chainweb-node`](https://github.com/kda-community/chainweb-node) |

---

## Known Implementors

| Module | Description |
|--------|-------------|
| `coin` | Native KDA token — the canonical reference implementation |
| Any custom fungible token | Any KIP-compliant token module should implement `fungible-v2` |

---

## Capabilities (Interface Signatures)

| Capability | Type | Description |
|-----------|------|-------------|
| `TRANSFER (sender receiver amount)` | `@managed` | Managed transfer authorization; implementor provides `TRANSFER-mgr` |

---

## Required Functions (Interface Signatures)

| Function | Signature | Description |
|----------|-----------|-------------|
| `transfer` | `(sender:string receiver:string amount:decimal) → string` | Transfer between existing accounts |
| `transfer-create` | `(sender:string receiver:string receiver-guard:guard amount:decimal) → string` | Transfer, creating receiver account if absent |
| `transfer-crosschain` | `(sender:string receiver:string receiver-guard:guard target-chain:string amount:decimal) → string` | Initiate cross-chain transfer (`defpact`) |
| `get-balance` | `(account:string) → decimal` | Return account balance |
| `details` | `(account:string) → object{account-details}` | Return account record (account, balance, guard) |
| `precision` | `() → integer` | Number of decimal places for this token |
| `enforce-unit` | `(amount:decimal) → bool` | Enforce minimum precision unit |
| `create-account` | `(account:string guard:guard) → string` | Create a new token account |
| `rotate` | `(account:string new-guard:guard) → string` | Rotate the guard (key rotation) |

---

## Schema

```pact
(defschema account-details
  @doc "Token account details"
  account:string
  balance:decimal
  guard:guard)
```

---

## Dependency Graph

```
fungible-v2  (interface — no dependencies)
 └── implemented by  coin
 └── implemented by  <any KIP-compliant fungible token>
```

---

## Extending This Interface

To implement `fungible-v2` in your token module:

```pact
(module my-token GOVERNANCE
  (implements fungible-v2)

  ;; Required: implement all 9 functions + TRANSFER cap + TRANSFER-mgr
  (defcap TRANSFER:bool (sender:string receiver:string amount:decimal)
    @managed amount TRANSFER-mgr
    ...)

  (defun TRANSFER-mgr:decimal (managed:decimal requested:decimal)
    ...)

  (defun transfer:string (sender:string receiver:string amount:decimal)
    ...)
  ;; ... etc.
)
```

---

## Related Modules

- [`coin`](../../core/coin/README.md) — flagship implementor of `fungible-v2`
- [`fungible-xchain-v1`](../fungible-xchain-v1/README.md) — companion cross-chain interface
- [`util.fungible-util`](../../core/fungible-util/README.md) — validation helpers for fungible implementors
