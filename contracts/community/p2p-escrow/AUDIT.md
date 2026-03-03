# Security Assessment — P2P Escrow

**Module:** `free.p2p-escrow`
**Status:** needs-review ⚠️ | **Date:** 2026-03 | **Reviewer:** Pact Community Org

## ⚠️ Critical Finding

```pact
(defcap GOVERNANCE () true)
```

**The governance capability has no access control.** Any account on the network can
call governance-gated functions, including module upgrades. This is a critical issue
for production deployments.

## Capability Model

| Capability    | Guard   | Managed | Event | Risk       |
|---------------|---------|---------|-------|------------|
| `GOVERNANCE`  | `true`  | No      | No    | **CRITICAL**|
| (state ops)   | —       | —       | —     | Medium     |

## Risk Profile

| Area               | Finding                                               | Risk       |
|--------------------|-------------------------------------------------------|------------|
| Governance         | `(defcap GOVERNANCE () true)` — NO GUARD              | **CRITICAL**|
| Arbiter            | Platform arbiter hardcoded to fixed account           | High       |
| Vault              | `p2p-escrow-vault` account — review guard             | Medium     |
| Timeout windows    | T1/T2/T3 configurable by admin (no governance guard!) | High       |
| Reputation data    | On-chain reputation writable without guard            | High       |

## Findings

1. **CRITICAL:** `(defcap GOVERNANCE () true)` — anyone can upgrade this module or
   call governance-gated functions. This MUST be fixed before production use.
2. The platform arbiter is a hardcoded account. If this account is compromised,
   all disputed escrows can be resolved maliciously.
3. Timeout parameters (T1/T2/T3) can be modified without any access control.

## Recommendations

Before any production use:
1. Replace `(defcap GOVERNANCE () true)` with `(enforce-keyset "your.admin-keyset")`.
2. Make the platform arbiter configurable via a governance-gated setter rather than
   a constant.
3. A full security review is required before this module handles user funds.

**This module is cataloged for reference only. Do not deploy to production without
addressing the critical governance issue.**
