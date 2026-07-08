# ns

> **Pre-deployed · Module · Audited**  
> The Kadena namespace registry. Every module or keyset deployed under a named namespace (e.g., `free.*`, `user.*`, `kip.*`) passes through `ns` for governance and validation.

---

## Overview

`ns` is the on-chain **namespace registry** for KDA-CE. It governs who can create and rotate namespaces, enforces namespace naming rules, and provides the policy hooks that control namespace access.

All modules and keysets in named namespaces (`free`, `user`, `kip`, `util`, …) are registered through `ns`. Without this module, namespaced contracts cannot be deployed.

`ns` is the most-used infrastructure module for **contract deployment** — every named-namespace deployment calls it.

---

## On-Chain Identity

| Property | Value |
|----------|-------|
| Module name | `ns` |
| Chain(s) | 0–19 (all chains) |
| Network | `mainnet01`, `testnet06` |
| Source | [`kda-community/chainweb-node`](https://github.com/kda-community/chainweb-node) |

---

## Capabilities

| Capability | Description |
|-----------|-------------|
| `GOVERNANCE` | Admin governance; controls upgrades to the `ns` module itself |

---

## Key Functions

| Function | Description |
|----------|-------------|
| `validate-name` | Validates a proposed namespace name against the naming policy |
| `ns-create-principal-namespace` | Creates a namespace derived from a public key |

The `ns` module is called by the Pact runtime's `(define-namespace ...)` builtin, which delegates to `ns` for namespace policy enforcement.

---

## Namespace Policy

KDA-CE has two namespace tiers:

| Tier | Examples | Access Requirement |
|------|----------|--------------------|
| **Root** | `kip`, `marmalade-v2`, `coin`, `util` | Governance keyset only (Kadena / KDA-CE admin) |
| **User** | `free`, `user`, `n_<principal>` | Any funded account via `ns.validate-name` |

To deploy to the `free` namespace:
```pact
(define-namespace "free"
  (read-keyset "ns-admin-ks")
  (read-keyset "ns-user-ks"))
```

To create a principal namespace (derived from a public key):
```pact
(ns.create-principal-namespace (read-keyset "my-ks"))
```

---

## Dependency Graph

```
ns  (module — no interface dependencies)
 └── called by  Pact runtime  (define-namespace builtin)
 └── required by  all namespaced module deployments
```

---

## Namespace Naming Rules

- Lowercase alphanumeric characters and hyphens
- Must start with a letter
- Principal namespaces begin with `n_` followed by the hash of the keyset
- No reserved names (e.g., `coin`, `ns`, `pact`, `kadena` are reserved)

---

## Usage Example

```pact
;; Deploy a module to the free namespace
(namespace "free")

(module my-token GOVERNANCE
  (implements fungible-v2)
  ;; ...
)

;; Create a principal namespace for your key
(ns.create-principal-namespace (read-keyset "owner-ks"))
;; result: "n_<hash>"
(namespace "n_<hash>")
```

---

## Related Modules

- [`coin`](../coin/README.md) — used to fund the deployer account needed for namespace-gated deployments
- [`fungible-v2`](../fungible-v2/README.md) — commonly implemented by modules deployed in `free.*`
