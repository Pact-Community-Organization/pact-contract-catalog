# AUDIT — library/vesting

## Summary

| Field | Value |
|---|---|
| **Module** | `vesting` (namespace: project-specific) |
| **Version** | 1.0.0 |
| **Audit Status** | self-reviewed |
| **Category** | PCO Library Template |
| **Source** | PCO-authored reference implementation |
| **Last review** | 2026-07-05 |

## Purpose

Deployable template for KDA vesting with cliff + linear release, escrowed
upfront: a grant locks its full amount in a capability-guarded vault at
creation; the beneficiary claims the vested portion over time; a revocable
grant lets the funder reclaim only the unvested remainder. Governance is
upgrade-only — the deployed code gives it no path to escrowed funds.

## Audit history: findings and fixes

An independent `pact-auditor` pass returned **NO-GO** on the first version
(zero CRITICAL/HIGH; one MEDIUM ship-stopper). All findings were fixed:

| # | Severity | Finding | Fix |
|---|----------|---------|-----|
| F1 | **MEDIUM** | `revoke` computed `refund = total − vested(now)` without asserting `vested ≥ claimed`. Under a **non-monotonic block-time**, `vested(now)` could fall below `claimed`, making the refund exceed the grant's own remaining escrow. Because the vault is **shared across grants**, the excess was paid out of *other grants' escrow* — reproduced: a co-tenant grant was left unable to pay its beneficiary (`Insufficient funds`). | `revoke` now binds `claimed` and clamps `vested = max(vested-raw, claimed)`, so the refund is capped at `total − claimed` (this grant's own remaining escrow) and the frozen total stays ≥ claimed (no negative claimable after revoke). Regression-tested (`revoke-g6-clock-rollback`: claim 90 at day 90, revoke with the clock rolled back to day 40 → refund 10, not 60). The `claimable-amount` view is clamped at zero. |
| F2 | LOW | The beneficiary name was not bound to the enrolled guard, so a **vanity-named** beneficiary could be squatted (account pre-created with a foreign guard), after which every claim failed coin's guard match — a permanent fund lock. | `create-grant` now enforces `(validate-principal beneficiary-guard beneficiary)`. Squatting a principal is impossible (coin's reserved-name protocol rejects a foreign guard) and principal accounts cannot be guard-rotated. Regression-tested (vanity rejection + coin-level squat impossibility). |
| F3 | LOW | No exit path existed for a locked grant (no admin sweep — by design), so F2's squat-brick was a *permanent* loss state. | Structurally eliminated by the F2 fix: no third-party action can create a locked grant. Residual self-inflicted states are documented below. |
| F4 | INFO | The header claim "governance has NO path to escrowed funds" was only true of the deployed bytecode — an upgrade can replace it. | Docs tightened: pin the audited module hash; put GOV under a multi-sig keyset. |
| F5 | INFO | `start`/`cliff`/`end` magnitudes are unbounded (pathological far-future times can overflow time arithmetic). Impact confined to that single grant. | Accepted as-is for a trusted-funder template; documented. |

A **second** independent pass verified F1–F5 closed with no regression —
including targeted probes of the fix seams: the clamp's bounds were re-derived
(`refund ∈ [0, total−claimed]` for all inputs), and the principal binding
survived every self-referential-guard construction (a reconstructed vault
guard canonicalizes to the vault's own principal, which is rejected by name;
no alternate construction of the vault predicate yields a different
principal). Verdict: **GO**, with two new low-impact items — both fixed:

| # | Severity | Finding | Fix |
|---|----------|---------|-----|
| N1 | LOW | Doc/code mismatch: docs promised `k:/w:/r:` beneficiaries, but the code accepted **any** guard whose principal matched — including syntactically-valid but *unsatisfiable* `c:`/`u:` guards (reproduced: a `c:` capability-guard beneficiary creates fine and every claim fails forever). Funder-self-inflicted lock; no third-party exposure. | `create-grant` now enforces `typeof-principal ∈ {k:, w:, r:}` — the documented restriction is real. Regression-tested (`c:` beneficiary rejected). |
| N2 | INFO | A claimer who also scopes their signature to the vault's `coin.TRANSFER` cap collides with the module's own `install-capability` and the tx fails (harmlessly, per-tx, user-recoverable). | README usage note: sign `claim`/`revoke` with only `CLAIM-AUTH`/`REVOKE-AUTH`. |

**Residual accepted states (documented, not fixable without custodial power):**
a beneficiary who loses their key loses access to vested funds — inherent to
non-custodial escrow; there is deliberately no admin sweep. A grant id can be
front-run squatted with a dust grant (victim's `create-grant` aborts on the
insert collision, retries with a fresh id; no funds at risk) — use
nonce-bearing ids.

## Threat model & defenses

