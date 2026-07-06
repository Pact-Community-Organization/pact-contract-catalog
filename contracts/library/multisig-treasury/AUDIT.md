# AUDIT — library/multisig-treasury

## Summary

| Field | Value |
|---|---|
| **Module** | `treasury` (namespace: project-specific) |
| **Version** | 1.0.0 |
| **Audit Status** | self-reviewed |
| **Category** | PCO Library Template |
| **Source** | PCO-authored reference implementation |
| **Last review** | 2026-07-06 |

## Purpose

Deployable template for an M-of-N multisig treasury: KDA custody in a
capability-guarded vault, spendable only via an on-chain proposal that reaches an
approval threshold from an authenticated signer set.

## Audit history: findings and fixes

An independent `pact-auditor` pass returned **NO-GO** on the first version, with a
HIGH ship-stopper. All findings were fixed:

| # | Severity | Finding | Fix |
|---|----------|---------|-----|
| F1 | **HIGH** | `enforce-signer` read the `config` table **inside an `enforce` condition** (`(enforce (is-signer account) ...)`). This passes in the REPL but **aborts on the KDA-CE node** ("Operation is not allowed in read-only or system-only mode"). It gates both `propose` and `approve`, so on a real node no proposal could be created or approved — a funded vault could **accept KDA but never spend it** (funds locked). | `enforce-signer` now `let`-binds `(is-signer account)` before the `enforce`. Same fix applied to the new recipient-existence and vault-existence checks. |
| F2 | MEDIUM | `init` could be front-run bricked: anyone could pre-create the vault account, causing `init`'s `coin.create-account` to abort ("value already exists") and roll back the whole GOV setup. | `init` now creates the vault via `ensure-vault-account`, which skips creation if the account already exists (the vault guard is deterministic, so a pre-created vault necessarily carries the correct guard — coin enforces name==principal(guard)). |
| F3 | LOW | `propose` lacked `enforce-unit` and a recipient-existence check, so a proposal could reach threshold yet be un-executable (stuck `pending`), recoverable only by governance `cancel`. | `propose` now calls `coin.enforce-unit` and rejects a non-existent recipient at creation. |
| F4 | LOW | `init` emitted no event, unlike every other state transition. | `init` now emits `SIGNERS_ROTATED`. |
| F5 | INFO | Stale approvals survive a signer rotation (a proposal that met threshold under the old set can still execute). | Superseded by the R2-1 fix below: `execute` now drops rotated-out signers' approvals. |

> **F1 is REPL-invisible.** The fix (bind-before-enforce) is the verified remedy
> for this class, but a REPL pass is **not** evidence that it works on-node. A
> **devnet run of `propose`/`approve`/`execute` is mandatory** before any
> production use of this template — see the README deployment checklist. This is
> the single most important gate for this entry.

A **second** independent pass verified F1–F4 closed (F2 confirmed down to the
pinned interpreter source) and zero read-in-enforce remaining, but raised one
MEDIUM and two LOWs — all fixed:

| # | Severity | Finding | Fix |
|---|----------|---------|-----|
| R2-1 | **MEDIUM** | Signer rotation did not revoke recorded approvals — a rotated-out (e.g. compromised) signer's stale approval still counted toward the threshold, breaking the M-of-N guarantee in the exact scenario rotation exists for. | `execute` now counts **only** approvals from **current** signers: `(filter (lambda (a) (contains a current-signers)) approvals)` before the threshold check. Regression-tested (`stale-execute-blocked`: a rotated-out signer's approval no longer counts; execution requires a fresh current-signer approval). |
| R2-2 | LOW | Signer authentication was a bare defun, forcing signers to sign **unscoped** — their approval signature also authorized anything else their key could satisfy in the transaction. | `SIGNER-AUTH` is now a **capability**; `propose`/`approve` acquire it via `with-capability`, so signers scope their signature to `(treasury.SIGNER-AUTH "alice")`. Regression-tested (`scoped-sig-*`). |
| R2-3 | LOW | No duplicate-signer check — `["alice" "alice" "bob"]` with threshold 3 passed validation but could never reach 3 distinct approvals (silent N-of-M misrepresentation). | Shared `enforce-valid-config` (used by `init` and `rotate-signers`) now rejects duplicate signers via `(distinct signers)`. Regression-tested (`rotate-dup-signers`). |

A **third** pass returned **GO** (R2-1/2/3 all verified closed, node-safe, no
regression). It raised one residual LOW: approval identity is the account *name*,
so re-keying a signer **in place** (same name, new guard) revives any approvals
the old key made on still-pending proposals. **Disposition: documented** — the
README instructs responding to a key compromise by *removing the signer's name*
(and/or cancelling affected proposals), never swapping its guard in place. A
structural fix (per-approval rotation epoch) is noted for a future version.

## Threat model & defenses

