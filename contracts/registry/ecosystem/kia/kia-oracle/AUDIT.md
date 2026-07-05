# Security Assessment — KIA Oracle

**Module:** `n_40c883decc192e1e3214898f04656b2e9ea7b74e.kia-oracle`
**Status:** community-reviewed | **Date:** 2026-03 | **Reviewer:** Pact Community Org

## Capability Model

| Capability    | Guard                  | Managed | Event | Risk  |
|---------------|------------------------|---------|-------|-------|
| `GOVERNANCE`  | `admin` keyset (ns)    | No      | No    | Low   |
| `ADMIN`       | Composes GOVERNANCE    | No      | No    | Low   |
| `STORAGE`     | `true` (internal gate) | No      | No    | Low   |

STORAGE is composed by ADMIN and required by data-write helpers.
Reporters hold only the REPORT keyset and can push data without GOVERNANCE.

## Risk Profile

| Area                    | Finding                                          | Risk   |
|-------------------------|--------------------------------------------------|--------|
| Governance              | Admin keyset in hash namespace — well isolated   | Low    |
| Data integrity          | No @event on value updates — no on-chain log     | Medium |
| Replay / staleness      | Timestamps stored per key but not validated      | Medium |
| Access control          | Two-tier ADMIN/REPORT — principle of least priv  | Low    |
| Upgradeability          | Standard keyset governance — acceptable          | Low    |

## Recommendations

1. Consider emitting an `@event` capability on `set-value` / `set-values` to enable
   off-chain indexing of oracle updates.
2. Consider enforcing a minimum timestamp delta to prevent replay of stale data.
3. No issues found with the capability hierarchy. Approved for production use as-is.
