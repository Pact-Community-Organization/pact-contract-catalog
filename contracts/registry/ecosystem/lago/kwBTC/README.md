# lago.kwBTC — Namespace Governance Shell

| Field | Value |
|---|---|
| **Module** | `lago.kwBTC` |
| **Project** | Lago Protocol |
| **Category** | Governance Shell / Namespace Reservation |
| **Chains Deployed** | 20 / 20 |
| **Blockchain Hash** | `eMK6d8w17TqILbIYcbvhOWsMX49r5W5jqHdpRCLsDJY` |
| **Source Size** | 194 characters |
| **Interfaces Implemented** | none |

## On-Chain Reality

> **Important:** `lago.kwBTC` is a **governance shell** containing only a `GOVERNANCE` capability.
> It has **no fungible token logic** (no `transfer`, `get-balance`, `mint`, or `burn` functions).

The full on-chain source code is:

```pact
(module kwBTC GOVERNANCE

    (defcap GOVERNANCE ()
        @doc " Give the admin full access to call and upgrade the module. "
        (enforce-keyset 'lago-ns-user)
    )
)
```

This pattern is a **namespace reservation** — it locks the `lago.kwBTC` module name under the
`lago-ns-user` keyset so no external party can deploy code in the `lago` namespace under that name.

## Lago Namespace Architecture

The `lago` namespace uses four governance shells across all 20 chains:

| Module | Hash | Purpose |
|---|---|---|
| `lago.kwBTC` | `eMK6d8w17...` | Governance shell (btc name reservation) |
| `lago.kwUSDC` | `ZYJ-acaoNx...` | Governance shell (usdc name reservation) |
| `lago.USD2` | `gx8dwzIfbu...` | Governance shell (stablecoin reservation) |
| `lago.fungible-burn-mint` | `0ou5_XQM1O...` | Interface: mint/burn/mint-create signatures |

Chain 1 adds two additional companion modules:

| Module | Hash | Purpose |
|---|---|---|
| `lago.bridge` | `TEO9_LEZwx...` | Bridge admin governance shell |
| `lago.USD2-wrapper` | `5xX6H-mYx4...` | USD2 wrapper admin governance shell |

**All six modules are governance shells only.** The Lago protocol reserves these names under
the `lago-ns-user` keyset for future deployment or off-chain bridge operation.

## Companion Interface

`lago.fungible-burn-mint` defines the expected token interface:

```pact
(definterface fungible-burn-mint
  (defun mint:string (account:string guard:guard amount:decimal) ...)
  (defun burn:string (account:string amount:decimal) ...)
  (defun mint-create:string (account:string guard:guard amount:decimal) ...)
)
```

## Files in This Directory

| File | Module | Description |
|---|---|---|
| `kwBTC.pact` | `lago.kwBTC` | On-chain source (governance shell) |
| `fungible-burn-mint.pact` | `lago.fungible-burn-mint` | On-chain source (interface) |
| `lago-bridge.pact` | `lago.bridge` | On-chain source from chain 1 (bridge admin shell) |
| `metadata.yaml` | — | Catalog metadata |
| `AUDIT.md` | — | Security notes |

## References

- Website: https://www.lago.fi
- Deployment verified via `(describe-module "lago.kwBTC")` on chain 2
