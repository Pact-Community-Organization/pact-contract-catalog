# Devnet Validation Report

Every library `AUDIT.md` states that a green REPL suite is not proof the
on-chain path works, because one class of KDA-CE bug — **a table read
evaluated inside an `enforce` condition** — passes in the REPL but aborts on a
real node. This report records the campaign that closed that caveat: each
deployable template was deployed to a **live KDA-CE devnet** and its
node-critical paths driven to mined confirmation.

**Date:** 2026-07-06 · **Network:** `recap-development` (KDA-CE devnet) ·
**Harness:** [`scripts/devnet-validate`](../scripts/devnet-validate/) (`@kadena/client`, every transaction polled to a block).

## Results

| Template | Status | Deployed module | Txs | What was proven on-node |
|---|:--:|---|:--:|---|
| [multisig-treasury](../contracts/library/multisig-treasury/) | ✅ PASS | `free.treasury` | 13 | `SIGNER-AUTH` bound read + `try`-read; vault debit via capability-guarded `SPEND` after threshold `execute`; negatives rejected. |
| [vesting](../contracts/library/vesting/) | ✅ PASS | `free.vesting` | 12 | `CLAIM-AUTH` bound read; `REVOKE-AUTH` live `coin.details` guard; escrow → claim → revoke conserved the vault. |
| [dao-voting](../contracts/library/dao-voting/) | ✅ PASS | `free.dao-voting` | 13 | `MEMBER-AUTH` bound read; propose → vote → close after a **real ~90s deadline**; settled `passed`. |
| [oracle-feed](../contracts/library/oracle-feed/) | ✅ PASS | `free.oracle-feed-v2` | 13 | `PUBLISH-AUTH` bound read; median pipeline in a **mined consumer tx**; staleness fail-closed vs real block time; rotation revocation. |
| [token-fungible](../contracts/library/token-fungible/) | ✅ PASS | `free.token-v2` | 10 | `DEBIT` stored-guard enforcement (the v0.2.0 CRITICAL fix): authorized transfer succeeds, **foreign-key transfer rejected**, rotate updates the enforced guard. |
| [gas-station](../contracts/library/gas-station/) | ✅ PASS | `free.gas-station` | 7 | A **zero-KDA user** ran a tx the **station paid for** via `GAS_PAYER`; spend bounded/accounted against `(chain-data)` actual gas; non-enrolled user denied. |
| [royalty-sale](../contracts/library/royalty-sale/) | ✅ PASS | `free.royalty-sale` | 13 | `buy` settlement on-node: **fresh escrow** (fund-then-plain-`let` baseline read, primary-sale payout merge, escrow → 0) and **dust-carrying escrow** (conservation returns to the donated baseline, not zero) — the auditor's F1 node-only class, proven. |
| [property-lease](../contracts/library/property-lease/) | ⏸ pending | — | — | Deployable but not yet driven: its `AUDIT.md` names a devnet run of `give-notice` plus the full create → deposit → rent → claim → settle cycle as **required evidence before any production use** (its F1 class is REPL-invisible). |
| [hello-world](../contracts/library/hello-world/) | n/a | — | — | No node-only behavior; the REPL suite is sufficient. |

Every deployed module's source hash and every confirmed transaction's request
key are recorded in the corresponding template's `AUDIT.md` (§ *Devnet
validation*).

## What this establishes — and what it doesn't

**Establishes:** the read-in-enforce class is closed for the seven driven
templates. Every `SIGNER-AUTH` / `CLAIM-AUTH` / `MEMBER-AUTH` / `PUBLISH-AUTH`
capability, the treasury/vesting/gas-station capability-guarded vaults, the
token's `DEBIT`, and the gas-station's full drain-defense executed correctly
on a real node, and every negative case was rejected on-node rather than only
in the REPL.

**Does not establish:** this is a single-chain functional validation, not an
independent audit and not a cross-chain exercise. It does not replace the
`community-reviewed` / `independently-audited` steps on the audit-status
ladder, and it does not cover the token's `TRANSFER_XCHAIN` SPV path (which
needs a multi-chain devnet). Templates remain `self-reviewed`; devnet
validation is corroborating evidence for the node-safety claim, cited as such.

The same harness also carries the [NFT Framework](../contracts/nft/README.md)'s
own campaign (`npm run nft-framework`) — a genuinely **multi-chain** run with
real SPV relocation; see
[scripts/devnet-validate/README.md](../scripts/devnet-validate/README.md). That
run does not close the token template's `TRANSFER_XCHAIN` gap above.

## Reproducing

```bash
cd scripts/devnet-validate
npm install
npm run all      # against a devnet on http://localhost:8090 (recap-development)
```

Findings surfaced by the campaign (all pre-existing template behavior,
confirmed correct on-node, now documented): a `k:` principal account cannot
rotate its guard (coin protocol) — token rotation demos use vanity accounts;
oracle publisher/feed names cannot contain `":"` — publishers are named
accounts, not `k:` principals (now noted in that README).
