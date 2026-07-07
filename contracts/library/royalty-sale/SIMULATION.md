# SIMULATION — library/royalty-sale, full-marketplace run

## Summary

| Field | Value |
|---|---|
| **Module** | `royalty-sale` 1.0.0 |
| **Date** | 2026-07-06 |
| **REPL simulation** | `examples/royalty-sale-market-sim.repl` — 149 assertions (121 positive, 28 adversarial rejections), all green |
| **Devnet simulation** | `scripts/devnet-validate` → `npm run royalty-sale-sim` — **32 txs mined to confirmation** on a live KDA-CE node (`recap-development`); deployed as `free.royalty-market` (hash `5qDbxh_0Apk86rJ6NU8EbBSFfKDht4d_VmkwrcQJRec`) with `free.sim-tok` as the second currency; request keys in `scripts/devnet-validate/results/royalty-sale-market-sim.json` |
| **Static gate** | `pact-static-check.sh` PASS, 0 violations |
| **Verdict** | **HOLDS UP.** Conservation, royalty accrual, fee integrity, and every adversarial rejection proven in the REPL and on-node. No code defect found. |

This is the economic follow-up to `AUDIT.md`: the audit proved the settlement
is *safe*; this run proves a whole marketplace *works* on it — creation,
primary sales, a multi-hop secondary market, two competing marketplaces, a
second currency, gifts, and a hostile user — with every unit of money accounted
for to 12 decimal places.

## The marketplace that was simulated

Ten participants: two artists (alice, dana), four collectors (bob, carol,
frank, gina), two marketplaces (mkt1 at 2.5%, mkt2 at 5%), one adversary
(eve), one governance key. Six tokens spanning the royalty spectrum:

| Token | Creator | Royalty | Transferable | Story |
|---|---|---|---|---|
| `gift-0` | alice | 0% | yes | gifted twice (provenance events) |
| `art-25` | alice | 2.5% | yes | primary sale, creator==seller merge |
| `chain-1` | alice | 5% | **sale-only** | the headline resale chain (6 sales) |
| `art-max` | alice | 50% (cap) | yes | list → delist → relist → sale at max royalty |
| `dna-tok` | dana | 2.5% | yes | sold twice in a **non-coin** fungible-v2 |
| `fr-1` | **bob** (creator **alice**) | 2.5% | yes | minter ≠ creator; front-run + dust + wash-trade cases |

## Headline: the resale chain

`chain-1` (5% royalty, sale-only) moved creator→A→B→C→D and then twice more,
through both marketplaces:

| Sale | Seller → Buyer | Price | Fee (bps → payee) | Royalty → alice | Seller nets |
|---|---|---|---|---|---|
| S2 | alice → bob | 100.0 | 2.5 (mkt1) | 5.0 | 92.5 (merged with royalty: one 97.5 payout) |
| S3 | bob → carol | 160.0 | 8.0 (mkt2) | 8.0 | 144.0 |
| S4 | carol → frank | 80.0 | 2.0 (mkt1) | 4.0 | 74.0 |
| S5 | frank → gina | 250.0 | — | 12.5 | 237.5 |
| S6 | gina → bob | 60.0 | 6.0 (**alice as marketplace**) | 3.0 | 51.0 |
| S7 | bob → carol | 50.0 | 1.5 (**bob as marketplace**) | 2.5 | 46.0 + 1.5 merged |

Proven, both in the REPL and reconstructed from the SOLD event log alone:

- **Royalty on every hop**: cumulative creator royalty over the 4-hop chain is
  **29.5 == 5% × 590 volume, exactly**; over the token's 6-sale lifetime,
  **35.0 == 5% × 700, exactly**. The rate travels with the token, not the seller.
- **Every seller nets price − royalty − fee**, exactly.
- **Sale-only is airtight**: the free-transfer path was rejected for the
  creator (before hop 1) and for the owner (after 6 ownership changes). `buy`
  — which always pays the royalty — is the only way the token ever moved.
- Payout merges never collide on the managed-transfer install:
  creator==seller (S2), marketplace==creator (S6), marketplace==seller (S7)
  each arrive as ONE merged payment.

The devnet run replays the 4-hop chain on-node with fresh personas, plus a
fifth sale settled over a dust-carrying escrow: 5 sales, 630.0 volume,
creator royalty **31.5 == 5% × 630** — every settlement mined and conserved
on a live KDA-CE node.

## Multi-currency (the marketplace is not coin-only)

`dna-tok` sold twice in the library `token-fungible` (a non-coin fungible-v2):
primary 500.0 TOKEN via mkt2 (dana, creator==seller, merged 475.0; fee 25.0),
secondary 200.0 TOKEN (royalty 5.0 → dana, proceeds 195.0). Dana's cumulative
TOKEN royalty: **17.5 == 2.5% × 700**, exact. Token-side escrow settled to 0
both times; coin balances untouched by token sales. The devnet run repeats
both sales on-node — the settlement path (dynamic `precision`, managed
`TRANSFER` install, escrow guard) is node-proven for a second fungible, which
the original F1 validation (coin-only) did not cover.

## Global accounting (the economics hold)

Coin side — 10 sales, prices summing to **940.0**:

| Aggregate | Value |
|---|---|
| Royalties (all to alice — she created every coin-side token) | 55.25 |
| Marketplace fees (mkt1 5.5, mkt2 9.5, alice-as-mkt 6.0, bob-as-mkt 1.5) | 22.5 |
| Seller proceeds | 862.25 |
| **Sum** | **940.0 — every unit the buyers paid in** |

