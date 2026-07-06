# Property Lease (rental rails)

PCO library template: **on-chain rental-lease rails** — a property registry, per-property rent splitting into earmarked buckets, and deposit escrow with claim-window settlement. All money moves through one capability-guarded vault and every payment is evented for an auditable trail. This is the money-and-record layer; the legal contract lives off-chain.

> **Read this first — what this template is NOT.** These are *rails*, not a legal lease. The enforceable contract is the signed off-chain document whose hash each lease anchors; jurisdiction-specific tenancy law cannot be universalized on-chain. And **v1 has no arbiter**: a landlord's capped deposit claim is honored **unilaterally** — the tenant cannot dispute it on-chain. Use this only where the off-chain document and legal system are the real backstop. See [Trust model](#trust-model) and `AUDIT.md`.

## How it works

1. **`register-property id landlord landlord-guard beneficiary beneficiary-guard info tax-bps repairs-bps beneficiary-bps`** — a landlord self-registers (their guard signs). The three revenue-split basis points are **immutable after registration** (so the beneficiary — a protocol fee, co-owner, or DAO treasury — cannot later be zeroed); the landlord takes the residual `10000 − sum`.
2. **`create-lease …`** — landlord and tenant **co-sign one transaction** (mutual assent). The lease stores the hash of the signed off-chain document plus rent, period, grace, late fee, deposit, term, notice period, and claim window.
3. **`pay-deposit id payer`** — escrow the security deposit into the vault (anyone may pay). Rent is gated until it's fully escrowed.
4. **`pay-rent id payer`** — covers exactly one period: rent splits into the TAX / REPAIRS / BENEFICIARY / LANDLORD buckets, a flat late fee past grace goes to the landlord, and the landlord residual absorbs floor-rounding dust so the vault conserves exactly. **Anyone may pay** (guarantor pattern — coin authorizes the payer).
5. **`withdraw-bucket …`** (landlord) — pull TAX / REPAIRS / LANDLORD to any payee with a memo. **`push-beneficiary id`** (anyone) — sweep the BENEFICIARY bucket to its fixed destination.
6. **`give-notice id new-end`** — either party shortens the term, bounded by the notice period and never below `paid-through`. **`renew-lease …`** — both parties co-sign to extend and re-price.
7. **`claim-deposit id amount memo`** (landlord, once, in-window) then **`settle-deposit id`** (anyone, after the window) — claim to the landlord, remainder to the tenant.

## Security model

- **One capability-guarded vault.** All KDA sits in a principal account guarded by an internal `VAULT` capability, acquired only inside this module — every payout is either landlord-guarded, or bounded to recorded accounting paid to a *stored* destination (rent credits, the fixed beneficiary, the settlement parties). There is no path that pays an attacker-chosen account an attacker-chosen amount.
- **Exact conservation.** `vault balance == Σ bucket balances + Σ deposits held`, to the last of coin's 12 decimals — the landlord residual absorbs split dust, and the suite asserts this after every phase including a `33.33% × 3` odd-rent case.
- **Scoped party signatures.** Landlord and tenant authenticate through `LANDLORD (property-id)` / `TENANT (lease-id)` capabilities, so a signature authorizes exactly one action on one property or lease — not anything else the key could satisfy in the transaction. Lease creation and renewal require **both** guards.
- **Immutable splits, immutable beneficiary destination.** Neither can be changed after registration, protecting the beneficiary from unilateral rerouting or zeroing.
- **Bounded time & ids.** All stored times are bounded to 1970–2200 and day-counts are capped, closing the `add-time` int64-overflow class; ids are ASCII, ≤64 chars, and cannot contain the `|` bucket-key separator.
- **Principal payout accounts — enforced.** The landlord, beneficiary, and tenant accounts (every *stored* payout destination) must be principal accounts (`k:`/`w:`/`r:`). This binds each name to its guard so it cannot be squatted with a foreign guard, which would otherwise make coin abort every payout to it and permanently lock the deposit or a bucket. Free withdrawal payees (`withdraw-bucket`) are not restricted — they receive at withdrawal time, not from stored state.

