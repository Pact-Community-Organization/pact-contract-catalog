# DAO Voting (membership, quorum + threshold)

PCO library template: **membership-based on-chain voting** — a governed member set votes yes/no/abstain on proposals, one member one vote, immutable once cast. A proposal passes when participation meets a **quorum** percentage of the current member set and yes-votes meet an approval **threshold**. The module custodies **no funds**: it produces an auditable, replayable on-chain decision record. Pair it with the [multisig-treasury](../multisig-treasury/) template to act on passed proposals — together they are the complete DAO primitive stack.

## How it works

1. **`init members guards quorum-pct threshold-pct`** (governance) — enroll the member accounts with their authenticating guards (positionally aligned) and set the integer percentages (both in `[1,100]`).
2. **`propose id proposer title deadline`** — any member opens a proposal with a future voting deadline. The proposer does not auto-vote. `id` must be unique.
3. **`vote id member choice`** — a member casts `"yes"`, `"no"`, or `"abstain"`, strictly before the deadline. One immutable vote per member per proposal — no vote changes.
4. **`close id`** — at or after the deadline, **anyone** may close (settlement is deterministic; the recorded votes are the authorization). Close counts **only votes from members current at close time**, records the filtered tallies, and settles:
   - **quorum**: `participation × 100 ≥ quorum-pct × member-count` — abstains count toward participation;
   - **passed**: quorum **and** `yes > 0` **and** `yes × 100 ≥ threshold-pct × (yes + no)` — abstains do not dilute the threshold.
5. **`cancel id`** (governance) — cancel an open proposal.
6. **`rotate-members members guards quorum-pct threshold-pct`** (governance) — replace the member set and percentages.

Every step emits an event (`PROPOSED`, `VOTED`, `CLOSED`, `CANCELLED`, `MEMBERS_ROTATED`) for off-chain audit.

## Security model

- **Authenticated, scoped voting.** `propose`/`vote` acquire the `MEMBER-AUTH` capability, which checks current membership **and** enforces the member's enrolled guard. Members scope their signature to `(dao-voting.MEMBER-AUTH "alice")`, so a voting signature does not also authorize other operations their key could satisfy in the transaction.
- **Counts-once, immutable.** A member appears in at most one choice list per proposal; there is no vote-change and no vote-removal — the record is append-only until settlement.
- **Rotation revokes in-flight votes.** `close` counts only current members' votes, so rotating a compromised member out drops their votes on every open proposal. Respond to a key compromise by **removing the member's name** — re-enrolling the same name with a new guard revives votes the old key cast on still-open proposals.
- **Integer-only math.** All quorum/threshold comparisons are integer products (counts × 100) — no decimal division, no rounding surface.
- **Zero-yes proposals never pass.** An all-abstain turnout can meet quorum but is rejected (`yes > 0` is required), so a proposal cannot pass without a single affirmative vote.
- **The passage bar is locked at propose time.** Each proposal snapshots the quorum and threshold percentages when it is opened — governance cannot move the bar on an open proposal after votes are cast (rotating the percentages affects only future proposals). Membership is deliberately *not* snapshotted: that is what lets rotation revoke a compromised member's votes, and it means governance retains influence over open proposals through the member list itself — every rotation emits `MEMBERS_ROTATED` for audit.
- **Governance cannot vote.** It configures the member set, cancels open proposals, and upgrades the module; it cannot cast, alter, or remove votes, and settled proposals are immutable.

## Deployment checklist

1. Wrap the module in your namespace; replace the `"dao-voting-gov"` keyset with your deployed, namespace-qualified governance keyset (**multi-sig recommended** — governance can rotate the member set and cancel proposals).
2. Deploy and `create-table`, then call `(init members guards quorum-pct threshold-pct)` **once**.
3. Validate the end-to-end flow on **devnet** before mainnet — **mandatory**, not optional (see Known limits).

## Usage

```pact
;; a member proposes (signs scoped to MEMBER-AUTH)
(dao-voting.propose "grants-2026-q3" "alice" "Fund the grants program"
  (time "2026-08-01T00:00:00Z"))

;; members vote (each signs scoped to their own MEMBER-AUTH)
(dao-voting.vote "grants-2026-q3" "alice" "yes")
(dao-voting.vote "grants-2026-q3" "bob" "no")

;; after the deadline, anyone settles it
(dao-voting.close "grants-2026-q3")
```

## Testing

`examples/dao-voting-test.repl` is fully standalone (this module depends on nothing — not even coin):

```bash
cd contracts/library/dao-voting/examples && pact dao-voting-test.repl
```

60 assertions on a controlled clock: the full pass/quorum-fail/threshold-fail/all-abstain outcome matrix, deadline boundaries (vote strictly before, close at-or-after), counts-once voting, every authorization attack (non-member, wrong key, signature scoped to another member, governance bypass), the rotation regression (a rotated-out member's in-flight vote is dropped at close, flipping the outcome), the snapshot regression (governance lowering the bar cannot flip an open proposal), the documented in-place re-key sharp edge, inclusive quorum/threshold boundaries, the single-member 100/100 edge, and the 200-member cap. CI runs this suite as a blocking check.

## Known limits

- **Devnet validation is MANDATORY before mainnet — not optional.** The auth capability reads on-chain tables; the template binds every read before its `enforce` (the node-safe pattern), but this class of bug is **invisible in the REPL**. Deploy to a devnet node and drive a full `propose → vote → close` cycle before relying on outcomes.
- **Member sets are capped at 200 (`MAX_MEMBERS`).** Votes are stored as lists on the proposal row and `close` filters them against the member list (O(members × voters)); measured at ~2.7k gas for 200 all-voting members — generous headroom under the 150k per-transaction gas ceiling. For larger electorates you need per-vote rows and paginated tallying — a different design.
- **Membership at close governs the tally.** Quorum/threshold are snapshotted per proposal, but the member *set* is read at `close` — rotating a member out drops their in-flight votes (by design), and rotating members in changes the quorum denominator for open proposals. Governance is trusted here; put it under a multi-sig.
- **Proposal `id`s are caller-supplied and must be unique** — `propose` uses `insert`, so a reused id aborts (a front-runner squatting an id costs you nothing but a retry with a fresh id).
- **No vote delegation, no weighting.** One enrolled member, one vote. Token-weighted voting needs snapshot mechanics that are chain-specific — out of scope for this template.
- **Block time is the parent block's timestamp** (~one block behind wall clock) — do not build second-granularity deadlines.
- Governance holds upgrade power. Pin the deployed module hash you audited; use a multi-sig governance keyset.

## License

Apache-2.0
