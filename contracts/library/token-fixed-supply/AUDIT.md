# AUDIT — library/token-fixed-supply

## Summary

| | |
|---|---|
| Version | 1.0.0 |
| Audit status | `self-reviewed` (see §What self-reviewed means here) |
| Review | Independent adversarial review, fresh context, 2026-07-18 |
| Verdict | **GO** — 0 CRITICAL / 0 HIGH / 0 MEDIUM; 1 LOW + 2 INFO, all dispositioned below |
| Suite | `examples/fixed-supply-token-test.repl` — green, assertion-honesty verified by the reviewer |
| Static analysis | 0 VIOLATIONs; all WARNs dispositioned (enforce-guard positions are defcap bodies or the deliberate rotate pattern) |

## Purpose

A fixed-supply, non-upgradeable `fungible-v2` token: one-shot exact-distribution
mint gated by a deploy-time keyset, self-burn as the only supply change, no
admin surface, single-chain. The security claim under review: **after the one
mint transaction, no party — including the deployer — holds any authority
beyond that of an ordinary holder.**

## Capability model (reviewer's summary)

> Authority in `fixed-supply-token` is fully capability-scoped and frozen.
> Governance (`GOV`) is an unsatisfiable `(enforce false)`, so the module is
> non-upgradeable and no operational function composes with it. Value movement
> is gated by a managed `TRANSFER` capability (budget manager enforces
> remainder ≥ 0) that composes a real `DEBIT` guard (`enforce-guard` of the
> sender's stored account guard) with an internal weak-body `CREDIT` token;
> `CREDIT` is never acquired on a public path — only under `TRANSFER` or the
> one-shot `MINT`, both of which enforce a real guard upstream — so it is an
> internal permission token, not public authorization (verified: direct
> `credit`/`debit`, external `with-capability`, and `install-capability` on
> `CREDIT` all fail). Minting is a single `init-mint` guarded by the
> deploy-time `token-minter` keyset and made one-shot by a singleton
> supply-row `insert`; the distribution must sum to exactly `TOTAL-SUPPLY`,
> after which the minter is powerless. Burning is self-only under the
> account's own guard and is the sole way supply decreases. The reserved-name
> protocol pins `k:`/`w:`/`r:` accounts to their principal guard (no
> principal-name squatting); guard rotation is authorized by a dedicated
> `ROTATE` capability enforcing the account's current stored guard (so
> wallets can scope a signature to exactly one rotation), and principal
> accounts cannot rotate their guard away. No table read occurs inside any
> `enforce` condition, so no REPL-vs-node divergence class is present.

The `ROTATE` capability was added post-initial-review (cross-template parity
with the governance sibling) and re-verified by the same reviewer: nine
targeted probes on the new surface (scope confinement per account, no
privilege bleed from other caps, unscoped compatibility, module-external
acquisition rejected), original probe batteries re-run, verdict unchanged.

## Findings and dispositions

| # | Sev | Finding | Disposition |
|---|---|---|---|
| F1 | LOW | `init-mint` griefing: a pre-created vanity recipient name under a foreign guard aborts the whole mint (no value at risk; principal names immune). | Documented in `init-mint` `@doc` and README §Deployment: distribute to principal (`k:`/`w:`) accounts, or mint in the deploy transaction. No code change (the abort is the correct behavior). |
| F2 | INFO | `read-integer 'precision` coerces decimals by rounding — `12.4` deploys silently as `12`. Operator's own tx data, irreversible deploy footgun. | Documented in README §Known limits: send deploy parameters as exact JSON numbers. |
| F3 | INFO | Non-principal vanity names are first-come (standard fungible-v2 behavior; squatter denies only the name string, never value). | Documented in README §Known limits. |

## Attacks attempted and defeated (reviewer-executed probes)

- Free-mint via the weak `CREDIT` capability: direct `credit`/`debit` fail
  `require-capability`; external `with-capability (CREDIT …)` fails
  `Module admin necessary`; `install-capability` fails `not managed`.
- Second mint: blocked by the singleton supply-row insert.
- Under/over-distribution: blocked by the exact-sum enforce.
- Managed-budget overrun, self-transfer, precision dust, insufficient funds:
  all rejected at capability acquisition or pre-write enforce.
- `k:` squatting and re-guarding an existing account via `transfer-create`:
  rejected by the reserved-name protocol and the credit guard match.
- Principal guard rotation: rejected.
- Scoped-signature misuse (TRANSFER-scoped sig used for rotation): rejected.
- Node-vs-REPL divergence sweep: all 21 `enforce` conditions use pre-bound
  values; guard reads occur only in `enforce-guard` argument position
  (devnet-proven-safe pattern).

## Liveness

The only value store is per-account balances; exit paths (`transfer`,
`transfer-create`, `burn`) are holder-guarded and compose with nothing
admin-gated. Nothing is frozen-but-load-bearing; tables are created in the
deploy transaction (required — `GOV` can never grant admin again).

## What self-reviewed means here

The review was adversarial and independent of the implementation session
(fresh context, cold read, reviewer-authored probe harnesses), but it was
performed within the PCO — no external party has reviewed this code. Per the
catalog's audit-status ladder (docs/CONTRACT_POLICIES.md §3.1) that is
`self-reviewed`, not "audited". A qualifying independent community review
promotes the entry.

## Reproduce the review

```bash
cd examples && pact fixed-supply-token-test.repl   # suite green
pact --check-shadowing ../fixed-supply-token.pact  # clean (needs deploy env-data)
```

REPL discipline note for reviewers extending the suite: in Pact 5.4 REPL,
`expect-failure` does NOT roll back the failed action's partial writes, and
`expect-failure` around `load` corrupts repl state — put write-capable
negative cases in their own transactions ended with `(rollback-tx)`, and
verify bad-deploy aborts manually.
