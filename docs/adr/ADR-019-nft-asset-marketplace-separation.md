# ADR-019: NFT asset/marketplace separation — self-sovereign per-NFT modules, consignment across marketplaces

**Status:** PROPOSED (2026-07-07 — founder decisions: one module per NFT, frozen at mint,
consignment one-marketplace-at-a-time; **PCO owns the standard, Smart Pacts Gallery is the first
marketplace built on it**)
**Date:** 2026-07-07
**Decider:** Solo developer (Smart Pacts); founder set the model and the two forks
**Supersedes:** the "shared surface, NOT shared custody" stance of **ADR-018 §2.1** (the exact
limitation this ADR removes). ADR-018's interfaces are refactored, not discarded — see §7.
**Relates to:** ADR-017 (the current Gallery), ADR-001 (PCO catalog/registry layout), the
Marmalade V2 analysis (the custody/authority lessons this design applies).

---

## 1. Context — the flaw ADR-018 left

ADR-018 gave marketplaces a shared *surface* (one wallet/indexer across implementers) but explicitly
NOT shared *custody*: each marketplace owns its own token ledger, so an NFT minted in Gallery lives as
a row *inside* the Gallery module. The founder identified the consequence directly: **a Gallery NFT
cannot be moved to another marketplace and sold there** — "the painting and the gallery are the same
object." The cross-marketplace investigation confirmed it: the ledgers are disjoint; a second
marketplace can only *broker* a Gallery sale, never take the token as its own consignable inventory.

The founder's target is the real-world model: *a painting is created in a studio, consigned to any
gallery to be sold, and once sold the new owner keeps it in a wallet or consigns it to another gallery
— on the internet, to many galleries over time.* The asset must be **separable from the marketplace**.

## 2. Decision

### 2.1 The asset is separate from the marketplace, and IS the source of truth
An NFT is **its own module** (founder decision), deployed by and in the **artist's own namespace**,
implementing a PCO `nft-asset` interface. The module owns: its current owner, its immutable creator
royalty, and the single active **consignment** (which marketplace guard may currently sell it, at what
price). Marketplaces own **no tokens**. The NFT pays its **own royalty** on every sale, so the royalty
is enforced by the asset regardless of which marketplace triggers the sale — a marketplace can never
skim or bypass it.

Gas for deploying a per-NFT module is the **artist's** cost, not the platform's (founder), which
removes the scaling objection to one-module-per-NFT: the platform never pays per-mint.

### 2.2 Frozen at mint
Royalty rate, creator payee, and supply are **immutable after mint**, enforced by the module's own
`GOVERNANCE`: once minted, the governance cap refuses every upgrade (a `frozen` flag the governance
body checks). The artist governs *deployment*, but **cannot change the economic terms after mint** —
so buyers and marketplaces can trust them. Metadata mutability is out of scope for v1 (default: also
frozen; a later ADR may allow display-only metadata updates).

*Proven:* a minted module's upgrade attempt aborts with the frozen guard (`GOV` enforces
`(not frozen)`), so the terms are genuinely immutable even to the artist-governor.