| Vector | Defense | Test |
|---|---|---|
| Non-signer proposes/approves | `SIGNER-AUTH` cap checks set membership | `propose-non-signer`, `approve-non-signer` |
| Impersonate a signer by name | `SIGNER-AUTH` enforces the signer's enrolled guard | `propose-unauthenticated` |
| Spend below threshold | `execute` enforces `valid-approvals >= threshold` | `execute-under-threshold` |
| Inflate approvals by re-approving | per-signer dedup (`not (contains signer approvals)`) | `approve-double` |
| Double-spend / re-execute | status set to `executed` before transfer; re-entry re-checks `pending` | `re-execute` |
| Drain the vault directly | vault guard requires `SPEND`, acquired only inside `execute` after threshold | `vault-guard-denies` |
| Self-deal to the vault | `propose` rejects the vault as recipient | `propose-to-vault` |
| Execute a cancelled/settled proposal | status re-checked on entry | `execute-cancelled`, `approve-cancelled` |
| Non-governance cancel/rotate | `GOV` keyset gate | `cancel-requires-gov`, `init-requires-gov` |
| Rotated-out signer's stale approval counts | `execute` counts only current-signer approvals | `stale-execute-blocked` |
| Duplicate signers silently break N-of-M | `enforce-valid-config` rejects `distinct` mismatch | `rotate-dup-signers` |
| Signer approval sig authorizes bundled ops | `SIGNER-AUTH` is a cap; signers sign scoped | `scoped-sig-propose`, `scoped-sig-approve` |

## Capability model

| Capability | Type | Guard | Notes |
|---|---|---|---|
| `GOV` | governance | `keyset-ref-guard GOV_KEYSET` | init / rotate-signers / cancel / upgrade |
| `SIGNER-AUTH` | authentication | set membership + signer's enrolled guard | Acquired by `propose`/`approve`; signers scope their signature to it |
| `SPEND` | weak-body | — | Safe: acquired ONLY inside `execute` after the threshold check; required by the vault guard; not externally acquirable |
| `PROPOSED` / `APPROVED` / `EXECUTED` / `CANCELLED` / `SIGNERS_ROTATED` | `@event` | — | Emit-only audit trail |

The vault account guard (`vault-guard-pred`) is a user guard that requires `SPEND`
in scope. Since `SPEND` is composed only within `execute` — and only after
`(enforce (>= (length approvals) threshold) ...)` — coin can debit the vault only
through a threshold-approved execution.

## Authorization: the threshold is the trust boundary

`execute` is intentionally **permissionless** — once approvals meet the threshold,
anyone may trigger the settled transfer. This is standard for multisig: the M
approvals *are* the authorization, and letting any party (or a relayer) execute
avoids a liveness dependency on a specific signer being online. A single
compromised signer key cannot move funds — it can add at most one approval and
cannot lower the threshold (only governance can rotate).

## Node-safety

The first version tripped the KDA-CE "table read inside an `enforce` condition"
trap (F1 above). It is now fixed: every table read that feeds an `enforce` is
`let`/`with-read`-bound **first**, then the bound local is enforced
(`SIGNER-AUTH`, `propose` recipient check, `ensure-vault-account`, `execute`
threshold + current-signer filter). This class is REPL-invisible, so **devnet
validation is the required evidence** — see the F1 caveat above.

## Risk profile

| Risk | Level | Notes |
|---|---|---|
| Unauthorized spend | Low | Threshold + per-signer auth + dedup, all regression-tested |
| Double-spend | Low | Settle-before-transfer + status re-check |
| Direct vault drain | Low | Capability-guarded principal; `SPEND` internal-only |
| Reentrancy | Low | Only `coin.transfer` is external; status already settled before it |
| Governance dependency | Medium | `treasury-gov` must be defined pre-deploy; template ships an unqualified REPL name — **must** be namespace-qualified on-chain |
| In-flight proposals across rotation | Low | `execute` counts only current-signer approvals, so a rotated-out signer's stale approval is dropped (R2-1) |
| No proposal expiry | By design | Add a block-time deadline to `execute` if needed; documented |

## Static analysis note

`pact-static-check.sh` reports **PASS, 0 violations**. A bare `pact <file>` load
cannot resolve the module's `coin` calls (the standalone CLI ships only a stub of
`coin` lacking `get-balance`), so this class of missing-upstream-dependency load
error is treated as a WARN, scoped to a known allowlist of pre-deployed modules —
a typo against the module's *own* members still fails the gate as a VIOLATION. The
authoritative evidence is the full `.repl` harness (43 assertions green), which
loads the real `coin`, plus the blocking CI test step. The two Tier-2 WARNs
(`enforce-guard` in `GOV` and in `SIGNER-AUTH`) are dispositioned SAFE — both sit
inside defcaps.

## What self-reviewed means here

Reviewed by the template's maintainers against the PCO checklist, with all
authorization/threshold/double-spend scenarios encoded as runnable regression
tests. **Not independent.** Promotion requires a second reviewer
(`community-reviewed`) or a third-party report with a matching source hash
(`independently-audited`) — see `docs/CONTRACT_POLICIES.md` §3.1.

## Reproduce the review

```bash
cd contracts/library/multisig-treasury/examples
pact treasury-test.repl   # 43 assertions
```
