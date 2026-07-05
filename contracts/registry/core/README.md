# core/ — Core KDA-CE Chain Infrastructure

This layer contains **pre-deployed production modules** that form the foundation of every chain in the KDA-CE network (chains 0–19). These modules are authored by Kadena LLC / KDA Community Edition and are present at genesis — you cannot redeploy them, only integrate with them.

---

## Contents

| Module | Directory | Description |
|--------|-----------|-------------|
| `coin` | [coin/](coin/README.md) | Native KDA token — every tx, every chain |
| `ns` | [ns/](ns/README.md) | Namespace registry — required for all namespaced deployments |
| `util.fungible-util` | [fungible-util/](fungible-util/README.md) | Validation helpers for fungible token implementors |

---

## Dependency graph — this layer

```
coin
 ├── implements  kip/fungible-v2
 └── implements  kip/fungible-xchain-v1

util.fungible-util
 └── implements  kip.account-protocols-v1  (not catalogued separately — small interface)

ns
 └── (no interface deps — called by Pact runtime define-namespace builtin)
```

---

## Integration notes

- You never **deploy** these modules. They already exist on every chain.
- Call them directly: `(coin.transfer "alice" "bob" 10.0)`
- `coin.create-account` / `coin.transfer-create` are the two most common entry points for new users.
- `ns` is called implicitly by `(namespace "free")` — you rarely call it directly.
- Use `util.fungible-util.enforce-valid-transfer` / `enforce-reserved` in your own fungible module for correctness and safety.
