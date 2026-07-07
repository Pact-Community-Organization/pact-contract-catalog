# ADR-018: A Kadena NFT interface standard (nft-asset-v1 / nft-market-v1 / nft-xchain-v1)

**Status:** ACCEPTED (2026-07-07 — founder decision: shared-standard-surface v1; multi-currency
market; implementation-private fee routing; adopt in both royalty-sale and Gallery)
**Date:** 2026-07-07
**Decider:** Solo developer (Smart Pacts); founder set the scope and the two open forks
**Relates to:** ADR-017 (Gallery is the production implementer), ADR-001 (catalog/registry layout),
the Marmalade V2 security & architecture analysis (2026-07-06, the source of the S-clauses)

---

## 1. Context

Founder direction (2026-07-07): *"we still want to create the standards. Future companies will take
this product from the Pact organization or from us and create their own marketplace; we want all
marketplaces to be compatible between them. We want to properly set the standards"* — and the
standard should reflect *what the public expects from markets* (per the Marmalade V2 analysis).

"Multiple future implementers we do not control" is exactly the condition under which a Pact
interface earns its existence. Until now both NFT contracts were single-implementation modules, so
an interface would have been a banned one-impl abstraction. That changed with this direction.

Two facts shaped every decision:

1. **Interfaces cannot be upgraded** (`CannotUpgradeInterface`). Whatever v1 freezes is permanent
   on-chain; the only escape is publishing `-v2` and migrating an ecosystem (the `fungible-v1` →
   `fungible-v2` precedent). So v1 must be small, version-suffixed, and validated against ≥2
   independent implementations before any public deploy.
2. **The public expectation** (Marmalade analysis §1): creators want royalties that hold, buyers
   want to receive exactly what they paid for, owners want to move their own property. The one
   design on any chain that enforces all three without a trusted marketplace is Kadena's escrow
   model. The standard's job is to make that model portable across marketplaces, not to reinvent it.

## 2. Decision

### 2.1 Scope — "compatible" means shared surface, not shared custody (founder fork #1)
v1 delivers **compatibility of tooling and semantics**: every marketplace exposes the same views,
emits the same events, and obeys the same royalty/settlement rules, so one wallet, one indexer, one
aggregator work across all of them. Each marketplace's tokens live in its own module (the
`fungible-v2` model — every contract is its own ledger, yet one wallet handles them all). **Full
asset portability across a shared neutral ledger is explicitly NOT a v1 goal** (that is Marmalade's
problem space and reopens royalty-bypass / modref-trust); if the ecosystem ever needs it, that is a
v2 track with its own ADR. Versioning means choosing shared-surface now does not foreclose it.

### 2.2 Three layered interfaces
Standardize what tooling depends on; keep the trusted economic surface small and private (the
Marmalade lesson — over-coupling the policy-manager was its core mistake).

- **`nft-asset-v1`** (required) — the token: `mint`, `transfer`, ownership/royalty views
  (`get-token`, `owner-of`, `is-listed`), the shared `token` schema, and the event vocabulary
  (`MINTED` with initial owner, `TRANSFERRED`, `SOLD`). This is the indexer contract.
- **`nft-market-v1`** (if sellable; requires the asset interface) — fixed-price sale:
  `list-token(id, price, currency)`, `delist`, `buy(id, buyer, buyer-guard)`, `get-listing`,
  `get-escrow-account`, plus `LISTED`/`DELISTED`. Settlement MUST be single-point and
  conservation-asserted; economics MUST come from state, never the buy transaction.
- **`nft-xchain-v1`** (opt-in; requires the asset interface) — two-step SPV `move-crosschain` +
  `MOVE-INITIATED`/`MOVE-COMPLETED`. Where cross-marketplace cross-chain compatibility lives.

### 2.3 Currency: multi-currency in the market interface (founder fork #2a)
`list-token` carries `currency:module{fungible-v2}`; the price is denominated in it. A KDA-only
marketplace always passes `coin`. This matches royalty-sale (already multi-currency) and the
analysis's POL-4 finding (*parameterize the settlement fungible*), and keeps stable-denominated
sales possible without a second interface. Gallery, being KDA-revenue, accepts the arg but enforces
`currency == coin`.

