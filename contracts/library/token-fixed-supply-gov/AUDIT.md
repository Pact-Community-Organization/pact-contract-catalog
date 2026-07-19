# AUDIT — library/token-fixed-supply-gov

## Summary

| | |
|---|---|
| Version | 1.0.0 |
| Audit status | `self-reviewed` (see §What self-reviewed means here) |
| Review | Independent adversarial review, fresh context, 2026-07-18 |
| Initial verdict | NO-GO as written: 1 MEDIUM (F1) + 2 LOW (F2, F3) |
| Final verdict | **GO** after the reviewer-prescribed F1/F2 fixes landed and the suite re-ran green; F3 documented |
| Suite | `examples/fixed-supply-token-gov-test.repl` — green; worst-case governance-loaded transfer gas measured AND asserted (489 ≪ 150k) |
| Static analysis | 0 VIOLATIONs; WARNs dispositioned (guard enforcement lives in defcap bodies) |

## Purpose

The fixed-supply, non-upgradeable token extended with **advisory** governance:
proposals + live balance-weighted voting with permanent tallies and **no
execution surface**. Claims under review: tallies can never be forged or
amplified; sold/moved/burned tokens can never keep voting; the public
`release-votes` sync is harmless; governance load on transfers is bounded;
closed tallies are immutable.

## Capability model (reviewer's summary, post-fix, re-verified)

> The module's authority model is minimal and terminal: `GOV` is
> unsatisfiable (`enforce false`), so no upgrade, admin, or table-creation
> surface exists after the deploy transaction. All value movement flows
> through the managed `TRANSFER` capability (linear budget via
> `TRANSFER-mgr`), composing `DEBIT` — the sender's own account guard — with
> the weak-body internal `CREDIT` token; `credit`, `debit`, and
> `cast-vote-internal` are sealed behind `require-capability`, and `CREDIT`
> is only ever acquired under a real upstream guard (the one-shot `MINT`
> keyset, made unrepeatable by the supply-row insert, or `TRANSFER`'s debit
> guard), so no free-mint path exists. Every user-facing authorization —
> `TRANSFER`, `BURN`, `ROTATE`, `PROPOSE`, and per-proposal `VOTE` — enforces
> the account's own guard inside a capability body, so wallets can sign with
> capability-scoped signatures throughout and never need to expose an
> unscoped key. Governance adds no authority at all: tallies derive
> exclusively from real balances (weight = current balance, shrink-only
> public sync on every balance decrease, credits never vote), the proposal
> threshold is deploy-enforced positive, and no capability, function, or
> module surface consumes a tally — votes are permanently recorded advisory
> signals with no execution lever. Independently exercised attack harnesses
> (vote-transfer-revote cycles, hostile syncs, scoped-signature spoofing,
> degenerate deploy parameters, worst-case governance-loaded gas at
> 489/150,000) produced no violation.

## Findings and dispositions

| # | Sev | Finding | Disposition |
|---|---|---|---|
| F1 | **MED** | Voting/proposing/rotation used bare `enforce-guard` in defun bodies — capability-scoped signatures could never satisfy them, forcing every voter to sign UNSCOPED (a wallet-security anti-pattern a public template would teach). | **FIXED** as prescribed: `PROPOSE`/`VOTE`/`ROTATE` defcaps added; write paths wrapped; `cast-vote-internal` sealed with `require-capability`. Suite now proves scoped-sig proposing and voting positively, plus the negative (attacker key carrying a scoped VOTE cap for another account still fails). Base template got `ROTATE` for parity. |
| F2 | LOW | `proposal-threshold` could floor to 0.0 under legal deploy parameters (e.g. precision 0, small supply, minimum fraction), silently letting zero-balance accounts propose. Reviewer-proven in a probe. | **FIXED** as prescribed: `PROPOSAL-THRESHOLD` is a load-time defconst with `(enforce (> t 0.0))` — the degenerate parameter combination now refuses to deploy. |
| F3 | LOW | Proposal-slot squatting: a threshold-holder can occupy all 3 active slots with 720h windows and race re-grabs at expiry, crowding the advisory channel. Recoverable, contestable, advisory-only. | Documented in README §Known limits (including the gov-threshold sizing advice). Per-account limits/deposits left to forks — a deliberate simplicity trade-off. |
| F4 | INFO | `release-votes` mutates tallies without an event; indexers must replay transfers/burns against the open set to reconstruct tallies. | Documented here. No event added: a per-shrink event would charge every transfer for indexer convenience, and the source-of-truth tallies are always readable on-chain (`get-proposal`/`get-results`). |
| F5 | INFO | Suite's gas measurement was not worst case (1 live vote, not 3). | **FIXED**: suite votes on all 3 open proposals, measures 489 gas, and asserts the bound instead of printing it. |
| F6 | INFO | Duplicated fungible core under-covered vs the base suite (no crosschain/rotate checks). | **FIXED**: crosschain-disabled assertion + rotate coverage (scoped-sig vanity rotate, principal-rotation rejection) added. |
| F7 | INFO | No AUDIT.md at review time. | This file. |
| F8 | INFO | Closed pids persist in `gov-actives` until the next `create-proposal` prunes (≤3 stale reads per transfer meanwhile; self-heals). | Accepted as-is; cosmetic, provably bounded. |

## Attacks attempted and defeated (reviewer-executed)

- **Vote→transfer→re-vote double-count** across split accounts and circular
  transfers: tally always equals the sum of voters' current balances; never
  amplified; tally ≤ circulating supply held throughout. Release is computed
  on the **post-debit** balance.
- **Hostile `release-votes`**: no-op on healthy and nonexistent accounts
  (byte-identical state); the shrink math cannot underflow a tally column
  (column = Σ row-weights maintained in lockstep).
- **Tally-freeze bypass**: no post-close write path; `cast-vote` and
  `open-ids` use the same strict time bound, so no closed-but-mutable window.
- **Index wedge**: proposal insert + active-index write are same-tx atomic;
  the stored index is provably ≤ 3 entries; `open-ids`' filter can never read
  a missing row.
- **vkey forgery**: digit-only pids + reserved-name account rules make
  `"<pid>:<account>"` keys unambiguous.
- **Free-mint / squat / rotation / managed-budget attacks** on the duplicated
  core: as the base template (see its AUDIT.md); shared core diffed against
  the base — byte-identical except the two `release-votes` call sites.
- **Node-vs-REPL divergence**: every enforce condition uses pre-bound values;
  guard reads only in `enforce-guard` argument position.

## Liveness

Transfers and burns are holder-guarded, compose with no governance state
beyond the bounded (≤3, 489-gas) release work, and can never be wedged by
proposals. Closed proposals, vote rows, and the supply row persist forever by
design (the permanent record is the product). No trapped value.

## What self-reviewed means here

Adversarial and independent of the implementation session (fresh context,
cold read, reviewer-authored probe harnesses for scoped signatures, the
zero-threshold edge, and worst-case gas), but performed within the PCO. Per
docs/CONTRACT_POLICIES.md §3.1 that is `self-reviewed`, not "audited". A
qualifying independent community review promotes the entry.

## Reproduce the review

```bash
cd examples && pact fixed-supply-token-gov-test.repl   # suite green, gas asserted
```

Same REPL discipline note as the base template: `expect-failure` does not
roll back partial writes and cannot wrap `load` — negative write-capable
cases live in `(rollback-tx)` transactions; bad-deploy aborts (including the
zero-threshold refusal) are verified manually.
