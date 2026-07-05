# AUDIT — kaddex.kdx

## Summary

| Field | Value |
|---|---|
| **Module** | `kaddex.kdx` |
| **Deployed Hash** | `UbAj2RYupaT-x4vrBv8VcSzY9VN7EV…` |
| **Audit Status** | Community Reviewed |
| **Formal Audit** | Not publicly available |

## Security Observations

### Capability usage
- Implements `fungible-v2`: all transfers require `TRANSFER` capability with `@managed` on the amount — prevents double-spend via capability re-use.
- `MINT` and `BURN` capabilities are guarded by `kaddex.supply-control-v1`, which enforces governance-controlled supply bounds. This limits unbounded minting risk.
- `SPECIAL_ACCOUNT_GUARD` protects reserved accounts (treasury, DAO, team) from being overwritten by normal transfers.

### Cross-chain safety
- `fungible-xchain-v1` relies on Kadena's chain-verified SPV proofs. In KDA-CE v3.1, SPV proof expiry has been disabled — cross-chain transfers can be completed at any time after initiation with no race condition.

### Known limitations
- No public formal audit report has been published.
- Supply control governance (mint/burn) is ultimately controlled by the keyset defined at deployment. Assess governance key custody before large positions.

## Compliance with PCO Standards

| Check | Status |
|---|---|
| `@doc` on public functions | ✅ (upstream code) |
| `@event` on state-changing caps | ✅ (TRANSFER, MINT, BURN) |
| `@managed` on transfer amounts | ✅ |
| Explicit types on all function args | ✅ |
| No `(enforce true ...)` | ✅ |

## References
- Source: https://github.com/kaddex-org/swap-v2
