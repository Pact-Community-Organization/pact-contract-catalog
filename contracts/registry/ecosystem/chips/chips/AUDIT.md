# Security Assessment — Chips Protocol

**Module:** `n_e98a056e3e14203e6ec18fada427334b21b667d8.chips`
**Status:** community-reviewed | **Date:** 2026-03 | **Reviewer:** Pact Community Org

## Capability Model

The module is large (1,549 lines). Key capabilities were assessed:

| Capability              | Guard             | Managed | Event | Risk    |
|-------------------------|-------------------|---------|-------|---------|
| `GOVERNANCE`            | Admin keyset (ns) | No      | No    | Low     |
| `BANK_DEBIT`            | Internal          | No      | No    | Medium  |
| `LOCK` / `UNLOCK`       | Account guard     | No      | —     | Low     |
| `CLAIM_REWARDS`         | Account guard     | No      | —     | Low     |

## Risk Profile

| Area                  | Finding                                               | Risk    |
|-----------------------|-------------------------------------------------------|---------|
| Complexity            | 1,549 lines — high complexity, many interacting paths | High    |
| External dependencies | Depends on chips-oracle (same namespace)              | Medium  |
| Governance            | Hash-namespace keyset — well isolated                 | Low     |
| Locking math          | Early-withdraw penalty configurable by admin          | Medium  |
| Reward accounting     | Multiple supported coins — complex reward distribution| Medium  |

## Recommendations

1. Given the complexity (1,549 lines, multiple schemas, order book + staking),
   a professional audit is strongly recommended before significant TVL is deployed.
2. Verify that `chips-oracle` price updates cannot be manipulated to affect locking
   penalties or reward calculations.
3. Review the early-withdraw-penalty parameter for admin manipulation risk.