- **Exact final balance of every participant asserted** (alice 215.25,
  bob 1137.75, carol 713.5, frank 1157.5, gina 801.0, dana 70.0, mkt1 15.5,
  mkt2 19.5, eve 1.999999999999, escrow 0.000000000001).
- **Global conservation**: the sum of ALL balances == the 4132.0 funded at
  setup, to 12 dp — the marketplace neither minted nor destroyed a single
  unit. Token side: all balances sum to the 1300.0 minted.
- **Escrow returns to its baseline after every one of the 12 sales**
  (0 for the first nine; the donated-dust baseline after the griefing case).
- **Event-log reconstruction**: ownership history replayed from
  SOLD/TRANSFERRED events alone matches `owner-of` state for all six tokens,
  and the royalty/fee/volume totals recomputed from events match the balance
  deltas. (The REPL's event log resets each transaction, so the suite ingests
  each sale's events into a `sim-indexer` fixture table — exactly what an
  off-chain indexer does.)

## Adversarial sweep (all rejected, REPL + the starred ones re-proven on-node)

| Attack | Result |
|---|---|
| Non-owner lists / delists* / transfers (eve, scoped to `OWNER`) | `Keyset failure` |
| Broke buyer (balance 2 vs price 40)* | `Insufficient funds` (currency debit) |
| Buyer under-scopes the price (fee/price evasion — buy has NO money argument) | `TRANSFER exceeded` |
| **Front-run: seller reprices after the buyer signed*** | buy aborts (`TRANSFER exceeded`); buyer's balance untouched — a buyer can never be made to pay more than they signed |
| Escrow self-buy (buyer == escrow account) | `sender cannot be the receiver of a transfer` |
| Non-principal owner / creator / marketplace / receiver / buyer | `… must be a principal account` |
| Royalty > 50% or negative; fee > 10% or negative | range enforce |
| Zero / negative / over-precision price | `price must be positive` / precision enforce |
| Transfer of a listed token; transfer of a sale-only token* | `delist before transferring` / `token is sale-only; use buy` |
| Re-buy of a settled listing; buy after delist; buy of never-listed id | `token is not listed for sale` / missing row |
| Duplicate mint of an existing id | insert rejected (1-of-1 holds) |
| **Escrow dust-griefing*** (donate 1e-12, then sell) | next sale settles; escrow returns to the donated **baseline**, not zero |
| Wash trade (self-buy at price 20) | allowed but costs the full royalty (0.5 to the creator) — volume faking is not free |

## Gas vs the 150k KDA-CE ceiling

Devnet (node-true, from the 32 mined txs of this simulation — authoritative):

| Operation | Gas (observed) | Headroom vs 150,000 |
|---|---|---|
| deploy module + 2 tables (one-time) | 12,440 | 12× |
| mint | 203 | ~740× |
| list-token | 327–357 | ~420× |
| **buy** (7 settlements incl. 3-way splits, non-coin currency, dust baseline) | **704–868** | **~170×** |
| dust donation (plain transfer-create) | 234 | — |
| **maximum across the whole run** | **12,440** | **12×** |

REPL table-model figures agree on the ordering (mint 124, list 278, buy 785,
transfer 256, delist 119). Every mined tx ran under `gasLimit 150000`;
per-step gas and request keys are recorded in
`scripts/devnet-validate/results/royalty-sale-market-sim.json`.

## Observations (no code changes required)

1. **`MINTED` does not carry the initial owner** (params: id, creator,
   royalty-bps, transferable). An indexer can replay every ownership *change*
   from events, but the owner between mint and first move is only visible via
   `get-token`. Immaterial to the economics; worth knowing when building an
   indexer. Similarly, `LISTED`/`SOLD` carry the fee *rate/amount* but not the
   fee payee account.
2. **The "(k:/w:/r:)" wording is narrower than the check**: `validate-principal`
   also admits other principal classes (e.g. `u:`). Any principal's payout
   still settles correctly (the guard travels with it), so this is
   documentation looseness, not a hole — the escrow self-buy case proves the
   interesting instance is rejected by the currency itself.
3. **Wash trading is possible but taxed**: a self-buy pays the full royalty
   and fee. On-chain identity cannot prevent Sybil wash trades; the economics
   at least make them cost `royalty + fee` per fake sale.
4. **Rounding favors the seller** (royalty/fee are floored at the currency's
   precision): a 1e-12-priced sale pays zero royalty. Bounded by one
   precision-unit per sale — negligible against any real price.
5. README says "38 assertions" for the original suite; the suite has 46. Stale
   count, cosmetic.

## Verdict

**GO — the marketplace holds up end-to-end.** Every economic invariant the
template claims was exercised under realistic multi-party conditions and held
exactly: conservation per sale and globally, immutable creator royalties on
every hop of a resale chain, seller-fixed fees a buyer cannot influence,
sale-only royalty enforcement with no non-paying exit, currency-agnostic
settlement, and dust-robust escrow baselines — in the REPL and mined on a live
KDA-CE node. Gas is two orders of magnitude under the ceiling.

## Reproduce

```bash
cd contracts/library/royalty-sale/examples
pact royalty-sale-market-sim.repl          # 149 assertions
# on-node (requires a devnet on :8090):
cd ../../../../scripts/devnet-validate && npm run royalty-sale-sim
```
