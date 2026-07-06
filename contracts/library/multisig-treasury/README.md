# Multisig Treasury (M-of-N)

PCO library template: an **M-of-N multisig treasury** for custody of KDA under threshold control. Funds live in a module-owned vault that can be spent **only** through an on-chain proposal that collects approvals from a threshold of authorized signers. This is the primitive every DAO, foundation, and company treasury needs first.

## How it works

Funds sit in a **capability-guarded vault account** (a principal whose guard is satisfied only while the internal `SPEND` capability is in scope). `SPEND` is acquired **only** inside `execute`, and only after the on-chain approval count meets the threshold. So the vault can be debited only by a threshold-approved proposal — never directly.

The flow is **asynchronous** — signers approve in separate transactions, no co-signing ceremony required:

1. **`init [signers] threshold [guards]`** (governance) — configure the signer set, the M-of-N threshold, and each signer's authenticating guard; create the vault account.
2. **`propose id proposer recipient amount`** — any signer proposes a spend. The proposer counts as the first approval. `id` must be unique.
3. **`approve id signer`** — another signer adds their approval. Each signer may approve at most once; a signer cannot approve a settled proposal.
4. **`execute id`** — once approvals ≥ threshold, **anyone** may execute; the approvals are the authorization. The vault debits the recipient exactly once and the proposal is marked `executed`.
5. **`cancel id`** (governance) — cancel a pending proposal.
6. **`rotate-signers [signers] threshold [guards]`** (governance) — replace the signer set / threshold.

Every step emits an event (`PROPOSED`, `APPROVED`, `EXECUTED`, `CANCELLED`, `SIGNERS_ROTATED`) for off-chain audit.

## Security model

- **Authenticated signers.** A signer isn't just a name in a list — `propose`/`approve` acquire the `SIGNER-AUTH` capability, which enforces the signer's enrolled guard. Signers scope their signature to `(treasury.SIGNER-AUTH "alice")`, so an approval signature does not also authorize other operations their key could satisfy in the same transaction.
- **Threshold is the authorization, over the *current* signer set.** `execute` counts only approvals from signers who are current at execution time, and is permissionless once that count meets the threshold. A compromised single key cannot move funds below threshold, and rotating a signer out drops their stale approvals.
- **No direct vault access.** The vault guard requires `SPEND`, which is acquirable only inside `execute` after the threshold check. A direct `coin.transfer` from the vault fails.
- **No double-spend.** `execute` marks the proposal `executed` before the transfer and re-checks `pending` on entry, so a proposal settles at most once.
- **No self-dealing to the vault.** `propose` rejects the vault as recipient.

## Deployment checklist

1. Wrap the module in your namespace; replace the `"treasury-gov"` keyset with your deployed, namespace-qualified governance keyset (**multi-sig recommended** — governance can rotate signers and cancel proposals).
2. Deploy, then call `(init signers threshold guards)` **once** with your signer accounts and their guards (positionally aligned).
3. **Fund** the vault with KDA (`get-vault-account` returns its name).
4. Validate the end-to-end flow on **devnet** before mainnet — **mandatory**, not optional (see Known Limits; on-chain table-read behavior cannot be proven in the REPL).

## Usage

```pact
;; a signer proposes (signs with their own key)
(treasury.propose "spend-2026-01" "k:alice..." "k:vendor..." 500.0)

;; another signer approves (signs with their own key)
(treasury.approve "spend-2026-01" "k:bob...")

;; once threshold reached, anyone executes
(treasury.execute "spend-2026-01")
```

## Testing

`examples/treasury-test.repl` is self-contained (loads `coin` + interfaces from `registry/`):

```bash
cd contracts/library/multisig-treasury/examples && pact treasury-test.repl
```

43 assertions covering the full 2-of-3 flow and every authorization/threshold attack: non-signer propose/approve, proposing as a signer without its guard, double approval, execute below threshold, re-execution, self-dealing to the vault, executing/approving a cancelled proposal, the vault guard denying a direct debit, and governance-gated cancel + signer rotation. CI runs this suite as a blocking check.

## Known limits

- **Devnet validation is MANDATORY before mainnet — not optional.** Several correctness checks (signer/recipient/vault existence) read on-chain tables. The template binds every such read before its `enforce` (the node-safe pattern), but this class of bug is **invisible in the REPL** — a green test suite does not prove the on-chain path works. Deploy to a devnet node and drive a full `propose → approve → execute` cycle before trusting this with real funds.
- **Proposal `id`s are caller-supplied and must be unique** — `propose` uses `insert`, so a reused id aborts. Use a scheme like `"<purpose>-<nonce>"`.
- **Rotating signers revokes rotated-out signers' approvals.** `execute` counts only approvals from *current* signers, so a proposal loses any approval from a signer removed by a later rotation and must re-reach the threshold among the current set. (It does not expire on its own — see next.)
- **Respond to a key compromise by REMOVING the signer's account name, not re-keying it in place.** Approval identity is the account name. Rotating a signer *out* drops their stale approvals, but re-enrolling the *same name* with a new guard revives any approvals the old (compromised) key made on still-pending proposals. When responding to a compromise, remove the name from the signer set (and/or `cancel` affected pending proposals) rather than swapping its guard under the same name.
- **No per-proposal expiry.** Add a deadline (block-time) check to `execute` if you want proposals to lapse.
- Governance holds absolute power (rotate signers, cancel, upgrade). Use multi-sig.

## License

Apache-2.0
