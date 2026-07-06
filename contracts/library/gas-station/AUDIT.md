# AUDIT — library/gas-station

## Summary

| Field | Value |
|---|---|
| **Module** | `gas-station` (namespace: project-specific) |
| **Version** | 1.0.0 |
| **Audit Status** | self-reviewed |
| **Category** | PCO Library Template |
| **Source** | PCO-authored reference implementation |
| **Implements** | `gas-payer-v1` |
| **Last review** | 2026-07-05 |

## Purpose

Deployable template for a gas station that funds users' gas from an on-chain,
sponsor-controlled allowlist under strict per-transaction and per-user bounds.

## Design history: why this is allowlist-based, not code-introspecting

The first draft of this template used the common pattern of inspecting the
transaction's `exec-code` / `tx-type` via `read-msg` to fund only calls to a
named module. An independent `pact-auditor` pass **rejected it (NO-GO) with a
CONFIRMED CRITICAL drain**, and the finding was reproduced:

- `read-msg` returns the mutable tx `data` payload, which is **not bound** to the
  code the transaction executes (the gas-station-design skill flags `read-msg`
  keys as project-defined convention, not enforced introspection).
- A single `exec-code` string carrying two top-level forms —
  `"(free.my-dapp.ping) (coin.transfer \"station\" \"attacker\" 9999.0)"` —
  passed the "one list element + prefix match" check and was **approved** by the
  station (verified: `GAS_PAYER` returned success). The station would have funded
  an attacker-chosen operation.

String-prefix allowlisting cannot deliver a drain guarantee, so the template was
**redesigned**: authorization now comes from a governance-controlled on-chain
allowlist (`enroll-user`), and the executable path contains **no `read-msg`**.

A **second** independent auditor pass on that redesign returned another **NO-GO**
with a fresh CRITICAL, all three findings now fixed:

| # | Severity | Finding | Fix |
|---|----------|---------|-----|
| F1 | **CRITICAL** | The price/limit bounds and cap accounting used the signer-supplied `GAS_PAYER` **arguments**, which are not bound to the transaction's real gas. An attacker naming an enrolled user could pass tiny decoy args while setting a huge actual gas limit, draining the station past every bound at ~zero recorded cost. | `GAS_PAYER` now reads `(chain-data)` `gas-price`/`gas-limit` — the amounts coin actually debits — and bounds/accounts against **those**, ignoring the args for money math. Mirrors `flux-gas-station`'s `enforce-below-or-at-gas-*`. Regression-tested (`F1-drain-*`). |
| F2 | MEDIUM | `user` was not authenticated — anyone naming an enrolled user could spend that user's budget on arbitrary transactions. | Each enrollment stores a `guard`; `GAS_PAYER` calls `enforce-guard` on it. Regression-tested (`F2-unauthenticated-user`). |
| F3 | LOW | No events for enroll/disable/reset/withdraw/funding (weak audit trail). | `@event` caps `ENROLL`/`DISABLE`/`RESET`/`FUNDED`/`WITHDRAW` emitted on each path; asserted in suite. |

A **third** pass on the fixed design returned **GO** at `self-reviewed` — all
three prior findings verified genuinely closed, no drain path, zero
CRITICAL/HIGH/MEDIUM. Its one LOW and the actionable INFO items were applied
before release:

- **LOW** — the governance keyset name was a literal duplicated in the `GOV` cap
  and the station guard's withdraw branch; a deployer editing one but not the
  other would split governance. Hoisted to a single `GOV_KEYSET` defconst
  referenced by both.
- **INFO** — added a defense-in-depth `(enforce (>= tx-max-cost 0.0) ...)` (an
  on-chain-unreachable case, but it keeps `spent` provably monotonic).
- **Test coverage** — added a positive funding test under a **scoped** signature
  (the real wallet flow) and a `reset-user-spent` / `RESET` path test.

The redesign is a stronger, enforceable guarantee at the cost of requiring the
sponsor to enroll accounts (name + guard) explicitly.

## Threat model & defenses