| Vector | Defense | Test |
|---|---|---|
| Escrow created without funder consent | funder's own scoped `coin.TRANSFER` signature is the authorization; unscoped sig rejected | `create-grant-no-transfer-sig` |
| Claim by a non-beneficiary | `CLAIM-AUTH` enforces the guard enrolled at creation | `claim-wrong-key` |
| Claim signature reused across grants | `CLAIM-AUTH` is per-grant; sig scoped to another grant fails | `claim-sig-scoped-to-other-grant` |
| Claim before cliff / beyond vested | schedule math + `nothing claimable` gate | `claim-before-cliff`, double-claim cases |
| Over-claim via rounding | multiply-before-divide, floor to 12 dp, monotonic `claimed` | exact-amount asserts at days 90/182/end |
| Revoke by a non-funder | `REVOKE-AUTH` enforces the funder's live coin guard | `revoke-wrong-key` |
| Revoke stealing vested funds | refund = `total − max(vested, claimed)`; frozen remainder stays claimable | `revoke-g2`, `claim-after-revoke` |
| Cross-grant drain via clock rollback | the F1 clamp caps refund at the grant's own remaining escrow | `revoke-g6-clock-rollback` |
| Drain the vault directly | vault guard requires `SPEND`, acquired only inside `claim`/`revoke` | `vault-guard-denies` |
| Squat the beneficiary account | beneficiary must be its guard's principal; coin rejects foreign guards on principals | `squat-impossible`, vanity rejection |
| Unsatisfiable beneficiary guard (perma-lock) | only key-backed principals (`k:/w:/r:`) accepted | `c:` rejection case |
| Self-dealing to the vault | `create-grant` rejects the vault as beneficiary | vault-as-beneficiary case |
| Re-execute / double-pay | `claimed` settled before the transfer; status re-checked | `revoke-twice`, exhausted-grant cases |
| Governance seizure | no function composes with `GOV`; upgrade-only | capability sweep (both passes) |
| Value leak anywhere | conservation: suite ends with the vault at exactly `0.0` | `final-conservation` |

## Capability model

| Capability | Type | Guard | Notes |
|---|---|---|---|
| `GOV` | governance | `keyset-ref-guard GOV_KEYSET` | upgrade only; referenced by no function |
| `CLAIM-AUTH (id)` | authentication | enrolled beneficiary guard (read let-bound, then enforced) | acquired by `claim`; signers scope per grant |
| `REVOKE-AUTH (id)` | authentication | funder's **live** coin guard via `coin.details` | follows a funder key rotation; never revives an old key |
| `SPEND` | weak-body | — | Safe: acquired ONLY inside `claim`/`revoke` after their guard + amount checks; required by the vault guard; not externally acquirable (verified: an externally reconstructed vault guard canonicalizes to the same rejected principal) |
| `GRANT_CREATED` / `CLAIMED` / `REVOKED` | `@event` | — | emit-only audit trail |

## Node-safety

Every table read that feeds an `enforce` is bound first (`CLAIM-AUTH`,
`REVOKE-AUTH`, the claim/revoke amount checks); the clamp code introduced no
enforce-position reads. This class of bug is REPL-invisible on KDA-CE, so
**devnet validation of a full `create-grant → claim → revoke` cycle is the
required evidence** before production use — see the README deployment
checklist.

## Risk profile

| Risk | Level | Notes |
|---|---|---|
| Unauthorized claim/revoke | Low | per-grant scoped caps over enrolled/live guards, regression-tested |
| Over-payment / double-pay | Low | settle-before-transfer, monotonic `claimed`, floor-12 math |
| Cross-grant contamination | Low | refund clamp (F1); conservation proven to vault `0.0` |
| Direct vault drain | Low | capability-guarded principal; `SPEND` internal-only |
| Permanent fund lock | Low | principal + key-backed enforcement close all third-party vectors; residual = beneficiary key loss (inherent) |
| Governance dependency | Medium | upgrade power is ultimate power: pin the module hash, multi-sig the keyset |
| Clock manipulation | Low | block-time is consensus-produced; even a regression only triggers the clamp |

## Static analysis note

`pact-static-check.sh` reports **PASS, 0 violations**. A bare `pact <file>`
load cannot resolve the module's `coin` calls (missing-upstream-dependency
class, WARN-scoped to the known allowlist); the authoritative evidence is the
69-assertion `.repl` harness loading the real `coin`, plus the blocking CI
test step. The three Tier-2 `enforce-guard` WARNs are dispositioned SAFE —
all sit inside defcaps (`GOV`, `CLAIM-AUTH`, `REVOKE-AUTH`).

## What self-reviewed means here

Reviewed by the template's maintainers against the PCO checklist, with all
authorization/schedule/conservation scenarios encoded as runnable regression
tests, plus two independent `pact-auditor` passes (automated, fresh-context).
**Not independent human review.** Promotion requires a second reviewer
(`community-reviewed`) or a third-party report with a matching source hash
(`independently-audited`) — see `docs/CONTRACT_POLICIES.md` §3.1.

## Devnet validation (on-node evidence)

**Validated on a live KDA-CE devnet (recap-development) node, 2026-07-06.** The template was deployed under the
`free` namespace (governance keyset namespaced, per the deployment checklist)
and its critical paths were driven to mined confirmation with `@kadena/client`
— the required evidence for the REPL-invisible read-in-enforce class.

| | |
|---|---|
| Deployed module | `free.vesting` |
| Source hash | `PamnZMYjJl6lrYLyzxGV8UL96UoOolUnjU5Dol3MK3Y` |
| Confirmed transactions | 12 |

Proven on-node: `CLAIM-AUTH` (grants-read bound before `enforce-guard`) and `REVOKE-AUTH` (funder's **live** coin guard via `coin.details`); a full escrow → claim → revoke → frozen-remainder cycle conserved the vault, with foreign-key claim and non-funder revoke rejected on-node.

Reproduce: `scripts/devnet-validate` → `npm run vesting` (see that directory's README).

## Reproduce the review

```bash
cd contracts/library/vesting/examples
pact vesting-test.repl   # 69 assertions
```
