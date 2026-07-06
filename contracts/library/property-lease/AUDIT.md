# AUDIT — library/property-lease

## Summary

| Field | Value |
|---|---|
| **Module** | `property-lease` (namespace: project-specific) |
| **Version** | 1.0.0 |
| **Audit Status** | self-reviewed |
| **Category** | PCO Library Template |
| **Source** | PCO-authored reference implementation |
| **Last review** | 2026-07-06 |

## Purpose

Deployable on-chain rental-lease rails: a property registry with immutable
revenue splits, per-property rent bucketing inside one capability-guarded
vault, deposit escrow, and claim-window settlement. The enforceable lease is
the signed off-chain document whose hash each lease anchors; this module is the
money-and-record layer.

## Trust model (read alongside the README)

v1 has **no arbiter**. At lease end the landlord files one deposit-deduction
claim — capped at the escrowed amount, one claim only, only inside the claim
window — and after the window anyone may settle (claim to the landlord,
remainder to the tenant). The claim is *bounded* but not *adjudicated*: the
tenant has no on-chain dispute path. This is the template's largest trust
asymmetry and is appropriate only where a real off-chain lease and legal system
back the rails. The independent review confirmed the cap and window bounds
cannot be exceeded; the asymmetry is a documented design choice, not a defect.
A v2 would add an arbiter-guard slot gating the claim.

## Pre-catalog finding (spike testing)

Before catalog review, the test suite caught a `lease-state` cond-ordering
bug: a fully-settled lease (deposit-held zeroed) was reported as
`AWAITING-DEPOSIT`/`SETTLEMENT-DUE` rather than its correct terminal
`CLOSED` state. Fixed by branching the post-`end` states on
`deposit-held > 0` first; regression-asserted (the settle lifecycle test
asserts `CLOSED`).

## Audit history: findings and fixes

An independent `pact-auditor` pass returned **NO-GO** on the first version,
with two blocking findings. All were fixed:

| # | Severity | Finding | Fix |
|---|----------|---------|-----|
| F1 | **HIGH** | `give-notice` authenticated the parties with `(enforce-one [ (with-capability (LANDLORD …) true) (with-capability (TENANT …) true) ])`. The `LANDLORD`/`TENANT` capability bodies read the `properties`/`leases` tables, and an `enforce-one` **condition** evaluates in read-only mode — so this was a table read inside an enforce condition (the KDA-CE `BUG-010` class): **REPL-green but node-fatal**, which would have killed `give-notice` (the only early-termination path) on-chain for everyone, extending deposit lock duration. This was introduced by the (well-intended) promotion of party auth to scoped capabilities. | A new `PARTY (lease-id)` capability authenticates either party. Its body binds **both** guards to locals *before* the `enforce-one`, so the reads run in the defcap body (node-safe), not inside the enforce-one condition; the condition enforces only the bound locals. `give-notice` is now `(with-capability (PARTY lease-id) …)`, and parties scope their signature to `(property-lease.PARTY "lease-id")`. **This class is REPL-invisible — devnet validation is the required evidence (see below).** |
| F2 | MEDIUM | `settle-deposit` called `vault-pay` twice (claim → landlord, remainder → tenant). When **landlord == tenant** and **claim == held/2**, the two payouts installed the *identical* managed `(coin.TRANSFER vault payee amount)` capability, and the second install aborted (`already installed`) — a non-recoverable failure that, with the claim window already closed, **permanently locked the deposit**. | `settle-deposit` now coalesces identical payees: when the landlord and tenant are the same account it pays the full `held` amount once; otherwise the original two-payout path is unchanged. Regression-tested with a self-lease (`landlord == tenant`, `claim == held/2`) that now settles cleanly. |
| F3 | LOW | `set-property-active` (the only state-mutating admin toggle) emitted no event — an audit-trail gap. | Added `PROPERTY-ACTIVE-SET` `@event` and emit it. Regression-tested. |
| F4 | INFO | The final billing period is not prorated: `pay-rent`'s gate is `paid-through < end` *before* paying, so the last payment can advance `paid-through` past `end` by up to `period-days` (the tenant pays a whole final period). Conservation still holds. | Documented (README "Known limits": no partial payments; fixed-period billing). |
| F5 | INFO | If a landlord loses their key, the TAX / REPAIRS / LANDLORD buckets are permanently unreachable (only the `LANDLORD`-guarded withdrawal exits them). BENEFICIARY and the deposit have permissionless exits and survive key loss. | Documented as an inherent key-custody residual. |

A **second** independent pass verified F1–F3 closed with no regression, but
found one new MEDIUM (also fixed):

| # | Severity | Finding | Fix |
|---|----------|---------|-----|
| N1 | MEDIUM | Stored payout destinations (landlord, beneficiary, tenant) are paid via `coin.transfer-create` with their *enrolled* guard. A **vanity** (non-principal) account name could be squatted by anyone with a foreign guard at gas-only cost, after which coin aborts every payout to it (`account guards do not match`) — permanently locking the tenant's deposit (a bricked `settle-deposit`), a landlord bucket, or the beneficiary bucket. Grief-only (the squatter can never *receive* the funds), but a real liveness/fund-lock defect. | `register-property` now enforces `validate-principal` on the landlord and beneficiary accounts, and `create-lease` on the tenant account — every stored payout destination must be a principal (`k:`/`w:`/`r:`). coin's reserved-name protocol then makes squatting impossible and guarantees the enrolled guard matches (and structurally excludes the vault account). Regression-tested (vanity landlord / beneficiary / tenant all rejected). Free withdrawal payees are unaffected — they are paid at withdrawal time, not from stored state. |

With N1 fixed, the second pass returned **GO**.

## Threat model & defenses

