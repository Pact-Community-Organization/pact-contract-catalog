# AUDIT — community/token-fungible

## Summary

| Field | Value |
|---|---|
| **Module** | `token` (namespace: project-specific) |
| **Audit Status** | self-reviewed |
| **Category** | PCO Community Template |
| **Source** | PCO-authored reference implementation |

## Purpose

This module is a **neutral reference template** for a fungible token implementing
`fungible-v2` and `fungible-xchain-v1`. It is designed for use as a starting point,
not for direct deployment without customization.

## Security Assessment

### Capability Model

| Capability | Type | Notes |
|---|---|---|
| `GOV` | Governance | `(keyset-ref-guard "token-gov")` — admin-only |
| `DEBIT` | Internal | Restricts sender; required by `transfer` and `transfer-crosschain` |
| `CREDIT` | Internal | Restricts receiver; required by `transfer` |
| `TRANSFER` | `@managed` | Amount-managed; enforces positive, correct precision |
| `ROTATE` | `@managed` | Single-use guard rotation |

### Known Considerations

1. **Missing AUDIT.md** — addressed in this file.
2. **`fungible-v2.account-details`** — the `details` function return type references the
   interface type; module must be deployed in an environment where `fungible-v2` is already
   installed.
3. **`@managed true` on ROTATE** — allows any call when capability has been granted; callers
   should validate guard equality before calling `rotate`.
4. **No gas station** — intended for projects to add their own, or use `kadena.spirekey`.
5. **Cross-chain step** — basic `yield`/`resume` pattern; works but callers should
   validate target-chain is not empty (enforce already present).

### Risk Profile

| Risk | Level | Notes |
|---|---|---|
| Reentrancy | Low | No external calls within caps; `require-capability` guards all internal ops |
| Overflow | Low | `decimal` type with `enforce-unit` on precision |
| Authorization bypass | Low | All write paths guarded by `DEBIT`/`CREDIT` |
| Keyset dependency | Medium | `token-gov` must be defined before deployment |

### Recommendations for Production Use

1. Replace `"token-gov"` keyset reference with a deployed, multi-sig keyset.
2. Add rate limiting or supply-control capabilities for minting.
3. Run test suite against the full KDA sandbox (`kadena_repl_sandbox/kda-env/init.repl`)
   to verify interface compliance before deployment.
4. Add `@event` annotation to `TRANSFER` when deploying to mainnet for off-chain indexing.

## Audit Date

Community review: 2026-03-02.
Status: **self-reviewed** — documented author self-review; pending independent security audit.
