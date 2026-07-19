# Fixed-Supply Token with Advisory Governance

The [fixed-supply, non-upgradeable token](../token-fixed-supply/) extended
with **advisory on-chain governance**: proposals plus live balance-weighted
yes/no/abstain voting with permanent tallies. Votes are the community's
recorded voice — **they execute nothing**, because in a frozen token there is
nothing for them to execute: the mint is one-shot, the module cannot be
upgraded, and no admin surface exists.

## The live-vote discipline

The governance design closes the classic token-voting exploits *by
construction* rather than by snapshotting:

- **Weight = current balance.** A vote records the voter's balance at cast
  time; re-voting updates the recorded vote in place.
- **Balance decreases release weight.** Every transfer-out and burn
  automatically shrinks the account's recorded weight on every OPEN proposal
  down to the new balance. Sold or moved tokens can never keep voting — the
  vote-then-transfer double-count is impossible.
- **Credits never vote.** Received tokens arrive unvoted; tallies only ever
  grow from an explicit `cast-vote` by the holder.
- **`release-votes` is public on purpose.** It derives everything from the
  account's real balance, so a permissionless call can only correct stale
  weights downward — never forge or grow a vote. Anyone may sync anyone.
- **Bounded governance load.** At most `MAX-ACTIVE-PROPOSALS` (3) proposals
  are open at once, so the release work a transfer or burn carries is small
  and bounded — measured and asserted in the suite: a transfer at true worst
  case (3 open proposals, live votes on all 3) costs ~489 gas against the
  150k ceiling.
- **Scoped-signature governance.** Proposing, voting, and guard rotation are
  authorized through dedicated capabilities (`PROPOSE`, `VOTE`, `ROTATE`), so
  a wallet can sign a vote scoped to exactly one proposal — no unscoped
  signatures required anywhere in the module.
- **Tallies freeze at close.** After `close-at`, votes are rejected and
  balance changes no longer touch the proposal — the result is a permanent
  on-chain record. The open-proposal index self-prunes.

**Disclosure duty:** if you attach off-chain or cross-module meaning to a
tally (listing decisions, treasury actions run by other modules), state
prominently that votes here are advisory signals, not levers.

## Deployment checklist

Everything from the base template applies (namespace wrap, transaction-data
parameters, `create-table` stays in the deploy transaction, `init-mint`
once, devnet validation), plus one extra deploy-time parameter:

- `gov-threshold` — fraction of `TOTAL-SUPPLY` a holder needs to open a
  proposal, enforced into `[0.001, 0.1]` (0.1%–10%).

Voting windows are 24h–720h per proposal, chosen by the proposer.

## Usage

```pact
;; open a proposal (balance >= threshold; your guard authorizes)
(fixed-supply-token-gov.create-proposal "k:holder" "Title" "Body" 72)

;; vote / re-vote (weight = your current balance)
(fixed-supply-token-gov.cast-vote "1" "k:holder" "yes")

;; anyone can sync a stale vote weight down to the real balance
(fixed-supply-token-gov.release-votes "k:whale")

;; read the permanent record
(fixed-supply-token-gov.get-results "1")
```

## Testing

```bash
cd examples
pact fixed-supply-token-gov-test.repl
```

The suite re-proves a compact core sanity block (one-shot mint, managed
transfers, reserved names) and then exercises the full governance delta:
threshold and duration bounds, guard-authorized proposing/voting, re-vote
tally exactness, the release rule on transfer AND burn, the public
release-votes no-op property, the active-proposal cap, transfer gas under
maximum governance load, tally freeze at close, and index self-pruning.

## Known limits

- All base-template limits apply (load-time validation, irreversibility,
  single chain, devnet mandate, exact-JSON deploy parameters, first-come
  vanity names — see the base README; distribute the mint to principal
  `k:`/`w:` accounts or mint in the deploy transaction).
- **Proposal slots can be squatted.** Any holder above the threshold can
  occupy all 3 active slots with 720h windows and race to re-grab them at
  expiry. Advisory-only and recoverable (slots free at close, races are
  contestable), but a determined threshold-holder can crowd the channel.
  Pick `gov-threshold` with that in mind; a deposit or per-account limit
  would need a fork of the template.
- The deploy aborts if `floor(total-supply × gov-threshold, precision)` is
  zero (e.g. tiny supply at precision 0) — a zero threshold would let
  zero-balance accounts propose, so the module refuses the combination.
- **Advisory only.** No quorum is enforced and no execution is wired —
  readers judge turnout themselves via `get-results`. This is deliberate;
  wiring execution to tallies would require a governed surface and a
  different trust model.
- Proposal titles/bodies live on-chain forever (120/2000 char bounds);
  moderation is impossible by design.

## License

Apache-2.0 — see the repository [LICENSE](../../../LICENSE).
