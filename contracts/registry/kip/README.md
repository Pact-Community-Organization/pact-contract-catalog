# kip/ — KIP Interface Standards

This layer contains **pure Pact interfaces** defined by the Kadena Improvement Proposal (KIP) process. These modules contain no executable logic — they declare typed function and capability signatures that other modules must implement.

---

## Why interfaces first?

Pact interfaces are the foundation of composability on KDA-CE. Any code that accepts a `module{fungible-v2}` argument works with **every** compliant token automatically. Interfaces define the contract between callers and implementors without coupling them.

---

## Contents

| Interface | Module Name | Used By |
|-----------|-------------|---------|
| [fungible-v2](fungible-v2/README.md) | `fungible-v2` | `coin`, any KDA-CE fungible token |
| [fungible-xchain-v1](fungible-xchain-v1/README.md) | `fungible-xchain-v1` | `coin` (cross-chain transfer protocol) |
| [gas-payer-v1](gas-payer-v1/README.md) | `gas-payer-v1` | any gas station module |

---

## Dependency graph — this layer

```
fungible-v2          (no deps)
fungible-xchain-v1   (no deps — co-implements with fungible-v2)
gas-payer-v1         (no deps)
```

---

## Writing a KIP-compliant module

To implement `fungible-v2` in your token:

```pact
(module my-token GOVERNANCE
  (implements fungible-v2)
  (implements fungible-xchain-v1)
  ;; ... must satisfy all typed signatures from both interfaces
)
```