### 2.4 Fee routing: implementation-private (founder fork #2b)
The interface standardizes the fee *rate* and *amount* (via `LISTED.fee-bps` and `SOLD.fee`) but NOT
how the fee **payee** is chosen. Gallery routes to a fixed SPT revenue account; royalty-sale lets
the seller name a marketplace. Both conform; tooling sees fees through events. Fixing fee routing
into the ABI would be exactly the over-coupling to avoid.

### 2.5 The normative rules (SPEC.md, S1–S6)
The signatures fix shape; six MUST-clauses fix behavior, each traced to a Marmalade failure mode:
S1 fail-closed inputs (POL-1), S2 one conservation-asserted settlement + dust-floor listing ban
(ARCH-1/POL-3), S3 economics-from-state (ARCH-2), S4 explicit robust sale-only (POL-2), S5
cross-chain royalty non-bypass, S6 no-rollback/bless-in-flight/devnet-proven.

### 2.6 Governance home
The interfaces live in the **PCO catalog** (`contracts/standards/`), the neutral standards body —
a standard cannot credibly live in one competitor's namespace. `royalty-sale` is the MIT reference
implementation; `smartpacts-gallery` is the production implementation. Neither defines the standard;
SPEC.md + the three interfaces do.

## 3. Conformance — proven, not asserted

A `conformance-driver` module knows only `module{nft-asset-v1}` / `module{nft-market-v1}`; the
conformance suites drive each candidate **through that modref**, so passing proves the surface is
polymorphically usable, not merely name-compatible. Run against **both** implementations:

| Implementation | asset | market | xchain | Evidence |
|---|---|---|---|---|
| `royalty-sale` (reference) | ✓ | ✓ | n/a | `royalty-sale-conformance.repl` — PASS (modref-driven) |
| `smartpacts-gallery` (production) | ✓ | ✓ | ✓ | `gallery-conformance.repl` — PASS; **devnet 31/31** incl. SPV round trip |

The conformance suite already earned its keep: it caught the reference implementation
(`royalty-sale`) violating **S2** — it lacked the dust-price listing guard the SPEC requires (and
that Gallery already had via audit F3). Fixed in `list-token-with-fee`; the standard tightened the
reference, which is the point of a conformance gate.

## 4. On-chain findings (KDA-CE)

- **Root namespace is locked.** `"Cannot install modules in the root namespace"` — only genesis
  interfaces (`fungible-v2`, `fungible-xchain-v1`) live there. The standard interfaces therefore
  deploy **into the implementer's namespace**, and a module + interface in the same namespace
  resolve by **bare name** (no source qualification needed). On testnet the interfaces live in the
  Gallery namespace alongside the module. Proven on the devnet campaign.
- **Interface conformance requires exact event signatures.** An implementer MUST declare a `defcap`
  for every `@event` in the interface, with matching parameter list AND `:bool` return — a mismatch
  fails to load. Views may keep a richer private table schema but MUST project onto the interface's
  named schema.
- Gas: Gallery deploy rose ~1.5k (interface machinery) to 24,803 — well under the 150k ceiling.

## 5. Consequences

**Positive.** A real standard, validated against two independently-built marketplaces through a
modref before any public deploy; Gallery adopts it before its testnet port (nothing shipped is
wasted — the module just gains `implements` lines); third parties demonstrate conformance by passing
the same suite; the standard is small and every clause is mechanically checkable.

**Costs / non-goals.** No auctions, offers/bids, bundles, lazy minting, fractional ownership, shared
cross-marketplace ledger, or metadata schema beyond a `uri` string in v1 — each is a candidate
additive interface so v1 stays small. Conforming tokens are NOT visible to Marmalade-aware wallets
(different, marmalade-free type family — a deliberate founder directive), only to standard-aware
tooling.

**Deploy gates (unchanged from ADR-017).** Testnet = the v2 release line
(`n_d97ffd2ca290429b5dc85ce551a8d07d038e9641`): interfaces + module deploy together, all gates
re-run, hash-verify before announcing cross-chain moves, bless on every upgrade. Mainnet +
standards-body publication are counsel-gated (D7 flag #5). Publishing the interfaces publicly is the
moment their signatures freeze forever — do it only after the testnet validation confirms the shape.
