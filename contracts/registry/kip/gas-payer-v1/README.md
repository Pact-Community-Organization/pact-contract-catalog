# gas-payer-v1

> **Pre-deployed · Interface · Audited**  
> The gas station interface for KDA-CE. Implement this interface to build contracts that pay transaction gas fees on behalf of users (sponsored transactions / meta transactions).

---

## Overview

`gas-payer-v1` is a **Pact interface** that defines the protocol for gas-paying contracts ("gas stations"). A gas station is a module that implements `gas-payer-v1` and is referenced in transaction metadata as the signer for the `GAS` capability.

Gas stations enable:
- **Sponsored transactions** — users can transact without holding any KDA
- **Application-funded UX** — dApps pay gas for their users
- **Conditional gas payment** — pay gas only for specific transaction types

---

## On-Chain Identity

| Property | Value |
|----------|-------|
| Module name | `gas-payer-v1` |
| Type | `interface` |
| Chain(s) | 0–19 (all chains) |
| Network | `mainnet01`, `testnet06` |
| Source | [`kda-community/chainweb-node`](https://github.com/kda-community/chainweb-node) |

---

## Capabilities (Interface Signatures)

| Capability | Type | Description |
|-----------|------|-------------|
| `GAS_PAYER (user limit price)` | | Grants the `GAS` capability for this transaction; implementor enforces conditions |

Parameters:
- `user:string` — the transaction sender account
- `limit:integer` — gas limit from transaction metadata
- `price:decimal` — gas price from transaction metadata

---

## Required Functions (Interface Signatures)

| Function | Signature | Description |
|----------|-----------|-------------|
| `create-gas-payer-guard` | `() → guard` | Returns the guard that must be used as the gas station account guard |

---

## Dependency Graph

```
gas-payer-v1  (interface — no dependencies)
 └── implemented by  <any gas station module>
      └── uses  coin  (to hold KDA balance for paying gas)
```

---

## Implementing a Gas Station

```pact
(module my-gas-station GOVERNANCE
  (implements gas-payer-v1)

  (defcap GAS_PAYER:bool
    ( user:string
      limit:integer
      price:decimal )
    @doc "Allow gas payment for all users (simple gas station)"
    (enforce (> limit 0) "Gas limit must be positive")
    (enforce (> price 0.0) "Gas price must be positive")
    (compose-capability (coin.GAS))
    (compose-capability (ALLOW_GAS)))

  (defcap ALLOW_GAS () true)

  (defun create-gas-payer-guard:guard ()
    @doc "Guard for the gas station KDA account"
    (create-capability-guard (ALLOW_GAS)))
)

;; Fund the gas station account (one time)
(coin.create-account "my-gas-station-account"
  (my-gas-station.create-gas-payer-guard))
(coin.transfer "admin" "my-gas-station-account" 100.0)
```

---

## Usage in Transaction Metadata

```yaml
# In kda-tool tx template — reference gas station in signers
signers:
  - public: ""
    caps:
      - name: "my-gas-station.GAS_PAYER"
        args: ["{{ sender }}", 2000, 1.0e-8]
      - name: "coin.GAS"
        args: []
```

---

## Related Modules

- [`coin`](../../core/coin/README.md) — the `GAS` capability that gas stations compose into
- [`fungible-v2`](../fungible-v2/README.md) — standard fungible interface for managing the gas station KDA balance
