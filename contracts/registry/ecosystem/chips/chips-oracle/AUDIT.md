# Security Assessment — Chips Oracle

**Module:** `n_e98a056e3e14203e6ec18fada427334b21b667d8.chips-oracle`
**Status:** community-reviewed | **Date:** 2026-03 | **Reviewer:** Pact Community Org

## Capability Model

| Capability    | Guard                          | Managed | Event | Risk  |
|---------------|--------------------------------|---------|-------|-------|
| `GOVERNANCE`  | `chips-admin` keyset (ns)      | No      | No    | Low   |
| `ADMIN`       | Admin address OR GOVERNANCE    | No      | No    | Low   |

## Risk Profile

| Area              | Finding                                            | Risk   |
|-------------------|----------------------------------------------------|--------|
| Governance        | Hash-namespace admin keyset — well isolated        | Low    |
| Discord account   | Second write path via hardcoded Discord account    | Medium |
| Price history     | Append-only log — no update in-place               | Low    |
| Oracle freshness  | No staleness check — consumers must validate       | Medium |

## Recommendations

1. The Discord integration account (`k:4aab9...`) has write access equivalent to
   admin for price updates. Ensure this key is properly secured.
2. Consumers of this oracle should validate timestamp freshness before acting on
   price data.
3. No structural issues found. Approved for production use with the above caveats.
