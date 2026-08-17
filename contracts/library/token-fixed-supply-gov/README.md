# Fixed-Supply Token with Chain-Local Ranked-Choice Governance

A fixed-supply `fungible-v2` + `fungible-xchain-v1` token with **advisory
on-chain governance**: the operator publishes ranked-choice questions, holders
rank the options, and every chain keeps a live, permanently recorded tally.
Votes are the community's recorded voice — **they execute nothing**: no
quorum, no lever, no governed surface consumes a result.

Derived from a production contract live on Kadena mainnet (see `AUDIT.md`),
cleaned as a fresh-deploy template.

## What it does

- **Fixed supply, one-shot mint.** `init-mint` distributes exactly
  `TOTAL-SUPPLY` on `MINT-CHAIN`, once; there is no burn path and no
  standalone credit path. Every balance increase is fused with a real debit,
  behind the one-shot mint gate, or inside the cross-chain SPV resume.
- **Ranked-choice questions, admin-authored.** The ops tier (a routine
  authority named by governance, held as module state) publishes each
  question with an explicit id and three **absolute instants**: `created-at`,
  `starts-at`, `ends-at`. Holders rank 2–5 options; partial rankings are
  allowed; re-voting replaces the ballot.
- **Live balance weighting.** A ballot's weight is the voter's balance on
  the chain it is cast from, at cast time. Every balance decrease (transfer
  out, cross-chain send) automatically releases the moved weight from the
  account's ballots on every open question — sold or moved tokens can never
  keep voting. Received tokens arrive unvoted. `release-votes` is public on
  purpose: it derives everything from real state, so it can only correct
  stale weights downward.
- **The pairwise matrix is the result; Borda is a diagnostic.** Each question
  carries a K×K head-to-head matrix, updated with every ballot. Its cells
  are depth-neutral — a partial ballot credits its favourite's duels exactly
  as a full one does — which the also-published Borda scores are not (they
  reward truncation, and are kept only as a diagnostic). `get-head-to-head`
  reports the matrix, Copeland win counts, and the Condorcet winner, or
  reports a cycle honestly as no winner.
- **Two-tier signing.** Governance = the `<ns>.token-gov` keyset (upgrades,
  mint, ops rotation, the non-voting register). Ops = a guard stored in
  module state via `set-ops-guard` (create/cancel questions). Governance
  always satisfies the ops gate too and is tried first, so a broken or
  hostile ops authority can never lock governance out — and governance can
  replace the ops authority at any time, even after the module is frozen.
- **Dedicated vote key.** A holder can register a hot key that can ONLY
  vote (`set-vote-key`, main guard only). The main guard always keeps
  working; rotating the account guard deactivates the registration.
- **Non-voting register.** Escrow accounts holding tokens that are not yet
  anybody's are barred from voting **by name**, with a mandatory public
  reason, both directions evented. The reserve (the `r:` principal of the
  governance keyset) is barred by construction.
- **Freezable.** Set `FROZEN-MODULE` to `true` and redeploy to end upgrades
  forever. Ops rotation and the non-voting register deliberately survive the
  freeze; code changes do not.

## The chain-local model

Kadena runs many chains; module tables are per-chain. This template makes
that the design instead of fighting it:

- **Each chain tallies its own ballots.** A holder votes on the chain their
  tokens are on. There is no cross-chain vote aggregation on-chain and no
  hub: the same question is published to **every chain with identical
  arguments** (same id, same three instants), so all copies open and close
  together.
- **Deadlines are absolute for a reason.** A deadline computed from local
  block time would give every chain a different deadline — a double-vote
  hole (vote on one chain, transfer, vote again on another before its later
  deadline). Supplied absolute instants close it.
- **Combine results off-chain by summing the raw matrices.** Read
  `get-head-to-head` on every chain, **sum the K×K matrices cell by cell,
  and decide once** on the summed matrix. **NEVER combine per-chain
  winners** — electing whoever wins the most chains is a different (and
  wrong) voting rule: a candidate can win many small-turnout chains and
  lose the electorate. The matrix cells are additive across chains; the
  winners are not. Skip cancelled copies entirely (`cancelled` is reported
  separately from `closed` for exactly this reason).

## Deploy checklist

1. **Edit the literals** marked `;; EDIT-BEFORE-DEPLOY` in the source:
   `SYMBOL`, `PRECISION`, `TOTAL-SUPPLY`, `MINT-CHAIN`. They are literals,
   not tx-data parameters, because a defconst is re-evaluated on every
   upgrade — a data-block value could be silently restated later. Only the
   namespace stays a deploy parameter (`ns` in tx data).
2. **Define the keyset** `<ns>.token-gov` in your namespace (a multi-sig
   keyset; it is the upgrade, mint, and admin authority, and the reserve
   account `r:<ns>.token-gov` derives from it).
3. **Deploy on every chain you intend to serve**, each with tx data
   `{ "ns": "<ns>", "upgrade": false }` — the deploy transaction creates the
   tables and seeds the supply row. Upgrades use `"upgrade": true`.
4. **Mint once** on `MINT-CHAIN` with the full distribution (`init-mint`
   aborts unless the recipient amounts sum to exactly `TOTAL-SUPPLY`).
   Distribute to principal (`k:`/`w:`) accounts. Move balances to other
   chains with `transfer-crosschain`.