| Vector | Defense | Test |
|---|---|---|
| Attacker moves vault funds to a chosen account | `VAULT` is internal-only; every payout is landlord-guarded or bounded to recorded accounting paid to a *stored* destination — no attacker-chosen payee+amount path exists | withdrawal + push + settle cases |
| Non-landlord withdraws / registers | `LANDLORD` cap enforces the enrolled guard; registration enforces the landlord guard | stranger-withdraw, unsigned-register |
| Signature scoped to the wrong property | `LANDLORD (property-id)` is per-property; a sig scoped elsewhere is rejected | scoped-signature isolation case |
| One party forges a lease / renewal | `create-lease` / `renew-lease` require BOTH guards in one tx | one-sided lease + one-sided renewal rejections |
| Stranger terminates a lease | `PARTY` cap enforces landlord-or-tenant | stranger-notice rejection |
| Rent paid before deposit escrowed | `pay-rent` gates on `deposit-held == deposit` | deposit-gate case |
| Bucket overdraw / beneficiary pull by landlord | `debit-bucket` balance check; BENEFICIARY not landlord-withdrawable | overdraw + beneficiary-pull rejections |
| Value leak in the split | landlord residual absorbs floor dust; conservation asserted to 12 dp | on-time / late / 33.33%×3 dust cases |
| Claim above deposit / twice / out of window | `claim-deposit` bounds (`<= held`, `not filed`, in-window) | claim rejection cases |
| Settle early / twice / self-brick | window gate + single-shot `held > 0` + same-payee coalescing (F2) | settle rejections + self-lease regression |
| `add-time` int64 overflow | all stored times bounded 1970–2200, day-counts capped | far-future-end rejection |
| Squatted payout account bricks settlement | landlord / beneficiary / tenant must be principal accounts (N1) | vanity-account rejection cases |
| Two same-payee vault payouts collide in one tx | `settle-deposit` coalesces landlord==tenant; README notes one-payout-per-payee-per-tx | self-lease settlement case |
| Bucket-key collision | ids forbid `|`; bucket names are fixed constants | (structural; ids ASCII ≤64) |

## Capability model

| Capability | Type | Guard | Notes |
|---|---|---|---|
| `GOV` | governance | `keyset-ref-guard GOV_KEYSET` | upgrade only; no fund path |
| `LANDLORD (property-id)` | authentication | enrolled landlord guard (read in `enforce-guard` arg position) | scoped per property |
| `TENANT (lease-id)` | authentication | enrolled tenant guard | scoped per lease; used in `renew-lease` |
| `PARTY (lease-id)` | authentication | landlord OR tenant (both bound before `enforce-one`) | either-party; used only by `give-notice` |
| `VAULT` | weak-body | — | Safe: internal-only; guards the vault account + bucket ledger; every acquisition is landlord-guarded or bounded to recorded accounting to a stored account |
| `PROPERTY-REGISTERED` / `LEASE-SIGNED` / `DEPOSIT-PAID` / `RENT-PAID` / `WITHDRAWAL` / `DEPOSIT-CLAIMED` / `DEPOSIT-SETTLED` / `NOTICE-GIVEN` / `LEASE-RENEWED` / `PROPERTY-ACTIVE-SET` | `@event` | — | emit-only audit trail |

The vault account guard requires `VAULT`, which is composed only inside this
module and never on a path that pays an attacker-chosen account. Conservation
(`vault balance == Σ bucket balances + Σ deposits held`) holds across every
mutating path — verified by the independent review and asserted to 12 decimals
throughout the suite.

## Node-safety

Every table read that feeds an `enforce` (or an `enforce-one` condition) is
bound to a local first: the `LANDLORD` / `TENANT` guard reads sit in
`enforce-guard` argument position, and the `PARTY` cap binds both guards before
its `enforce-one` (the F1 fix). This class is **REPL-invisible on KDA-CE**, so
a **devnet run of `give-notice` (either party), plus a full
create → deposit → rent → claim → settle cycle, is the required evidence**
before any production use — the single most important gate for this entry.

## Risk profile

| Risk | Level | Notes |
|---|---|---|
| Vault theft | Low | no attacker-chosen payout path; `VAULT` internal-only |
| Conservation break | Low | dust-absorbing residual; asserted to 12 dp |
| Unauthorized party action | Low | scoped `LANDLORD`/`TENANT`/`PARTY` caps; mutual assent on create/renew |
| Fund lock | Low | F2 self-brick fixed; residual landlord-key-loss lock documented (F5) |
| Deposit dispute | **Medium (by design)** | no arbiter — see Trust model; off-chain document is the backstop |
| Governance dependency | Medium | upgrade power: pin the module hash, multi-sig the keyset |

## Static analysis note

`pact-static-check.sh` reports **PASS, 0 violations**. The `enforce-guard`
WARNs are dispositioned SAFE: inside `GOV`, inside the `LANDLORD`/`TENANT`/
`PARTY` defcaps, and at the two guard-*enrollment* points (`register-property`,
`create-lease`) where the guard is being stored this transaction and no
capability yet exists to scope to — the same pattern the treasury and vesting
templates use at setup.

## What self-reviewed means here

Reviewed by the template's maintainers against the PCO checklist, with all
authorization / conservation / lifecycle scenarios encoded as runnable
regression tests, plus two independent `pact-auditor` passes (automated,
fresh-context) whose blocking findings are all fixed. **Not independent human
review.** Promotion requires a second reviewer (`community-reviewed`) or a
third-party report with a matching source hash (`independently-audited`) — see
`docs/CONTRACT_POLICIES.md` §3.1.

## Reproduce the review

```bash
cd contracts/library/property-lease/examples
pact property-lease-test.repl   # 83 assertions
```
