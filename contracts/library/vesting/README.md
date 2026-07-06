# Token Vesting (cliff + linear)

PCO library template: **KDA vesting with a cliff and linear release, escrowed upfront**. A grant locks its full amount in a capability-guarded vault the moment it is created, so the beneficiary never depends on the funder staying solvent or honest — and **governance has no path to escrowed funds** (upgrade authority only). This is the safe replacement for ad-hoc escrow/timelock contracts: team and advisor vesting, investor lockups, grant milestones, deferred payments.

## How it works

Funds sit in a **capability-guarded vault account** (a principal whose guard is satisfied only while the internal `SPEND` capability is in scope). `SPEND` is acquired only inside `claim` and `revoke`, after their checks — the vault cannot be debited any other way.

1. **`create-grant id funder beneficiary beneficiary-guard total start cliff end revocable`** — escrows `total` from the funder into the vault. The funder authorizes by signing `coin.TRANSFER` for exactly that amount (they are spending their own funds; no module permission exists to move anyone else's). The beneficiary's guard is enrolled now and authorizes all future claims; **the beneficiary name must be that guard's principal** (`k:`/`w:`/`r:`) — enforced, see Security model. `start` may be in the past (e.g. an employment start date).
2. **`claim id`** — pays the beneficiary everything vested and not yet claimed. Vesting is 0 before `cliff`, linear in elapsed time from `start` to `end`, and complete at `end`. The beneficiary signs scoped to `(vesting.CLAIM-AUTH "id")`. Payment uses `transfer-create` with the enrolled guard, so the beneficiary account is created on first claim if absent.
3. **`revoke id`** — only if the grant was created `revocable`, and only by the funder (authenticated against the **current** guard of their coin account, so revoke authority follows a coin key rotation). The grant is frozen at its vested amount — still claimable by the beneficiary — and only the unvested remainder is refunded. Vested funds can never be clawed back.

Every step emits an event (`GRANT_CREATED`, `CLAIMED`, `REVOKED`) for off-chain audit.

## Security model

- **Escrowed upfront.** The full grant moves into the vault at creation. There is no "funder tops up later" state and no way to create an underfunded grant.
- **Beneficiary is a principal account — enforced.** `create-grant` requires `beneficiary` to be the principal of `beneficiary-guard` (`validate-principal`). This binds the payout name to the enrolled guard: the account can neither be squatted with a foreign guard (coin rejects it at the protocol level) nor guard-rotated out from under the grant (coin forbids rotating principal accounts). Without this, either would leave the escrow permanently unclaimable — there is deliberately no admin sweep.
- **Refunds are clamped.** `revoke` never refunds more than the grant's own remaining escrow (`total − claimed`), even if `block-time` were ever non-monotonic — one grant's revoke can never be paid out of another grant's funds. `claimable-amount` is likewise clamped at zero.
- **Non-custodial governance.** The `GOV` keyset can upgrade the module and nothing else — no function under `GOV` touches the vault. (Upgrade power is still absolute power over future code: pin the module hash you audited, and use a multi-sig keyset.)
- **Vested is untouchable.** `revoke` refunds only `total − vested(now)`; the vested portion stays claimable by the beneficiary forever.
- **Scoped signatures.** `CLAIM-AUTH` and `REVOKE-AUTH` are capabilities, so a signature authorizes exactly one action on exactly one grant — nothing else the same key could satisfy in the transaction.
- **Precise math.** The linear schedule multiplies before dividing and floors to coin's 12-decimal precision, so every claim amount is transferable and claims are monotonic (no over-claim at schedule boundaries; the final claim pays the exact remainder, no dust left behind).

## Deployment checklist

1. Wrap the module in your namespace; replace the `"vesting-gov"` keyset with your deployed, namespace-qualified governance keyset (**multi-sig recommended**).
2. Deploy and `create-table`. There is no init step — grants are self-contained.
3. Validate the end-to-end flow on **devnet** before mainnet — **mandatory**, not optional (see Known limits; on-chain table-read behavior cannot be proven in the REPL).

## Usage

```pact
;; funder creates a 1-year grant with a 90-day cliff, revocable
;; (signs coin.TRANSFER for 365.0 to the vault — vesting.get-vault-account)
(vesting.create-grant "alice-2026" "k:funder..." "k:alice..." (read-keyset "alice")
  365.0 (time "2026-01-01T00:00:00Z") (time "2026-04-01T00:00:00Z")
  (time "2027-01-01T00:00:00Z") true)

;; beneficiary claims whatever has vested (signs scoped to CLAIM-AUTH)
(vesting.claim "alice-2026")

;; funder revokes the unvested remainder (signs scoped to REVOKE-AUTH)
(vesting.revoke "alice-2026")
```

Sign `claim`/`revoke` with **only** the `CLAIM-AUTH`/`REVOKE-AUTH` capability. Do not also scope the signature to the vault's `coin.TRANSFER` — the module installs that capability itself, and a signature-installed duplicate makes the transaction fail (harmlessly; resubmit without it).

## Testing

`examples/vesting-test.repl` is self-contained (loads `coin` + interfaces from `registry/`):

```bash
cd contracts/library/vesting/examples && pact vesting-test.repl
```

The suite drives the full lifecycle on a controlled clock — escrow at creation, pre-cliff denial, exact linear amounts at the cliff / mid-schedule / after the end, revocation mid-schedule with the frozen remainder still claimable — plus every authorization attack: claiming with a foreign key, a signature scoped to another grant, revoking someone else's grant, revoking a non-revocable grant, direct vault drains, squatting a beneficiary principal, and a clock-rollback revoke (the refund clamp). It ends with the vault at exactly `0.0`: every escrowed KDA provably claimed or refunded. CI runs this suite as a blocking check.

## Known limits

- **Devnet validation is MANDATORY before mainnet — not optional.** The auth capabilities read on-chain tables; the template binds every read before its `enforce` (the node-safe pattern), but this class of bug is **invisible in the REPL**. Deploy to a devnet node and drive a full `create-grant → claim → revoke` cycle before trusting this with real funds.
- **Vanity beneficiary names are rejected by design.** The beneficiary must be a principal account (`k:` single key, `w:` multi-key, `r:` keyset reference). This is what guarantees the escrow can always be claimed; see Security model.
- **The suite's test keys are synthetic.** On a real chain, `k:` account keys are ED25519 public keys; the enforcement is coin's, not this module's.
- **Grant `id`s are caller-supplied and must be unique** — `create-grant` uses `insert`, so a reused id aborts. Use a scheme like `"<beneficiary>-<purpose>-<nonce>"`.
- **Revocation is all-or-nothing per grant and irreversible.** A revoked grant is frozen at its vested amount; there is no un-revoke and no partial revoke.
- **Block time is the parent block's timestamp** (~one block behind wall clock) — irrelevant at vesting timescales, but do not build second-granularity schedules.
- Governance holds upgrade power. It cannot touch escrowed funds through any function in this module, but an upgrade can change the module. Pin the deployed module hash you audited; use a multi-sig governance keyset.

## License

Apache-2.0
