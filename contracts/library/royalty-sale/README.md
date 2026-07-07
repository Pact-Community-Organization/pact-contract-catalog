# Royalty Sale — conservation-checked NFT marketplace

PCO library template: a **self-contained NFT with an enforceable-royalty marketplace**, built as the hardened answer to the flaws documented in our [Marmalade V2 security & architecture analysis](../../docs/). It owns both its token ledger and its sale escrow end to end — which is the only way to *prove* the safe settlement patterns rather than inherit a shared-escrow sweep.

On-chain royalty enforcement is genuinely the strongest model in the NFT market (Ethereum's EIP-2981 is metadata-only and its enforcement collapsed; Solana keeps re-platforming transfer-restriction). Marmalade had the right idea; this template keeps the idea and fixes the execution.

## What it does

1. **`mint id owner owner-guard creator creator-guard royalty-bps transferable uri`** — create a 1-of-1 NFT. The royalty rate is fixed forever at mint. `transferable: false` makes the token **sale-only** (see below).
2. **`list-token id price currency marketplace marketplace-guard marketplace-bps`** — the owner lists at a fixed price. The marketplace fee rate and payee are fixed **here, by the seller** — not by the buyer at purchase.
3. **`buy id buyer buyer-guard`** — the buyer pays the full price into the escrow (they authorize only their own debit); settlement pays creator + marketplace + seller, ownership flips to the buyer, and the listing closes. **All in one atomic, conservation-asserted transaction.**
4. **`transfer id receiver receiver-guard`** — a free (no-payment) gift/move, allowed **only** for a token minted `transferable`.
5. **`delist id`** — the owner cancels a listing.

## How it fixes the Marmalade findings

Each hardened property maps directly to a finding in the analysis:

| Property | Fixes |
|---|---|
| **One settlement, conservation-asserted.** `buy` computes every cut, pays each once from the escrow, and asserts `royalty + fee + proceeds == price` *and* that the escrow returns to its pre-sale baseline. No policy/hook ever holds escrow-spend authority. | ARCH-1 (shared escrow sweep), POL-3 (policy reaches into escrow) |
| **Economics live in state, not the buy transaction.** The royalty is fixed on the token at mint; the fee rate + payee are fixed on the listing by the seller. `buy` takes no fee or royalty argument — a buyer structurally cannot zero the fee. | ARCH-2 (caller-supplied marketplace fee) |
| **Fail closed.** Every payout account must be a `validate-principal` account; the royalty rate and fee are range-checked and capped; nothing defaults to permissive. | POL-1 (fail-open guard defaults) |
| **Sale-only is an explicit, robust opt-in.** The creator *chooses* `transferable: false` at mint. It's immutable and cannot be composed away — the token can then move only through `buy`, which always pays royalty. | POL-2 (blunt always-fail transfer lock) |
| **Principal payees + payout merge.** Creator, seller and marketplace are principal accounts, so a payout can't be bricked by a squatted vanity name; same-account payouts (a *primary* sale, where creator **is** the seller) are merged into one payment so they cannot collide on coin's managed-transfer install. | fund-lock + duplicate-install classes |

## Security model

- **Capability-guarded escrow.** All payment sits in a principal account whose guard requires the internal `SPEND` capability, acquired *only* inside `buy`'s settlement and never externally. The settlement pays out exactly what was paid in, asserted both by the arithmetic identity and by the escrow-returns-to-baseline check.
- **Enforceable royalty, honestly.** A sale-only token cannot move without a paying sale — real on-chain enforcement with no trusted marketplace. That is a deliberate trade-off (no gifting, no free wallet migration) the creator opts into, not a default forced on every token.
- **Owner-scoped signatures.** Listing, delisting and transfers require the `OWNER` capability (the owner's enrolled guard); a buyer authorizes only their own payment.

## Deployment checklist

1. Wrap the module in your namespace; replace the `"royalty-sale-gov"` keyset with your deployed, namespace-qualified governance keyset (**multi-sig recommended**; governance is upgrade-only and touches no funds).
2. Deploy and `create-table` (`tokens`, `listings`).
3. Validate on **devnet** before mainnet — **mandatory** (the auth capability reads on-chain tables; that class of bug is invisible in the REPL).

## Usage

```pact
;; creator mints a sale-only 1-of-1 with a 5% royalty (k: principal accounts)
(free.royalty-sale.mint "art-001"
  "k:creator…" (read-keyset "creator") "k:creator…" (read-keyset "creator")
  500 false "ipfs://art-001")

;; owner lists at 100 KDA with a 2.5% marketplace fee
(free.royalty-sale.list-token "art-001" 100.0 coin
  "k:marketplace…" (read-keyset "mkt") 250)

;; buyer purchases (signs only their own coin.TRANSFER of the price into escrow)
(free.royalty-sale.buy "art-001" "k:buyer…" (read-keyset "buyer"))
```

## Testing

`examples/royalty-sale-test.repl` is self-contained (loads `coin` + interfaces from `registry/`):

```bash
cd contracts/library/royalty-sale/examples && pact royalty-sale-test.repl
```

38 assertions: fail-closed mint validation, sale-only vs transferable transfer rules, listing validation with the fee fixed in state, a secondary sale proving conservation to 12 decimals (creator + marketplace + seller + escrow-to-zero), the **primary-sale merge** (creator == seller pays one merged payout with no managed-transfer collision), zero-royalty and odd-price rounding-dust conservation, unlisted/delisted/re-buy rejection, and end-to-end sale-only royalty enforcement. CI runs this suite as a blocking check.

## Known limits

- **Instant fixed-price sales only.** Auctions, Dutch auctions, and time-escrowed offers are a future extension; the conservation-checked settlement generalizes to them.
- **Sale-only tokens cannot be gifted or freely migrated** — that is the cost of enforceable royalties, and it is the creator's explicit opt-in, not a default.
- **1-of-1 NFTs.** Fractional / multi-edition supply is out of scope for this template.
- **The escrow is shared across sales but nets to zero each sale** (conservation is asserted per sale). Do not send funds to the escrow account directly.
- **Validate on devnet before mainnet** (see the deployment checklist).
- Governance holds upgrade power. Pin the deployed module hash you audited; use a multi-sig governance keyset.

## License

Apache-2.0