## Trust model

This template deliberately encodes an **asymmetry**: at lease end the landlord files a single deposit-deduction claim (capped at the escrowed amount, inside the claim window), and after the window **anyone** can settle — claim to the landlord, remainder to the tenant. **There is no on-chain arbiter and no tenant dispute path.** The claim is bounded (never more than the deposit, one claim only, only in-window) but not *adjudicated*. This is appropriate when a real-world lease and legal system sit behind the rails; it is not appropriate as a trustless escrow between adversaries. A future version would add an arbiter-guard slot (a third-party or multi-sig gate on the claim) — the schema and settlement are structured to accept one.

## Deployment checklist

1. Wrap the module in your namespace; replace the `"property-lease-gov"` keyset with your deployed, namespace-qualified governance keyset (**multi-sig recommended**; governance is upgrade-only and touches no funds).
2. Deploy and `create-table` (`properties`, `leases`, `buckets`).
3. Validate the end-to-end flow on **devnet** before mainnet — **mandatory**, not optional (the party-auth capabilities read on-chain tables; that class of bug is invisible in the REPL).

## Usage

```pact
;; landlord registers (8% tax / 7% repairs / 5% beneficiary; 80% residual)
(free.property-lease.register-property "unit-12"
  "k:landlord…" (read-keyset "landlord") "k:dao-treasury…" (read-keyset "benef")
  "ipfs://premises-record" 800 700 500)

;; landlord + tenant co-sign the lease (both scope their capability)
(free.property-lease.create-lease "unit-12-2026" "unit-12"
  "k:tenant…" (read-keyset "tenant") (hash "signed-lease.pdf")
  1000.0 30 5 25.0 1500.0
  (time "2026-01-01T00:00:00Z") (time "2026-07-01T00:00:00Z") 30 14)
```

## Testing

`examples/property-lease-test.repl` is self-contained (loads `coin` + interfaces from `registry/`):

```bash
cd contracts/library/property-lease/examples && pact property-lease-test.repl
```

83 assertions on a controlled clock: registration validation and immutable splits, mutual-assent lease signing (one-sided rejected), the deposit gate, on-time and late rent with exact bucket splits, guarded and permissionless withdrawals, scoped-signature isolation (a signature scoped to the wrong property is rejected), rounding-dust conservation, the guarantor payment path, notice and renewal bounds, and the full claim → settle lifecycle including double-claim and double-settle rejection. Conservation is asserted to 12 decimals throughout. CI runs this suite as a blocking check.

## Known limits

- **No arbiter (the headline limitation).** The landlord's deposit claim is unilateral within its cap and window — see [Trust model](#trust-model).
- **Day-based periods, not calendar months.** `pay-rent` advances `paid-through` by `period-days`; a "monthly" lease drifts against calendar months. Model your periods in days.
- **No partial payments and no refunds.** `pay-rent` covers exactly one whole period; `give-notice` cannot cut below `paid-through` (rent already paid is not refunded).
- **KDA only.** Rent, deposits, and payouts are native KDA (`coin`). Supporting an arbitrary `fungible-v2` token would be a v2 generalization.
- **The TAX bucket is savings accounting, not legal remittance.** It earmarks funds and lets the landlord withdraw to a tax authority; it does not file or remit anything.
- **The off-chain document is the legal contract.** On-chain state anchors its hash and moves money; it does not encode tenancy terms, habitability, or local law.
- **One payout per payee per transaction.** coin's managed transfer capability is keyed by (sender, receiver) — so two vault payouts to the *same* account in one transaction collide and abort. `settle-deposit` handles the landlord-is-tenant case internally; if you batch calls (e.g. settling two leases that share a landlord), put each in its own transaction.
- **Validate on devnet before mainnet** (see the deployment checklist).
- Governance holds upgrade power. Pin the deployed module hash you audited; use a multi-sig governance keyset.

## License

Apache-2.0