### 2.3 Consignment — one marketplace at a time, enforced by the asset
To sell, the owner **consigns** the NFT to exactly one marketplace: `list-for-sale(mkt-guard, price)`
records *that marketplace's guard* and the price on the NFT. Only the consigned marketplace's guard
can trigger `buy`. To list elsewhere, the owner re-consigns (records a different guard), which
atomically supersedes the first — the NFT stores exactly **one** active consignment, so two
marketplaces can never both sell it. "The others fail" happens deterministically at **consign** time,
not as a same-block refund race. This is the real-world model and the SAFE version of the founder's
"register on many, first sale wins": no marketplace ever holds simultaneous authority, so the
Marmalade multi-authority theft class (ADR-018's ARCH-1/ARCH-4 lesson) cannot arise.

The owner's three states map to the painting: **in the wallet** (not consigned), **in one gallery**
(consigned to one marketplace), **moved to another gallery** (re-consigned) — and after a sale the new
owner chooses again.

### 2.4 The two Pact-5 constraints this design MUST respect (proven, load-bearing)
Cross-module/cross-namespace authority in Pact 5 blocks the naive shapes; the working patterns are:

- **A marketplace cannot acquire the NFT's capabilities.** Acquiring a cap defined in another module
  requires that module's admin, which a foreign marketplace lacks (`"Module admin necessary … not
  acquired"`). Therefore the NFT authorizes a sale via an **`enforce-guard` on the recorded
  consignment guard**, NOT via a capability the caller acquires. The NFT exposes a **public `buy`**;
  its guard check passes only when the consigned marketplace is the one calling.
- **A caller cannot acquire the marketplace's SELL cap externally** (same rule, other side).
  Therefore the marketplace exposes a **public `execute-sale`** that acquires its own `SELL` cap
  *internally* and calls `nft::buy`, taking the NFT as a **`module{nft-asset}` modref parameter**
  (never a hard-coded module name — that would couple one marketplace to one NFT).

*Proven cross-namespace:* an `art.nft-*` module is sold by a `mkt.gallery` module through a modref,
authorized by the consignment guard, with the royalty paid inside the NFT — end to end.

### 2.5 Settlement
The buyer signs a single `coin.TRANSFER` of the price into the **NFT's own capability-guarded escrow**;
the NFT splits it — royalty → creator (fixed at mint), marketplace fee → the marketplace's fee account
(the marketplace's own policy, taken as a parameter/authority, not baked into the asset), remainder →
seller — and asserts the escrow returns to baseline (the conservation guarantee carried over from
Gallery). Merged payouts handle payee collisions (creator == seller, etc.), unchanged from ADR-017/018.

## 3. Ownership of the standard vs the marketplace (founder)

- **PCO owns the standard.** The `nft-asset` interface, the per-NFT/consignment architecture, and the
  reference `nft-single` template live in the PCO catalog — the neutral standards body (as ADR-018's
  interfaces already do). Any artist, any marketplace, anywhere builds against it.
- **Smart Pacts Gallery is the FIRST marketplace** built on the standard — the reference *consumer*,
  not the definition. It proves the open standard works and is the first of many independently-built
  marketplaces.

## 4. The `nft-asset` interface (surface, not final signatures)

Refines ADR-018's `nft-asset-v1` for self-custody:
- `get-owner`, `get-creator`, `get-royalty-bps`, `get-price`, `is-listed`, `is-frozen` — views.
- `transfer(receiver, receiver-guard)` — free, owner-authorized, only when not consigned.
- `list-for-sale(mkt-guard, price[, currency])` — owner consigns to one marketplace.
- `delist()` — owner revokes the consignment (painting returns to the wallet).
- `buy(buyer, buyer-guard, fee-account, fee-guard, fee-bps)` — public; enforces the consignment guard;
  pays royalty (from state) + marketplace fee (from the call, but capped/validated) + seller; asserts
  conservation. Economics-from-state (ADR-018 S3) still holds: royalty/price come from the NFT, never
  the tx.
- Events: `MINTED`, `LISTED`(consigned-to), `DELISTED`, `SOLD`, `TRANSFERRED` — sufficient for one
  cross-marketplace indexer to follow a painting from studio through every gallery and wallet.
- Marketplace-side interface `nft-marketplace`: `execute-sale(nft:module{nft-asset}, …)` + the
  marketplace's guard accessor.

Cross-chain (`nft-xchain`) is carried over but re-examined: a self-sovereign per-NFT module doing SPV
moves is a design question deferred to the implementation ADR/spike (§8).

## 5. Consequences

**Positive.** The painting model, realized: an NFT is created once, consigned to any marketplace in any
namespace, sold with the creator's royalty enforced by the asset, and re-consigned or held at the new
owner's choice. Marketplaces are permissionless and independent; the royalty is inviolable; "one
gallery at a time" is deterministic and race-free; the platform pays no per-mint gas.

**Costs / risks to resolve in the spike.** More moving parts (asset + marketplace modules, two
public-entry patterns to get exactly right — see §2.4); per-NFT module deploy UX for artists; the
cross-chain story for self-sovereign assets; how a marketplace's fee is bounded so a hostile
marketplace can't set an absurd fee (the NFT should cap/validate the fee it accepts). Each is a spike
item, not a blocker.

**Supersedes** ADR-018 §2.1 (shared-surface-not-custody). ADR-018's interfaces are refactored into the
asset/marketplace split (§7), not thrown away — the conformance-by-modref discipline and the S1–S6
clauses carry over.

## 6. Fate of the current Gallery (ADR-017/018)

`smartpacts-gallery` (single module, token-as-row) is **refactored into a marketplace-only** sale
contract: it keeps its SPT-revenue fee routing and cross-chain handling but **stops owning tokens** —
it sells NFTs from the per-NFT modules via `execute-sale`. Its ADR-017 testnet-port plan is superseded
by this architecture; the port target becomes "deploy the first marketplace + the reference nft-single
template," not "deploy the token-owning Gallery." The already-merged Gallery remains valid as the
proof-of-economics artifact; it is not deleted, it evolves.

## 7. Migration of ADR-018

- `nft-asset-v1` → `nft-asset` (self-custody: adds `list-for-sale`/`delist`/`buy` with the consignment
  guard; ownership is authoritative in the asset).
- `nft-market-v1` → `nft-marketplace` (a sale contract that takes `module{nft-asset}` and calls it;
  owns no tokens).
- `nft-xchain-v1` → re-examined for self-sovereign assets (spike).
- The conformance-driver/modref discipline and the S1–S6 normative clauses are retained and re-pointed.

## 8. Next (gated on this ADR's acceptance)

1. ✅ **DONE — runnable spike** (`contracts/standards/spike-adr019/`, `SPIKE.md`): `nft-single` +
   `simple-market` (deployed into TWO namespaces) + `nft-asset`/`nft-marketplace` interfaces, and
   `spike.repl` proving mint → freeze (upgrade rejected) → consign to gallery A → non-consignee
   rejected → cross-namespace sale (royalty paid by the asset) → re-consign to gallery B (A
   superseded) → resale (royalty to the ORIGINAL creator) → full 12-dp reconciliation + global
   conservation. **Load successful, 0 FAILURE, static gate clean (1 dispositioned dependency-load
   WARN).** The design is proven buildable on Kadena today.
2. Then the interface + reference-template PRs to the PCO catalog (the standard), and the Gallery
   refactor to a marketplace (Smart Pacts, the first consumer).
3. Testnet/mainnet + public standard publication remain counsel-gated (D7 flag #5); publishing the
   interfaces freezes their signatures forever — only after the spike + testnet validation.
