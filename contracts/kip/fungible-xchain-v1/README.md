# fungible-xchain-v1

> **Pre-deployed · Interface · Audited**  
> The cross-chain transfer extension interface for fungible tokens on KDA-CE. Extends `fungible-v2` to support SPV-verified transfers across Kadena's 20 parallel chains.

---

## Overview

`fungible-xchain-v1` is a **Pact interface** that defines the cross-chain transfer protocol for fungible tokens. It is implemented alongside `fungible-v2` by the `coin` module.

Cross-chain transfers on Kadena/KDA-CE are two-step `defpact` continuations:
1. **Step 1 (source chain):** `transfer-crosschain` — locks funds and emits an SPV-verifiable event.
2. **Step 2 (target chain):** Continuation carrying SPV proof — mints/credits funds on the target chain and emits `TRANSFER_XCHAIN_RECD`.

> **KDA-CE note:** SPV proof expiry has been disabled since chainweb-node v3.1 — cross-chain continuations can be completed at any point after initiation.

---

## On-Chain Identity

| Property | Value |
|----------|-------|
| Module name | `fungible-xchain-v1` |
| Type | `interface` |
| Chain(s) | 0–19 (all chains) |
| Network | `mainnet01`, `testnet06` |
| Source | [`kda-community/chainweb-node`](https://github.com/kda-community/chainweb-node) |

---

## Known Implementors

| Module | Description |
|--------|-------------|
| `coin` | Native KDA token — canonical implementor |

---

## Capabilities (Interface Signatures)

| Capability | Type | Description |
|-----------|------|-------------|
| `TRANSFER_XCHAIN (sender receiver amount target-chain)` | `@managed` | Authorise cross-chain debit on source chain |
| `TRANSFER_XCHAIN_RECD (sender receiver amount source-chain)` | `@event` | Emitted on target chain when cross-chain transfer is completed |

### TRANSFER_XCHAIN-mgr

Implementors must provide `TRANSFER_XCHAIN-mgr` as the managed capability handler:

```pact
(defun TRANSFER_XCHAIN-mgr:decimal (managed:decimal requested:decimal)
  @doc "Enforce exact managed amount for cross-chain transfer"
  (enforce (= managed requested) "Transfer amount must match")
  0.0)
```

---

## Dependency Graph

```
fungible-xchain-v1  (interface — no dependencies)
 └── implemented by  coin  (alongside fungible-v2)
```

---

## Cross-Chain Transfer Flow

```
Source Chain                          Target Chain
─────────────                         ────────────
1. coin.transfer-crosschain(...)
   → defpact step 1
   → TRANSFER_XCHAIN cap consumed
   → funds locked / burned
   → SPV event emitted
                                      2. (continue ...) + SPV proof
                                         → defpact step 2
                                         → TRANSFER_XCHAIN_RECD emitted
                                         → funds credited to receiver
```

---

## Usage Example

```pact
;; Step 1 — on source chain (e.g., chain 0)
(coin.transfer-crosschain
  "alice"          ;; sender
  "bob"            ;; receiver
  (read-keyset "bob-ks")
  "5"              ;; target-chain-id
  50.0)            ;; amount

;; Step 2 — automatically submitted to chain 5 with SPV proof by relay or wallet
```

---

## Related Modules

- [`fungible-v2`](../fungible-v2/README.md) — base fungible interface; both are co-implemented by `coin`
- [`coin`](../../core/coin/README.md) — canonical implementor of both fungible interfaces
