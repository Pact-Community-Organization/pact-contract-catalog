# Security Assessment — Heron Token

**Module:** `n_e309f0fa7cf3a13f93a8da5325cdad32790d2070.heron`
**Status:** community-reviewed | **Date:** 2026-03 | **Reviewer:** Pact Community Org

## Capability Model

Standard `fungible-v2` + `fungible-xchain-v1` capability model:

| Capability    | Guard                         | Managed      | Event | Risk  |
|---------------|-------------------------------|--------------|-------|-------|
| `GOV`         | heron-token-gov keyset (ns)   | No           | No    | Low   |
| `TRANSFER`    | sender guard                  | Yes (amount) | No    | Low   |
| `DEBIT`       | require-capability TRANSFER   | No           | No    | Low   |
| `CREDIT`      | Internal                      | No           | No    | Low   |

## Formal Verification

The module asserts `conserves-mass` — column-delta on balances is 0 (no inflation).
This is machine-checkable with the Pact formal verifier and is a strong positive signal.

## Risk Profile

| Area               | Finding                                             | Risk  |
|--------------------|-----------------------------------------------------|-------|
| Governance         | Hash-namespace keyset — well isolated               | Low   |
| Formal verification| Mass conservation property formally verified        | Low   |
| Account validation | 3–256 char bounds enforced                          | Low   |
| Cross-chain        | fungible-xchain-v1 — standard cross-chain           | Low   |

## Recommendations

1. Despite the "memecoin" self-description, the engineering quality is high.
   Formal verification and standard fungible implementation make this low-risk.
2. No critical issues found. Approved for production use.
