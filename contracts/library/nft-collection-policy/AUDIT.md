# AUDIT — library/nft-collection-policy

## Summary

| Field | Value |
|---|---|
| **Module** | `nft-collection-policy` (namespace: project-specific) |
| **Version** | 1.0.0 |
| **Audit Status** | self-reviewed |
| **Category** | PCO Library Template (marmalade-v2 concrete policy) |
| **Source** | PCO-authored reference implementation |
| **Last review** | 2026-07-06 |

## Purpose

Deployable marmalade-v2 concrete policy (implements `kip.token-policy-v2`) for
NFT collections: creator-gated token creation and minting, a collection size
cap, strict one-of-one NFT shape, opt-in burning. Custodies nothing — the
marmalade ledger holds tokens; this policy only decides what is allowed.

## Audit history

An independent `pact-auditor` pass returned **GO** — zero
CRITICAL/HIGH/MEDIUM/LOW findings; three INFO items, dispositioned below. The
review drove the policy through the **real** marmalade-v2 registry stack and
included two adversarial probe suites (hook reachability, state corruption),
both passing.

**The core security claim was empirically proven:** every one of the seven
policy hooks is gated by `require-capability` on the policy-manager's
corresponding `*-CALL` capability. External/top-level acquisition of those
caps is refused by Pact (`Module admin necessary`), signature-scoping to them
does not grant them, and the policy's rendered `POLICY` name matches what the
policy-manager passes under any namespace. Hooks are unreachable outside the
genuine ledger → policy-manager flow.

**All seven hooks' `require-capability` argument lists were verified against
the policy-manager source** — including `BUY-CALL`, whose path the REPL suite
cannot exercise (quote/escrow machinery). An argument-order mistake there
would brick every sale at the buy step invisibly; the order is confirmed
correct (id, seller, buyer, amount, sale-id, policy).

| # | Severity | Finding | Disposition |
|---|----------|---------|-------------|
| 1 | INFO | The creator's `enforce-guard` runs in the hook defuns (the standard marmalade concrete-policy pattern), so an **unscoped** creator signature authorizes their guard for the whole transaction. Not exploitable by others (proven: non-creators fail the guard). | Documented: README instructs creators to scope create-token/mint signatures to the ledger's `INIT-CALL`/`MINT-CALL`; the suite demonstrates the exact shape. |
| 2 | INFO | `size` counts tokens **created** and never decrements on burn — a max-N collection can only ever contain N distinct token ids, even if some are burned. | Intended; documented explicitly in the README security model. |
| 3 | INFO | Mint/burn emit no policy-level event (only `TOKEN-ADDED` at init). The ledger's `RECONCILE`/`TOKEN` events fully cover the audit trail. | Accepted — duplicating ledger events adds gas for no new information. Indexers should key off ledger events. |

## Probe results (auditor artifacts, reproduced then removed from the tree)

- **Hook reachability**: `POLICY` const == manager's rendering under any
  namespace; top-level `with-capability` of a `*-CALL` cap refused;
  a signature scoped to `INIT-CALL` still fails the hook's
  `require-capability`. No bypass.
- **State corruption**: collection `size` shows no phantom drift when a
  create-token aborts mid-transaction (atomicity); listing this policy twice
  in a token's policy list fails cleanly with size unchanged; a mint cannot
  re-home a token to another collection (`collection_id` tx data is only read
  at init — mint uses the stored binding).

## Threat model & defenses

| Vector | Defense | Test |
|---|---|---|
| Direct call to any policy hook | `require-capability` on the policy-manager's `*-CALL` caps | `direct-hook-calls-blocked` (all 7) |
| Fake ledger / hostile module drives hooks | `*-CALL` caps acquirable only inside the genuine policy-manager | auditor reachability probe |
| Non-creator adds tokens to a collection | `enforce-guard` on the enrolled creator guard at init | `create-token-non-creator` |
| Non-creator mints | creator guard enforced at mint | `mint-non-creator` |
| Supply > 1 (fractional, re-mint, mint-after-burn) | precision 0 at init; amount exactly 1.0; one-way minted flag | `mint-bad-amount`, double-mint, `burn-burnable-then-no-remint` |
| Collection cap bypass | `size` incremented transactionally at init; `max-size` checked on bound locals | `collection-full`, auditor abort-atomicity probe |
| Cross-collection contamination | token→collection binding stored at init; mint/burn use the stored binding | auditor cross-collection probe |
| Non-owner transfer / burn | ledger's managed `TRANSFER` / `BURN`→`DEBIT` guard enforcement | `transfer-t1`, burn cases |
| Burning where not intended | per-collection `burnable` opt-in | `burn-non-burnable` |
| Governance seizure of collections | `GOV` is upgrade-only; touches no collection/token state | capability sweep |

