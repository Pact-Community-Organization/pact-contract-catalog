# Security Assessment — KDSwap Exchange

**Module:** `kdlaunch.kdswap-exchange`
**Status:** community-reviewed | **Date:** 2026-03 | **Reviewer:** Pact Community Org

## Capability Model

| Capability       | Guard            | Managed | Event | Risk  |
|------------------|------------------|---------|-------|-------|
| `GOVERNANCE`     | kdlaunch keyset  | No      | No    | Low   |
| Pair guards      | Per-pair guard   | No      | No    | Low   |

## Formal Verification Coverage

The module includes `@model` properties. The key verified property:
- `prop-pairs-write-guard`: every write to the pairs table enforces the pair guard,
  except `create-pair` (insert — new pair) and internal private functions.

Formal verification adds confidence in the core invariant, though it does not cover
economic attack vectors (e.g., flash-loan manipulation, sandwich attacks).

## Risk Profile

| Area                   | Finding                                            | Risk   |
|------------------------|----------------------------------------------------|--------|
| Formal verification    | Guard-on-write invariant machine-checked           | Low    |
| Economic attacks        | No flash-loan protection observed in source        | Medium |
| Governance             | kdlaunch keyset — centralized admin                | Medium |
| Reserve integrity       | Reserves tracked per pair — review update path    | Low    |
| Pair creation           | Unguarded insert (intentional) — any can create   | Low    |

## Recommendations

1. Review `swap-exact-in` / `swap-exact-out` for sandwich attack surface before
   deploying significant liquidity.
2. Consider adding slippage protection or minimum-output checks in critical paths.
3. The formal verification model is a strong positive signal for correctness of
   the guard invariant.