| Vector | Defense | Test |
|---|---|---|
| Fund a non-sponsored account | Only enrolled + enabled users pass `GAS_PAYER` | `reject-non-enrolled`, `reject-disabled` |
| Spend another user's budget by naming them | `enforce-guard` on the enrolled user's stored guard | `F2-unauthenticated-user` |
| Pass tiny cap args but consume huge real gas | Bounds/accounting use **actual** `(chain-data)` gas, not args | `F1-drain-actual-gas-over-bound`, `F1-drain-actual-limit-over-bound` |
| Zero/negative declared limit or price | canonical `gas-payer-v1` positivity checks | `reject-nonpositive-args` |
| Exhaust the station via one user | per-user cumulative `cap` on `spent += actual-limit*actual-price` | `carol-second-fund-over-cap` |
| Spend the station outside gas eval or governance | account guard requires (`coin.GAS` + `ALLOW_GAS`) OR the gov keyset | `guard-denies` |
| Non-governance withdrawal | station guard's governance branch enforces `gas-station-gov` | `withdraw-requires-gov` |
| Tamper the funded operation via tx `data` | **Not applicable** — no `read-msg` in the executable path | — (structural) |

## Capability model

| Capability | Type | Guard | Notes |
|---|---|---|---|
| `GOV` | governance | `keyset-ref-guard GOV_KEYSET` | Gates enroll/disable/reset/init/upgrade |
| `GAS_PAYER` | `gas-payer-v1` | on-chain allowlist + bounds | Composes `ALLOW_GAS` **only after all checks pass** |
| `ALLOW_GAS` | weak-body | — | Safe: composed only inside `GAS_PAYER`; not externally acquirable; required by the station guard |

The station account guard (`gas-payer-guard-pred`) uses `enforce-one` over two
branches: (1) `require-capability coin.GAS` **and** `require-capability ALLOW_GAS`
(the gas-payment path), or (2) `enforce-guard` on the governance keyset (the
withdrawal path). Neither branch is satisfiable by an unauthorized caller.

## Node-safety

The only table read in an authorization path is `with-read allowlist user` inside
`GAS_PAYER`; it is bound (via `with-read`) before any `enforce`, so it is
node-safe (the REPL-vs-node "table read inside enforce" trap does not apply). The
static gate passes with 0 violations.

## Risk profile

| Risk | Level | Notes |
|---|---|---|
| Drain / unauthorized spend | Low | Allowlist + bounds + cap, all regression-tested; no code-introspection surface |
| Reentrancy | Low | No external module calls in `GAS_PAYER`; `coin` calls only in GOV/guard-gated `init`/`withdraw` |
| Governance dependency | Medium | `gas-station-gov` must be defined pre-deploy; template ships an unqualified REPL name — **must** be namespace-qualified on-chain |
| End-to-end gas flow | Medium | REPL tests the policy + guard directly; coin buy/redeem wrapping validated on devnet |
| Enrollment trust | By design | The station does not constrain which module an enrolled user calls; enrollment is the sponsor's trust boundary |

## What self-reviewed means here

Reviewed by the template's maintainers against the PCO checklist, with all
authorization/bounds/drain scenarios encoded as runnable regression tests, across
**three independent auditor passes** — the first two drove full redesigns away
from two distinct CRITICAL drains, and the third returned GO on the final code
with the LOW/INFO items applied.

We keep the status at **`self-reviewed`** rather than `community-reviewed`
deliberately: the auditor passes were automated fresh-context reviews by the same
tooling maintained alongside this template, not a review by an independent second
PCO maintainer, and — critically — the on-chain `buy-gas`/`redeem-gas` wrapping
and the scoped-signature authentication path are behaviors the bare REPL
**cannot** prove. A **mandatory devnet end-to-end run** (README deployment step 6)
is the remaining evidence gate before any production claim. `independently-audited`
additionally requires a third-party report with a matching source hash
(`docs/CONTRACT_POLICIES.md` §3.1).

## Reproduce the review

```bash
cd contracts/library/gas-station/examples
pact gas-station-test.repl   # 30 assertions
```
