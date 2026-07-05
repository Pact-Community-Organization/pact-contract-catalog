# Security Assessment — CyberFly Token (CFLY)

**Module:** `free.cyberfly_token`
**Status:** community-reviewed | **Date:** 2026-03 | **Reviewer:** Pact Community Org

## Capability Model

Standard `fungible-v2` + `fungible-xchain-v1` capability model via `free.util-fungible`:

| Capability    | Guard                              | Managed      | Event | Risk   |
|---------------|------------------------------------|--------------|-------|--------|
| `GOVERNANCE`  | Keyset guard (cyberfly_team)        | No           | No    | Medium |
| `TRANSFER`    | sender guard                       | Yes (amount) | No    | Low    |
| `DEBIT`      | require-capability TRANSFER        | No           | No    | Low    |
| `CREDIT`     | Internal                           | No           | No    | Low    |

## Risk Profile

| Area                 | Finding                                             | Risk   |
|----------------------|-----------------------------------------------------|--------|
| Governance           | `free` namespace — less isolated than hash ns       | Medium |
| Standard compliance  | Full fungible-v2 + fungible-xchain-v1               | Low    |
| Shared dependency    | Uses `free.util-fungible` shared library            | Low    |
| Blessed hashes (4)   | Active cross-chain history with upgrades            | Low    |

## Recommendations

1. Same governance concern as cyberfly_node — `free` namespace keyset is less
   protected than a hash namespace admin keyset.
2. The shared `free.util-fungible` dependency is acceptable but should be monitored
   for upstream changes.
3. Standard fungible implementation — no critical issues found.
