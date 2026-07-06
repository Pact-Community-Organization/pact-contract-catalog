# AUDIT — library/token-fungible

## Summary

| Field | Value |
|---|---|
| **Module** | `token` (namespace: project-specific) |
| **Version** | 0.2.0 |
| **Audit Status** | self-reviewed |
| **Category** | PCO Library Template |
| **Source** | PCO-authored reference implementation |
| **Last review** | 2026-07-05 (PCO, template hardening) |

## Purpose

Deployable template for a fungible token implementing `fungible-v2` and
`fungible-xchain-v1`. Designed as a hardened starting point; adapt namespace,
governance keyset, and tokenomics before deployment.

## v0.1 → v0.2: remediated findings

Version 0.1 of this template contained a **CRITICAL authorization flaw**, and its
audit record at the time incorrectly rated authorization bypass as "Low". Recorded
here permanently for transparency:

| # | Severity | v0.1 finding | v0.2 remediation |
|---|----------|--------------|-------------------|
| 1 | **CRITICAL** | `DEBIT` only checked `sender != ""` — it never enforced the sender's account guard. Any signer scoping the managed `TRANSFER` cap could transfer **anyone's** funds. | `DEBIT` now enforces the sender's stored guard (coin pattern, read let-bound before enforcement). Regression-tested: attacker-scoped `TRANSFER` fails with `Keyset failure`. |
| 2 | **CRITICAL** | `transfer-crosschain` step 0 acquired plain `DEBIT` directly — no managed cap, no guard: anyone could burn/redirect anyone's funds cross-chain. | Step 0 now requires the managed `TRANSFER_XCHAIN` cap which composes the guard-enforcing `DEBIT`; target-chain validated against `VALID_CHAIN_IDS` and same-chain transfers rejected. Regression-tested. |
| 3 | High | No reserved-account protocol: anyone could create `k:<key>` accounts with their own guard (squatting). | `enforce-reserved` (coin pattern) at `create-account` and inside `credit` for implicit creation. Regression-tested. |
| 4 | Medium | `@doc` claimed `fungible-xchain-v1` compliance but the module did not implement the interface (no `TRANSFER_XCHAIN`/`TRANSFER_XCHAIN_RECD`). | `(implements fungible-xchain-v1)` with the full capability surface. |
| 5 | Medium | No account validation (length/charset); no supply mechanism (tests seeded balances by acquiring internal caps directly). | `validate-account` bounds + charset; governed `mint` with `MINT` event. |
| 6 | Low | Test suite used invalid 3-argument `(try ...)` forms and never exercised the attack paths; a REPL pass proved nothing. | Suite rewritten: self-contained (loads registry interfaces), 31 assertions including both drain-attack regressions and the doomed-yield fast-fail; runs blocking in CI. |

## Capability model (v0.2)

| Capability | Type | Guard | Notes |
|---|---|---|---|
| `GOV` | governance | `keyset-ref-guard "token-gov"` | Replace with deployed multi-sig keyset |
| `DEBIT` | internal | **sender's stored account guard** | The authorization for every outgoing transfer |
| `CREDIT` | internal | weak-body | Safe: only acquired composed under `DEBIT`/`GOV` paths |
| `TRANSFER` | `@managed amount` | composes `DEBIT`+`CREDIT` | Auto-emits event on acquisition |
| `TRANSFER_XCHAIN` | `@managed amount` (one-shot mgr) | composes `DEBIT` | Cross-chain step 0 |
| `TRANSFER_XCHAIN_RECD` | `@event` | — | Emitted on step 1 receipt |
| `ROTATE` | `@managed` one-shot | old guard enforced in `rotate` | Principal accounts cannot rotate away |
| `MINT` | `@event` weak-body | acquired only under `GOV` | Supply transparency |

## Risk profile (v0.2)

| Risk | Level | Notes |
|---|---|---|
| Authorization bypass | Low | Sender guard enforced in `DEBIT` on all debit paths; regression tests in CI |
| Account squatting | Low | `enforce-reserved` on both creation paths |
| Supply inflation | Low | Only `GOV`-gated `mint`; event-audited |
| Reentrancy | Low | No external module calls in any capability or write path |
| Keyset dependency | Medium | `token-gov` must be defined pre-deploy; template ships REPL-style unqualified name — **must** be namespace-qualified for on-chain use |
| Cross-chain lifecycle | Medium | Step 1 (SPV resume) is untestable in the REPL — devnet validation is mandatory before production (see README checklist) |

## Independent review (pact-auditor, 2026-07-05)

An independent audit pass (fresh-context reviewer, no implementation history)
walked the full capability tree, ran 11 adversarial REPL probes plus the shipped
suite, and cross-checked every debit/credit/rotate/mint/cross-chain path line-by-line
against `coin-v6`. **Verdict: GO at `self-reviewed`. Zero CRITICAL / HIGH / MEDIUM
findings.** No third-party-exploitable path exists; the read-before-enforce pattern
is applied consistently (node-safe); both managed-cap managers are correct.

Three LOW findings were raised and **all three fixed in this same version** before release:

| # | Finding | Fix applied |
|---|---------|-------------|
| L1 | `mint` did not emit the ecosystem-standard `(TRANSFER "" account amount)` — indexers reconstructing balances from fungible-v2 events would under-count supply. | `mint` now emits `TRANSFER "" account amount` alongside `MINT`. Asserted in suite. |
| L2 | Cross-chain step 0 would debit then lock funds forever if the `k:` receiver's guard mismatched (uncompletable defpact). | Step 0 now `enforce-reserved`s the receiver before any state change; fails fast. Regression-tested. |
| L3 | README did not warn that upgrading with in-flight cross-chain transfers requires blessing the old module hash. | Added to the deployment checklist. |

INFO items (governance omnipotence, hardcoded chain ids, REPL-only keyset name,
`@model` non-enforcement on 5.4ce, no burn) are inherent template characteristics
and documented in README/AUDIT.

## What self-reviewed means here

Reviewed by the template's own maintainers against the PCO checklist, with the
attack scenarios encoded as runnable regression tests. **Not independent.**
Promotion to `community-reviewed` requires a second PCO reviewer sign-off;
`independently-audited` requires a third-party report with a matching source hash
(see `docs/CONTRACT_POLICIES.md` §3.1).

## Devnet validation (on-node evidence)

**Validated on a live KDA-CE devnet (recap-development) node, 2026-07-06.** The template was deployed under the
`free` namespace (governance keyset namespaced, per the deployment checklist)
and its critical paths were driven to mined confirmation with `@kadena/client`
— the required evidence for the REPL-invisible read-in-enforce class.

| | |
|---|---|
| Deployed module | `free.token-v2` |
| Source hash | `GI-zDC-lWmrfJ_hDo7bxS0l7ifUFw0sD3dZtBDDTT_0` |
| Confirmed transactions | 10 |

Proven on-node: `DEBIT` (sender's stored guard `let`-bound before `enforce-guard`, the v0.2.0 CRITICAL fix): an authorized transfer succeeded, a **foreign-key transfer was rejected**, and a guard rotation updated exactly the stored guard the DEBIT reads (the old key then failed).

Reproduce: `scripts/devnet-validate` → `npm run token-fungible` (see that directory's README).

## Reproduce the review

```bash
cd contracts/library/token-fungible/examples
pact token-test.repl        # 31 assertions, includes attack + doomed-yield regressions
```