5. **Name the ops authority** with `set-ops-guard` on every chain (a plain
   keyset guard only; the module refuses references, user guards, custom
   predicates, and empty keysets). Until then the governance keyset serves
   as ops, so a fresh deploy is operable immediately.
6. **Publish each question to every chain with identical arguments** — same
   id, same `created-at` / `starts-at` / `ends-at`. The module enforces:
   `created-at` within 1h of chain time, `starts-at` ≥ `created-at` + 12h
   (the announce window: land and verify every copy before the first
   ballot), window between 24h and 720h, and cancellation only before
   `starts-at`.
7. **Run the suites** (below), then validate on devnet before any
   production deployment. The cross-chain SPV plumbing is only provable on
   devnet.

## Operational warnings

1. **Upgrades must bless every previously deployed hash.** The template
   ships without a `bless` line because a fresh deploy has no history. From
   your second deploy onward, add `(bless "<hash>")` for **every** hash ever
   deployed, append-only: an in-flight cross-chain transfer resolves against
   the hash that debited it, and an unblessed hash strands it. Record every
   deployed hash durably at deploy time — after a freeze, the recorded
   history is all there is.
2. **The first question closes the cheap-replacement window.** Until the
   first question exists, a bad deploy can be fixed by redeploying wholesale
   — the only state is the mint. Once questions and ballots exist they are
   the permanent record the module exists to keep: from then on the only
   honest path forward is upgrade-with-bless, and the recorded history must
   carry forward intact. Treat the first question as the moment the deployed
   version is committed — verify every chain's deploy (all 8 tables exist,
   hashes match) before publishing it. A chain missing `rcv-actives` bricks
   every debit on that chain, and after `FROZEN-MODULE` no table can ever be
   created.

## Usage

```pact
;; the ops authority publishes one question to every chain (identical args)
(fixed-supply-token-gov.create-proposal
  "2031-q1" "Which integration next?" "Advisory: rank the options."
  ["bridge" "dex" "wallet"]
  (time "2031-01-10T12:00:00Z")     ; created-at (within 1h of chain time)
  (time "2031-01-11T00:00:00Z")     ; starts-at  (>= created-at + 12h)
  (time "2031-01-18T00:00:00Z"))    ; ends-at    (24h..720h after starts-at)

;; holders rank options on the chain their tokens live on (partial ok)
(fixed-supply-token-gov.cast-vote "2031-q1" "k:holder..." [2 0])

;; optional hot key that can ONLY vote
(fixed-supply-token-gov.set-vote-key "k:holder..." (read-keyset 'vote-key))

;; the authoritative per-chain result (sum matrices across chains off-chain)
(fixed-supply-token-gov.get-head-to-head "2031-q1")
```

## Testing

```bash
cd tests
pact token-gov.repl    # positive lifecycle: mint, transfers, questions,
                       # ballots, release, vote key, xchain, upgrade
pact negatives.repl    # every enforce branch as a failure, with both sides
                       # of every time boundary
pact pairwise.repl     # the head-to-head tally: depth-neutrality,
                       # Borda-vs-Condorcet divergence, reversibility, cycles
```

Suites are self-contained: interfaces and `coin` load from this repository's
registry tree. Cross-chain step 0 and the resume are exercised in the REPL
via `continue-pact`; SPV proof validation itself needs devnet.

## Known limits

- **Advisory only.** No quorum, no execution wiring. If you attach off-chain
  or cross-module meaning to a result, disclose prominently that votes are
  advisory signals.
- **Freeze-flag rehearsal is manual.** `FROZEN-MODULE` is a source literal;
  the refusal it produces ("Module is frozen - no further upgrades") can only
  be exercised by flipping it and attempting an upgrade — rehearse that on
  devnet before a mainnet freeze.
- Until `FROZEN-MODULE` is set, module admin (the governance keyset) can
  write tables directly, silently — `chain-minted` is a lower bound, not an
  audit, until the freeze. This is inherent to upgradeable Pact modules;
  the flip is what converts the fixed supply from policy into fact.
- Question titles/bodies live on-chain forever (120/2000 char bounds);
  moderation is impossible by design.
- The ops principal check cannot see key COUNTS (a principal encodes the
  key-list hash), so an unsatisfiable keyset such as `keys-2` over one key
  is accepted by `set-ops-guard`; that only bricks the ops tier and
  governance re-points it — but verify the key count off-chain before
  signing.

## License

Apache-2.0 — see the repository [LICENSE](../../../LICENSE).

## Audit dispositions (v2.0.0 cold review)

- **Escrow registration is not retroactive.** A ballot cast before an account is registered
  non-voting stays in the tally. Register every escrow before its first question opens. This is
  deliberate: zeroing live ballots on registration would let governance strike an unfavourable
  ballot out of a running tally — the same power the no-cancel-once-open rule exists to deny.
- **Balance-decrease releases emit no event.** An indexer rebuilding tallies from events must
  replay every debit against the open-question set; `get-results`/`get-head-to-head` on chain are
  authoritative. A per-release event was rejected: it would tax every transfer.
- **Verify every chain has all tables before the first question and before any freeze** — a chain
  missing `rcv-actives` refuses every debit, and after a freeze there is no repair.
