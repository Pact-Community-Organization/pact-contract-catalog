# Devnet Validation Campaign

On-chain validation of the PCO library templates against a **real KDA-CE devnet node** — the one evidence class the REPL cannot produce.

## Why this exists

Every library `AUDIT.md` carries the same caveat: a green REPL suite does not prove the on-chain path, because one class of KDA-CE bug — **a table read evaluated inside an `enforce` condition** — passes in the REPL but aborts on the node (`Operation is not allowed in read-only or system-only mode`). The templates are written to the node-safe pattern (bind the read to a local first, then enforce), but "written correctly" is not the same as "proven on a node." This campaign is that proof: it deploys each template to a devnet and drives the exact paths that exercise the node-only behavior.

## What each script proves

Each script deploys the template under the `free` namespace (governance keyset namespaced, exactly as the README's deployment checklist prescribes), then drives its critical paths with `@kadena/client`, polling every transaction to a mined block. The node-critical assertions per template:

| Template | Node-critical path exercised |
|---|---|
| `multisig-treasury` | `SIGNER-AUTH` binds a config read before `enforce`; `account-exists` `try`-reads coin; vault debits via the capability-guarded `SPEND` after a threshold-approved `execute`. |
| `vesting` | `CLAIM-AUTH` binds a grants read before `enforce-guard`; `REVOKE-AUTH` reads the funder's **live** coin guard via `coin.details`; escrow → claim → revoke conserves the vault. |
| `dao-voting` | `MEMBER-AUTH` binds a config read before `enforce`; propose → vote → **close after a real ~90s deadline** (chain-time polled, never slept). |
| `oracle-feed` | `PUBLISH-AUTH` binds a config read before `enforce`; the `get-price` median pipeline runs both via `/local` and inside a mined consumer tx; staleness fails closed against real block timestamps. |
| `token-fungible` | `DEBIT` let-binds the sender's stored guard (the v0.2.0 CRITICAL fix) — an authorized transfer succeeds, a foreign-key transfer is rejected, and rotation updates the guard the DEBIT reads. |
| `gas-station` | A **zero-KDA user** runs a real transaction the **station pays for** via `GAS_PAYER`: the allowlist read is bound before `enforce-guard`, spend is bounded/accounted against `(chain-data)` actual gas, and a non-enrolled user is denied. |

Each script also runs the negative cases (wrong key, non-member, below threshold, non-enrolled) to prove the guards reject on-node, not just in the REPL.

## Running

Requires a local KDA-CE devnet (default `http://localhost:8090`, network `recap-development`) with the genesis `sender00` faucet.

```bash
cd scripts/devnet-validate
npm install
npm run treasury      # or vesting | dao-voting | oracle-feed | token-fungible | gas-station
npm run all           # everything, sequentially
```

Environment overrides: `DEVNET_HOST`, `DEVNET_NETWORK_ID`, `DEVNET_CHAIN`.

Each run writes `results/<template>.json` (deployed module name, source hash, and every confirmed transaction's request key and gas) — the evidence cited in each template's `AUDIT.md`.

## Not covered

- **`nft-collection-policy`** requires the full marmalade-v2 stack (ledger, policy-manager, kip interfaces) deployed on the target devnet, which this shared devnet does not carry. Its REPL suite already runs against the **real** marmalade sources from the registry tree (stronger than a mock), and its specific devnet mandate — an on-chain **buy** through the sale defpact — is a follow-on for a marmalade-provisioned devnet. See that template's `AUDIT.md`.
- **`hello-world`** carries no node-only behavior (no table-read-in-enforce, no managed caps), so a devnet run adds nothing its REPL suite doesn't already show.
- **Cross-chain** paths (token `TRANSFER_XCHAIN`) need a multi-chain SPV exercise; the single-chain campaign does not cover them.
