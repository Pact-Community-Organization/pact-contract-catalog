# Security Assessment — CyberFly Node Registry

**Module:** `free.cyberfly_node`
**Status:** community-reviewed | **Date:** 2026-03 | **Reviewer:** Pact Community Org

## Capability Model

| Capability       | Guard                        | Managed | Event | Risk   |
|------------------|------------------------------|---------|-------|--------|
| `GOV`            | `free.cyberfly_team` keyset  | No      | No    | Medium |
| `STAKE`          | Node account guard           | No      | —     | Low    |
| `CLAIM_REWARDS`  | Node account guard           | No      | —     | Low    |
| `REGISTER_NODE`  | Account guard                | No      | —     | Low    |

## Risk Profile

| Area                | Finding                                              | Risk   |
|---------------------|------------------------------------------------------|--------|
| Governance          | `free` namespace keyset — less isolated than hash ns | Medium |
| Token custody       | Staked CFLY held in vault accounts                   | Medium |
| Dependency          | Requires `free.cyberfly_token` — coupled upgrade risk| Medium |
| Reward distribution | Admin-controlled reward rate parameters              | Medium |
| Node identity       | peer_id uniqueness enforced by insert semantics      | Low    |

## Recommendations

1. The `free` namespace provides weaker isolation than a hash namespace.
   A migration to a hash namespace would improve security posture.
2. Reward rate parameters controlled by admin create centralization risk —
   consider DAO-controlled parameters for production use.
3. Verify that the staking vault guard prevents unauthorized debits.
4. No critical vulnerabilities found, but the `free` namespace governance warrants
   ongoing monitoring.
