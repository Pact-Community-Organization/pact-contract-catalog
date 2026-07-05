# lago.kwUSDC — Namespace Governance Shell

| Field | Value |
|---|---|
| **Module** | `lago.kwUSDC` |
| **Project** | Lago Protocol |
| **Category** | Governance Shell / Namespace Reservation |
| **Chains Deployed** | 20 / 20 |
| **Blockchain Hash** | `ZYJ-acaoNxTNtgiShBi7q-OakMCdQkKFJLwGtLjEtSQ` |
| **Source Size** | 195 characters |
| **Interfaces Implemented** | none |

## On-Chain Reality

> **Important:** `lago.kwUSDC` is a **governance shell** with no token logic.
> It contains only a `GOVERNANCE` capability enforcing the `lago-ns-user` keyset.

Full on-chain source:

```pact
(module kwUSDC GOVERNANCE

    (defcap GOVERNANCE ()
        @doc " Give the admin full access to call and upgrade the module. "
        (enforce-keyset 'lago-ns-user)
    )
)
```

This reserves the `lago.kwUSDC` module name under the Lago team's keyset control.

## Lago Namespace Architecture

See [lago/kwBTC/README.md](../kwBTC/README.md) for the full namespace architecture diagram.
All six lago modules (kwBTC, kwUSDC, USD2, fungible-burn-mint, bridge, USD2-wrapper)
are governance shells with no deployed token functionality.

## Files in This Directory

| File | Module | Description |
|---|---|---|
| `kwUSDC.pact` | `lago.kwUSDC` | On-chain source (governance shell) |
| `fungible-burn-mint.pact` | `lago.fungible-burn-mint` | On-chain source (interface) |
| `metadata.yaml` | — | Catalog metadata |
| `AUDIT.md` | — | Security notes |

## References

- Website: https://www.lago.fi
- Deployment verified via `(describe-module "lago.kwUSDC")` on chain 2
