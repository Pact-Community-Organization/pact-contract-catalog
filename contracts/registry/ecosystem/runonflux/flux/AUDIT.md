# AUDIT — runonflux.flux

## Summary

| Field | Value |
|---|---|
| **Module** | `runonflux.flux` |
| **Deployed Hash** | `zV-EMOLy3olqMfwO9Ck9…` |
| **Audit Status** | Community Reviewed |

## Security Observations

- Implements `fungible-v2` with standard `@managed` TRANSFER capability — standard transfer safety applies.
- Token is bridge-minted: supply is controlled by the RunOnFlux bridge operators. Assess bridge security separately.
- Gas station (`runonflux.flux-gas-station`) uses `GAS_PAYER` capability; only sponsors transactions that meet its filters.

## Compliance with PCO Standards

| Check | Status |
|---|---|
| `@event` on TRANSFER | ✅ |
| `@managed` on transfer amounts | ✅ |
| Explicit types | ✅ |
