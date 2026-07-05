# AUDIT — lago.USD2 (Stablecoin Shell)

## Summary

| Field | Value |
|---|---|
| **Module** | `lago.USD2` |
| **Audit Status** | Unaudited (governance shell — minimal attack surface) |
| **On-Chain Hash** | `gx8dwzIfbuiqHtZ9km0W0bp1p7zAPYmrxfBmO7696S0` |
| **Source Size** | 193 characters |
| **Interfaces** | none |
| **Chain Coverage** | All 20 chains (governance shell; USD2-wrapper on chain 1) |

## Security Assessment

### Architecture Finding

`lago.USD2` is a **namespace governance shell** — not a functional token contract.
Its entire on-chain code is a single `GOVERNANCE` capability:

```pact
(enforce-keyset 'lago-ns-user)
```

**Implication:** There is no token logic, no state, and no user-callable functions.
The module cannot transfer tokens, mint, or burn — it only controls who can upgrade the module.

### Risk Profile

| Risk | Level | Notes |
|---|---|---|
| Reentrancy | None | No state or external calls |
| Capability escalation | None | Single restricted capability |
| Integer overflow | None | No arithmetic |
| Unauthorized access | Low | Protected by `lago-ns-user` keyset |
| Upgrade risk | Medium | Keyset holder can replace with any code |

### Governance Keyset

`lago-ns-user` keyset (`keys-any` predicate, 2 keys on-chain) controls all lago module upgrades.
Any holder of `lago-ns-user` can upgrade all six lago namespace modules simultaneously.

### Recommendations

1. If token functionality is intended, the module needs a complete fungible-v2 implementation.
2. The upgrade path via `lago-ns-user` should require multisig (`keys-2` or `keys-all`).
3. Consider timelock or migration announcement before deploying real token logic.

## Companion Modules Status

All lago co-deployed modules are also governance shells:

| Module | Hash | Interfaces | Note |
|---|---|---|---|
| `lago.kwBTC` | `eMK6d8w17...` | none | Shell |
| `lago.kwUSDC` | `ZYJ-acaoNx...` | none | Shell |
| `lago.USD2` | `gx8dwzIfbu...` | none | Shell |
| `lago.fungible-burn-mint` | `0ou5_XQM1O...` | none | Interface definition |
| `lago.bridge` (chain 1) | `TEO9_LEZwx...` | none | Bridge admin shell |
| `lago.USD2-wrapper` (chain 1) | `5xX6H-mYx4...` | none | Wrapper admin shell |

## Audit Date

Reviewed: 2026-03-02 via `(describe-module "lago.USD2")` on mainnet01.
