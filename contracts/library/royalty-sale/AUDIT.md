# AUDIT — library/royalty-sale

## Summary

| Field | Value |
|---|---|
| **Module** | `royalty-sale` (namespace: project-specific) |
| **Version** | 1.0.0 |
| **Audit Status** | self-reviewed |
| **Category** | PCO Library Template |
| **Source** | PCO-authored reference implementation |
| **Last review** | 2026-07-06 |

## Purpose

A self-contained NFT + fixed-price royalty marketplace that owns both its token
ledger and its sale escrow — the hardened demonstration of the fixes proposed
in the PCO Marmalade V2 security & architecture analysis. Its correctness
*claims* (conservation, on-chain economics, fail-closed inputs, sale-only
enforcement) are the deliverable, so they were probed directly.

## What it demonstrates (mapped to the Marmalade analysis)

| Property | Marmalade finding it answers |
|---|---|
| Single settlement asserting `royalty + fee + proceeds == price` and that the escrow returns to its pre-sale balance; no hook holds escrow-spend authority | ARCH-1 (shared escrow sweep), POL-3 (policy reaches into escrow) |
| Royalty fixed on the token at mint; fee rate + payee fixed on the listing by the seller; `buy` takes no money parameter | ARCH-2 (caller-supplied marketplace fee) |
| Principal payout accounts, range-capped rates, no permissive defaults | POL-1 (fail-open guard defaults) |
| `transferable` is an explicit, immutable per-token opt-in; sale-only enforcement can't be composed away | POL-2 (blunt always-fail transfer lock) |
| Same-account payout merge (primary sale: creator == seller) | fund-lock + duplicate-managed-install classes |

## Audit history: findings and fixes

An independent `pact-auditor` pass returned **NO-GO** with two confirmed code
defects and one high-impact node-safety gap. All were fixed:

