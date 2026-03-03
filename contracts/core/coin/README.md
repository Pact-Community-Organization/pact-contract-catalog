# coin

> **Pre-deployed · Core · Audited**  
> The native KDA token contract. Pre-deployed on every chain (0–19) of KDA-CE mainnet01 and testnet06. You do not deploy this contract — you integrate with it.

---

## Overview

`coin` is the foundational fungible token module for the Kadena Community Edition blockchain. It manages all KDA balances, powers the gas station protocol, and provides the reference implementation of both `fungible-v2` and `fungible-xchain-v1`.

Every transaction on every chain references `coin` for gas payment. It is the **most-used module** on KDA-CE mainnet by an enormous margin.

---

## On-Chain Identity

| Property | Value |
|----------|-------|
| Module name | `coin` |
| Chain(s) | 0–19 (all chains) |
| Network | `mainnet01`, `testnet06` |
| Governance keyset | `coin-contract-admin` (Kadena / KDA Community) |
| Source | [`kda-community/chainweb-node`](https://github.com/kda-community/chainweb-node) |

---

## Implements

| Interface | Purpose |
|-----------|---------|
| `fungible-v2` | Standard fungible token: transfer, create-account, get-balance, rotate, precision |
| `fungible-xchain-v1` | Cross-chain transfer protocol (SPVT continuation) |

---

## Capabilities

| Capability | Type | Description |
|-----------|------|-------------|
| `GOVERNANCE` | admin | Controls upgrades; keyset-guarded |
| `GAS` | | Grants permission for gas debit during transaction execution |
| `COINBASE` | | Mints block mining reward to miner account |
| `GENESIS` | | Bootstrap-only: funds initial allocations |
| `REMEDIATE` | | Emergency balance remediation (governance only) |
| `DEBIT (sender amount)` | | Internal: debit sender account |
| `CREDIT (receiver amount)` | | Internal: credit receiver account |
| `ROTATE (account)` | | Change account guard (keyset rotation) |
| `TRANSFER (sender receiver amount)` | `@managed` | Authorises fungible transfer; single use |
| `TRANSFER_XCHAIN (sender receiver amount target-chain)` | `@managed` | Authorises cross-chain transfer initiation |
| `TRANSFER_XCHAIN_RECD (sender receiver amount source-chain)` | `@event` | Emitted on cross-chain receipt |
| `RELEASE_ALLOCATION (account amount)` | `@event` | Emitted on vesting schedule release |

---

## Public Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `create-account` | `(account:string guard:guard) → string` | Create a new KDA account |
| `get-balance` | `(account:string) → decimal` | Return account balance |
| `details` | `(account:string) → object{fungible-v2.account-details}` | Return account + guard |
| `rotate` | `(account:string new-guard:guard) → string` | Rotate account guard |
| `precision` | `() → integer` | Returns `12` (12 decimal places) |
| `transfer` | `(sender:string receiver:string amount:decimal) → string` | Transfer KDA same-chain |
| `transfer-create` | `(sender:string receiver:string receiver-guard:guard amount:decimal) → string` | Transfer + create receiver account if needed |
| `transfer-crosschain` | `(sender:string receiver:string receiver-guard:guard target-chain:string amount:decimal) → string` | Initiate cross-chain transfer (step 1 of 2) |
| `buy-gas` | `(sender:string total:decimal) → string` | Gas station: debit gas budget at tx start |
| `redeem-gas` | `(miner:string miner-guard:guard sender:string total:decimal) → string` | Gas station: pay miner, refund remainder |
| `coinbase` | `(account:string account-guard:guard amount:decimal) → string` | Mining reward mint (chain internal) |
| `enforce-unit` | `(amount:decimal) → bool` | Enforce minimum precision |
| `validate-account` | `(account:string) → string` | Validate account string format |

---

## Dependency Graph

```
coin
 ├── implements  fungible-v2            (interface — defines transfer ABI)
 └── implements  fungible-xchain-v1    (interface — defines cross-chain ABI)
```

---

## Usage Example

```pact
;; Transfer KDA between accounts
(coin.transfer "alice" "bob" 10.0)

;; Create a new account
(coin.create-account "carol" (read-keyset "carol-ks"))

;; Check balance
(coin.get-balance "alice")

;; Cross-chain transfer (step 1 — initiates defpact)
(coin.transfer-crosschain "alice" "bob" (read-keyset "bob-ks") "2" 5.0)
```

---

## Integration Notes

- All accounts on KDA-CE use the `coin` module — there is no separate "wrap" step.
- Gas payment is automatic: the runtime calls `buy-gas` / `redeem-gas` internally.
- Use `transfer-create` (not `transfer`) when the receiver account may not yet exist.
- Cross-chain transfers are two-step `defpact` continuations: initiate on source chain, complete on target chain using an SPV proof.
- `TRANSFER` is `@managed` — the capability manager enforces one-time, exact-amount authorization.

---

## Related Modules

- [`fungible-v2`](../../kip/fungible-v2/README.md) — interface that `coin` implements
- [`fungible-xchain-v1`](../../kip/fungible-xchain-v1/README.md) — cross-chain interface that `coin` implements
- [`gas-payer-v1`](../../kip/gas-payer-v1/README.md) — gas station interface for subsidized transactions
- [`util.fungible-util`](../fungible-util/README.md) — helper utilities used by fungible modules
