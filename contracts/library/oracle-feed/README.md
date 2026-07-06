# Oracle Feed (median, staleness-guarded)

PCO library template: an on-chain **median data feed** with fail-closed consumption. A governed set of publishers posts observations; consumers read a median that only counts **fresh** observations (against their own staleness tolerance) from **currently enrolled** publishers, and aborts below a per-feed quorum. Prices are the obvious use, but any positive-decimal observation works.

## How it works

1. **`init publishers guards`** (governance) — enroll the publisher accounts with their authenticating guards (max 20).
2. **`create-feed id description min-answers`** (governance) — create a feed with a read quorum.
3. **`post feed publisher value`** — an enrolled publisher upserts their latest observation (positive decimals only), signing scoped to `(oracle-feed.PUBLISH-AUTH "node-1")`. **The timestamp is assigned from chain block-time** — publishers cannot backdate or forward-date.
4. **`get-price feed max-age`** — the consumer's read: the **median** of observations no older than `max-age` seconds, from current publishers only. Aborts (fails closed) unless at least `min-answers` such observations exist. `answer-count` previews the same filter.
5. **`rotate-publishers publishers guards`** (governance) — replace the set; a rotated-out publisher's standing observation stops counting **immediately**.

Every step emits an event (`FEED_CREATED`, `POSTED`, `PUBLISHERS_ROTATED`) — the `POSTED` stream is the feed's full history (state keeps only each publisher's latest).

## Security model

- **Median aggregation — at a real quorum.** With `n ≥ 3` fresh answers, fewer than `n/2` rogue publishers cannot move the answer beyond the honest range (`n ≥ 2f+1`). Below that the guarantee does not exist: one answer is a single publisher's word, and **two answers are averaged, giving either publisher unbounded pull**. Set `min-answers ≥ 3` for adversarial robustness, and size the publisher set so staleness can't thin reads below it.
- **Fail closed, never stale.** Consumers pick `max-age`; observations older than that are excluded, and a read below the quorum aborts. There is no path that returns a stale or thin answer.
- **Chain-assigned time.** `post` stamps observations with block-time. A publisher controls only the value, never the freshness bookkeeping.
- **Rotation is revocation.** Reads aggregate only current publishers, so rotating a compromised publisher out instantly removes their influence. Respond to a key compromise by enrolling a **fresh name** — re-enrolling the same name (even with a new guard) instantly revives that name's last posted, possibly poisoned, observation under its old timestamp.
- **Names are separator-safe.** Feed ids and publisher names must not contain `":"` (the observation-key separator) — enforced, so distinct (feed, publisher) pairs can never alias one storage row.
- **Scoped publishing.** `PUBLISH-AUTH` is a capability; a posting signature authorizes nothing else the same key could satisfy in the transaction.
- **Governance cannot post.** It curates publishers and creates feeds. Note the trust honestly: whoever controls enrollment controls the feed's long-run integrity — an oracle's governance is **operationally trusted**, unlike this library's custody templates. Multi-sig it.

## Consuming a feed safely

The suite ships a worked consumer (`price-consumer` in the test file) demonstrating the pattern every integrator should copy:

```pact
(let* ((p (oracle-feed.get-price "KDA/USD" 900.0))       ;; staleness: fail closed
       (prev (get-last-accepted))
       (dev-ok (or (= prev 0.0)
                   (<= (abs (- p prev)) (* prev 0.10)))))  ;; deviation breaker
  (enforce dev-ok "price deviates too far from last accepted")
  ...)
```

- **Choose `max-age` for your use case** — a lending protocol wants minutes, a weekly settlement can take hours. Remember block-time is the parent block's timestamp (~30s lag).
- **Add a deviation circuit-breaker** against your last accepted value: the feed defends against minority manipulation, but a majority repointing (or a real market crash) passes quorum and freshness — the consumer decides whether a sudden move is acceptable.
- **Round before money math.** An even answer count averages the two middle values, which can carry one more decimal place than the inputs; round/floor to your token's precision before transferring.

## Deployment checklist

1. Wrap the module in your namespace; replace the `"oracle-feed-gov"` keyset with your deployed, namespace-qualified governance keyset (**multi-sig mandatory in spirit** — enrollment is the feed's root of trust).
2. Deploy, `create-table` (all four), `init`, `create-feed`.
3. Validate the end-to-end flow on **devnet** before mainnet — **mandatory**, not optional (the auth path reads on-chain tables; that class of bug is invisible in the REPL).

## Testing

`examples/oracle-feed-test.repl` is fully standalone:

```bash
cd contracts/library/oracle-feed/examples && pact oracle-feed-test.repl
```

51 assertions on a controlled clock: publisher authorization attacks (non-publisher, wrong key, signature scoped to another publisher), chain-assigned timestamps, even-count and odd-count medians (an outlier is provably swallowed), staleness windows thinning the answer set until the quorum fails closed, the rotation regression (a rotated-out publisher's standing observation stops counting immediately, flipping the price), re-post upserts, and the consumer deviation-breaker pattern accepting drift and rejecting a >10% jump. CI runs this suite as a blocking check.

## Known limits

- **The feed is only as good as its publisher set.** The median bounds *minority* manipulation; a colluding majority of fresh answers controls the price. Enrollment (governance) is the root of trust — this is inherent to oracles, not fixable in Pact.
- **`min-answers 1` means single-publisher truth, and `2` means an average either publisher controls.** Legitimate for a feed you run yourself; understand what each value buys before pointing money at it. `≥ 3` is where the median guarantee starts.
- **A quorum above the publisher count makes the feed unreadable** (fail closed) until enough publishers exist and post — by design.
- **Publishers are per-module, not per-feed.** Every enrolled publisher may post to every feed. Segment by deploying separate instances if feeds need disjoint publisher sets.
- **Publisher and feed names cannot contain `":"`** (the observation-key separator, banned for injectivity). A `k:` principal account name contains a colon, so publishers are named as plain accounts (e.g. `"oracle-node-1"`) guarded by their own key — not `k:` principals. Confirmed on devnet.
- **State holds only each publisher's latest observation** per feed (bounded: publishers × feeds rows). History lives in the `POSTED` event stream — index it off-chain if you need TWAPs or archives.
- Governance holds upgrade power. Pin the deployed module hash you audited; use a multi-sig governance keyset.

## License

Apache-2.0