| # | Severity | Finding | Fix |
|---|----------|---------|-----|
| F1 | **HIGH (node-only)** | `buy` read the escrow baseline with `(try 0.0 (currency::get-balance ESCROW))` — a table read inside a `try`, a read-only context on the KDA-CE node. Same REPL-invisible class the module avoids elsewhere. On-node it could either abort every sale (if the node blocks the read) or, if caught, let a single dust donation to the *shared* escrow permanently break the baseline check (DoS). | `buy` restructured: fund the escrow **first** (the buyer's own signed transfer), then read the balance in a **plain `let`** (the account now exists — no `try`, no enforce-condition read), and prove conservation as `final-bal == funded-bal − price`. This is dust-donation robust (`funded = baseline + price` ⇒ `final == baseline`) and **validated on a live KDA-CE node** (see below). |
| F2 | MEDIUM | The `TRANSFERRED` event emitted `(TRANSFERRED id receiver receiver)` — the sender was lost, corrupting provenance. | Capture the prior owner before the update; emit `(TRANSFERRED id from receiver)`. Regression-tested. |
| F3 | LOW | `mint` did `(enforce-guard owner-guard)` in a bare defun, forcing the minter to sign **unscoped** — a signature-reuse foot-gun in a template others copy. | Added a `MINT-AUTH (owner-guard)` capability; `mint` acquires it, and the suite's mints now sign scoped to `(MINT-AUTH …)`. |
| F5 | LOW | Payouts ran before the ownership/listing updates (safe only via the Pact 5.3+ reentrancy guard, not "atomic" as the comment claimed). | Reordered to checks-effects-interactions: the listing is closed and ownership flipped **before** the payouts; comment corrected. |
| F6 | INFO | `enforce-unit` called `(currency::precision)` inside an `enforce` condition — node-safe for `coin` but latent for an arbitrary fungible. | Bind precision before the enforce. |
| F7 | INFO | The `royalty + fee + proceeds == price` assert was tautological (proceeds is defined as the difference). | Removed; the substantive conservation proof is the escrow-baseline check. |
| F4 / F8 | LOW / INFO | Donated funds sent directly to the shared escrow are stranded (no sweep); a seller-chosen malicious `currency` is trusted at buy time. | Documented as intentional/known limits (README): don't send to the escrow directly; trade only in trusted currencies. Conservation still holds over a dust-carrying escrow (regression-tested + devnet-proven). |
| F9 | — | Coverage gaps (donation, `marketplace==seller/creator` merges, transfer-while-listed, non-owner-delist). | Added: provenance, transfer-while-listed rejection, non-owner-delist rejection, `marketplace==seller` merge, and the escrow-dust-donation conservation regression. |

## Devnet validation (on-node evidence for F1)

The F1 class is **REPL-invisible**, so it was validated on a live KDA-CE devnet
(`recap-development`) via `scripts/devnet-validate` (`npm run royalty-sale`).
Both node-critical cases of the fix were driven to mined confirmation:

- **Fresh escrow (first sale):** `buy` funds the escrow, reads its balance in a
  plain `let`, settles (creator + marketplace + seller, with the primary-sale
  merge), and the escrow returns to `0` — proving the read is node-safe and the
  settlement conserves on-node.
- **Dust-carrying escrow:** a griefer donates dust to the shared escrow; the
  next `buy` still settles and the escrow returns to its dust **baseline**
  (not zero) — proving the conservation check is donation-robust on-node, not
  just in the REPL.

Module name, source hash, and confirmed request keys are recorded in
`scripts/devnet-validate/results/royalty-sale.json`.

## Threat model & defenses

| Vector | Defense | Test |
|---|---|---|
| Value stranded in / conjured from the escrow | single settlement; `final-bal == funded-bal − price`; payouts sum to price | conservation cases + odd-price dust + devnet |
| Buyer zeroes the royalty/fee | royalty fixed at mint, fee fixed at listing; `buy` has no money argument | listing-validation + economics-from-state |
| Primary-sale self-payout collision | same-account payouts merged before disbursing | primary-sale + `marketplace==seller` merges |
| Squatted payout account bricks a sale | creator / seller / buyer / marketplace must be principals | fail-closed mint + list validation |
| Escrow drained outside a sale | `SPEND` weak cap acquired only inside `buy`; escrow guard requires it | (structural; auditor-verified no external path) |
| Non-owner lists / delists / transfers | `OWNER` capability over the enrolled guard | non-owner list + non-owner delist |
| Sale-only token moved without paying royalty | `transfer` rejects non-transferable; `buy` (which always pays) is the only other path; `transferable` immutable | sale-only reject + end-to-end enforcement |
| Reentrancy on a live listing | checks-effects-interactions: listing closed before payouts | (structural) |

## Capability model

| Capability | Type | Guard | Notes |
|---|---|---|---|
| `GOV` | governance | `keyset-ref-guard GOV_KEYSET` | upgrade only; no fund path |
| `MINT-AUTH (owner-guard)` | authentication | the enrolled owner guard | minter signs scoped |
| `OWNER (id)` | authentication | enrolled owner guard (read in `enforce-guard` arg position) | list / delist / transfer |
| `SPEND` | weak-body | — | Safe: acquired ONLY inside `buy`'s settlement; guards the escrow; pays out exactly what the buyer paid in (asserted); not externally acquirable |
| `MINTED`/`LISTED`/`DELISTED`/`SOLD`/`TRANSFERRED` | `@event` | — | emit-only audit trail |

## Node-safety

Every table read that feeds an `enforce`/`enforce-one` condition is bound to a
local first: `OWNER` reads in `enforce-guard` argument position; `is-listed` is
bound before its enforce in `transfer`; the conservation read (`funded-bal`,
`final-bal`) is a plain `let` after the escrow is funded — the F1 fix. This
class is REPL-invisible, and for this template it is **devnet-proven** (above),
which is the required evidence.

## Risk profile

| Risk | Level | Notes |
|---|---|---|
| Conservation break | Low | asserted per sale; dust-robust; devnet-proven |
| Escrow drain / free-mint | Low | `SPEND` internal-only, bounded by the buyer's deposit |
| Fund lock | Low | principal payees + payout merge; donated dust to the escrow is a documented terminal state |
| Royalty bypass | Low | sale-only immutable; no non-paying move path |
| Governance dependency | Medium | upgrade power: pin the module hash, multi-sig the keyset |

## Static analysis note

`pact-static-check.sh` reports **PASS, 0 violations**. The `enforce-guard`
WARNs are dispositioned SAFE: inside `GOV`, `MINT-AUTH`, and `OWNER` defcaps,
and the guard-enrollment points. The bare-load WARN is the `fungible-v2` modref
that resolves in the full harness.

## What self-reviewed means here

Reviewed by the template's maintainers against the PCO checklist, with the
conservation and settlement claims encoded as runnable regression tests, an
independent `pact-auditor` pass whose blocking findings are all fixed, and an
on-chain devnet validation of the node-only settlement path. **Not independent
human review.** Promotion requires a second reviewer (`community-reviewed`) or
a third-party report with a matching source hash (`independently-audited`) —
see `docs/CONTRACT_POLICIES.md` §3.1.

## Reproduce the review

```bash
cd contracts/library/royalty-sale/examples
pact royalty-sale-test.repl        # 46 assertions
# on-node (F1):
cd ../../../../scripts/devnet-validate && npm run royalty-sale
```

The economic follow-up — a full-marketplace simulation (resale chain,
multi-currency, adversarial sweep, global conservation) — is documented in
[SIMULATION.md](SIMULATION.md) (`examples/royalty-sale-market-sim.repl` +
`npm run royalty-sale-sim`).