## Capability model

| Capability | Type | Guard | Notes |
|---|---|---|---|
| `GOV` | governance | `keyset-ref-guard GOV_KEYSET` | upgrade only |
| `CREATOR-AUTH (guard)` | authentication | `enforce-guard` on the supplied guard | acquired by `create-collection`; scoped-sig friendly |
| `COLLECTION` / `TOKEN-ADDED` | `@event` | — | emit-only |
| (external) `marmalade-v2.policy-manager.*-CALL` | gate | acquirable only inside the policy-manager | the hooks' only entry path |

## Node-safety

Every table read feeding an `enforce` is let/with-read-bound first
(`enforce-init`, `enforce-mint`, `enforce-burn`); `read-msg "collection_id"`
is env-data, not a table read. Swept clean by both the author and the
auditor. This class is REPL-invisible on KDA-CE, so **devnet validation
against the real marmalade-v2 deployment is required evidence** — including
specifically an on-chain **buy** (the REPL suite exercises offer/withdraw
positively but cannot cover the quote/escrow buy path).

## Risk profile

| Risk | Level | Notes |
|---|---|---|
| Unauthorized mint/creation | Low | creator guard + `*-CALL` gates, probe-verified |
| Supply inflation | Low | one-way minted flag + amount/precision invariants |
| Policy-state corruption | Low | module-scoped tables; tx atomicity probe-verified |
| Sale-path defect | Medium→Low | buy arg-order statically verified; devnet buy exercise mandated before relying on sales |
| Governance dependency | Medium | upgrade power: pin the module hash, multi-sig the keyset |

## Static analysis note

`pact-static-check.sh` reports **PASS, 0 violations**. WARNs dispositioned:
bare-load env-data warnings are the namespace/`read-msg` load ceremony
(the full harness is authoritative); the `enforce-guard` warnings sit either
in defcaps (`GOV`, `CREATOR-AUTH`) or inside `require-capability`-gated hooks
(Finding 1 above).

The suite loads real registry snapshots plus two **test-support interface
stubs** (`examples/support/`) for kip interfaces pre-deployed on-chain but not
yet snapshotted; the auditor confirmed both are pure interfaces (no state, no
executable bodies) whose signatures match the registry sources' usage — they
cannot alter behavior under test.

## Devnet validation status

Unlike the other library templates, this one is **not** part of the on-node
devnet validation campaign (`scripts/devnet-validate`): a concrete policy is
inert without a live marmalade-v2 deployment (ledger + policy-manager + kip
interfaces), which the shared campaign devnet does not carry. Two points make
this acceptable, not a gap:

1. This template's REPL suite already loads the **real** marmalade-v2 sources
   from the registry tree and drives the policy through the genuine ledger —
   stronger evidence than any mock, and it exercises the same node-safety
   pattern (every table read is bound before its `enforce`).
2. The template's own outstanding devnet mandate is specific and narrower than
   the read-in-enforce class: an on-chain **buy** through the sale defpact
   (the quote/escrow path the REPL cannot cover). That is a follow-on for a
   marmalade-provisioned devnet — see "Known limits" in the README.

## What self-reviewed means here

Reviewed by the template's maintainers against the PCO checklist, driven
through the genuine marmalade-v2 stack with attack scenarios as runnable
regression tests, plus an independent `pact-auditor` pass (automated,
fresh-context) returning GO. **Not independent human review.** Promotion
requires a second reviewer (`community-reviewed`) or a third-party report with
a matching source hash (`independently-audited`) — see
`docs/CONTRACT_POLICIES.md` §3.1.

## Reproduce the review

```bash
cd contracts/library/nft-collection-policy/examples
pact nft-collection-policy-test.repl   # 38 assertions against the real marmalade-v2 stack
```
