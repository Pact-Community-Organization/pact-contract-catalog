# lago.USD2 — Namespace Governance Shell

| Field | Value |
|---|---|
| **Module** | `lago.USD2` |
| **Project** | Lago Protocol |
| **Category** | Governance Shell / Namespace Reservation |
| **Chains Deployed** | 20 / 20 |
| **Blockchain Hash** | `gx8dwzIfbuiqHtZ9km0W0bp1p7zAPYmrxfBmO7696S0` |
| **Source Size** | 193 characters |
| **Interfaces Implemented** | none |

## On-Chain Reality

> **Important:** `lago.USD2` is a **governance shell** with no stablecoin logic.
> It contains only a `GOVERNANCE` capability enforcing the `lago-ns-user` keyset.

Full on-chain source:

```pact
(module USD2 GOVERNANCE

    (defcap GOVERNANCE ()
        @doc " Give the admin full access to call and upgrade the module. "
        (enforce-keyset 'lago-ns-user)
    )
)
```

Chain 1 additionally hosts `lago.USD2-wrapper` — also a governance shell (`MINTER-ADMIN` cap,
hash `5xX6H-mYx4N2RvXskbM4HxMkMg6mHMY9cIsm7PgLDEY`, 111 chars).

## Lago Namespace Architecture

See [lago/kwBTC/README.md](../kwBTC/README.md) for the full namespace architecture diagram.
All six lago modules are governance shells with no deployed token functionality.

## Files in This Directory

| File | Module | Description |
|---|---|---|
| `USD2.pact` | `lago.USD2` | On-chain source (governance shell) |
| `fungible-burn-mint.pact` | `lago.fungible-burn-mint` | On-chain source (interface) |
| `USD2-wrapper.pact` | `lago.USD2-wrapper` | On-chain source from chain 1 (wrapper admin shell) |
| `metadata.yaml` | — | Catalog metadata |
| `AUDIT.md` | — | Security notes |

## References

- Website: https://www.lago.fi
- Deployment verified via `(describe-module "lago.USD2")` on chain 2
