# util.fungible-util

> **Pre-deployed · Module · Audited**  
> Validation utility helpers for fungible token modules on KDA-CE. Provides reusable enforcement functions for amount, precision, account format, and principal account reservation — used internally by `coin` and recommended for all custom fungible token implementations.

---

## Overview

`util.fungible-util` is a utility module that centralises the common validation logic needed by any `fungible-v2`-compliant token. Rather than each token reimplementing these checks, they can import and call these battle-tested helpers.

It implements `kip.account-protocols-v1`, which adds the `enforce-reserved` function for principal account guard enforcement.

---

## On-Chain Identity

| Property | Value |
|----------|-------|
| Module name | `util.fungible-util` |
| Namespace | `util` |
| Chain(s) | 0–19 (all chains) |
| Network | `mainnet01`, `testnet06` |
| Source | [`kda-community/chainweb-node`](https://github.com/kda-community/chainweb-node) |

---

## Implements

| Interface | Purpose |
|-----------|---------|
| `kip.account-protocols-v1` | Defines `enforce-reserved` for principal account guard enforcement |

---

## Capabilities

| Capability | Description |
|-----------|-------------|
| `GOVERNANCE` | Module upgrade control |

---

## Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `enforce-valid-amount` | `(precision:integer amount:decimal) → bool` | Enforce amount is positive and matches token precision |
| `enforce-valid-account` | `(account:string) → bool` | Enforce account name is non-empty and within length limits |
| `enforce-precision` | `(precision:integer amount:decimal) → bool` | Enforce that `amount` has no more decimal places than `precision` |
| `enforce-valid-transfer` | `(sender:string receiver:string precision:integer amount:decimal) → bool` | Combined validation: sender ≠ receiver, valid amount, valid account names |
| `check-reserved` | `(account:string) → string` | Return the reserved protocol prefix of an account (e.g., `"k:"`, `"r:"`, `""` if none) |
| `enforce-reserved` | `(account:string guard:guard) → bool` | For principal accounts (`k:`, `r:`, etc.), enforce the guard matches the principal |

---

## Dependency Graph

```
util.fungible-util
 ├── implements  kip.account-protocols-v1   (interface: enforce-reserved)
 └── used by  coin                          (calls enforce-valid-amount, check-reserved, enforce-reserved)
 └── recommended for  any fungible-v2 implementor
```

---

## Usage Example

```pact
(module my-token GOVERNANCE
  (implements fungible-v2)

  (defun transfer:string (sender:string receiver:string amount:decimal)
    @doc "Transfer tokens with standard validation"
    ;; Use util.fungible-util for validated transfer setup
    (util.fungible-util.enforce-valid-transfer sender receiver 12 amount)
    (with-capability (TRANSFER sender receiver amount)
      (debit sender amount)
      (credit receiver amount)))

  (defun create-account:string (account:string guard:guard)
    @doc "Create account, enforcing principal guard rules"
    (util.fungible-util.enforce-valid-account account)
    (util.fungible-util.enforce-reserved account guard)
    (insert accounts-table account { "balance": 0.0, "guard": guard }))
)
```

---

## Principal Account Formats

The `check-reserved` / `enforce-reserved` functions handle these prefixes:

| Prefix | Protocol | Guard Requirement |
|--------|----------|-------------------|
| `k:` | Single-key principal | Guard must match the key |
| `r:` | Multi-key principal | Guard must match the keyset |
| `w:` | WebAuthn principal | Guard must match the WebAuthn key |
| (none) | Vanity account | No guard constraint from reserved |

---

## Related Modules

- [`coin`](../coin/README.md) — uses these utilities internally
- [`fungible-v2`](../../kip/fungible-v2/README.md) — interface that fungible tokens implement; util helpers support compliant implementations
- [`fungible-xchain-v1`](../../kip/fungible-xchain-v1/README.md) — cross-chain transfers also benefit from these validations
