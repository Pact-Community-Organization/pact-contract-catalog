# Kadena NFT Standard v1 — Normative Specification

**Status:** proposed · **Version:** 1 · **Language:** Pact 5.4ce / KDA-CE

Three interfaces define a 1-of-1 NFT with enforceable creator royalties,
trustless fixed-price sales, and cross-chain portability, such that independent
marketplaces built by different teams are **compatible**: one wallet, one
indexer, and one aggregator work across every conforming implementation.

| Interface | File | Role | Required? |
|---|---|---|---|
| `nft-asset-v1` | [nft-asset-v1.pact](nft-asset-v1.pact) | the token, ownership, royalty terms, event vocabulary | yes |
| `nft-market-v1` | [nft-market-v1.pact](nft-market-v1.pact) | fixed-price sale with conservation-asserted escrow | if the token is sellable; requires `nft-asset-v1` |
| `nft-xchain-v1` | [nft-xchain-v1.pact](nft-xchain-v1.pact) | two-step SPV cross-chain relocation | opt-in; requires `nft-asset-v1` |

Interfaces in Pact **cannot be upgraded** (`CannotUpgradeInterface`). Every
identifier here is version-suffixed; a breaking change ships as `-v2` and an
ecosystem migrates, exactly as `fungible-v1` → `fungible-v2` did. Do not treat
v1 as a draft to be edited in place once anything implements it on a public
network.

## What "compatible" means in v1

**Compatibility of tooling and semantics, not of custody.** A conforming
token lives in the module that minted it; a competing marketplace does not take
custody of it. But because every implementation exposes the same views, emits
the same events, and obeys the same royalty and settlement rules, external
software treats them uniformly. This is the `fungible-v2` model — every token
contract is its own ledger, yet one wallet handles them all. Full asset
portability across a shared ledger (a token minted in marketplace A, held in
marketplace B's ledger) is explicitly **not** a v1 goal; if the ecosystem ever
needs it, that is a v2 track with its own shared-ledger design.

## The rules (normative)

The interface signatures fix the *shape*. These clauses fix the *behavior* a
signature cannot express. An implementation that matches the signatures but
violates a clause is **not conforming**. Each clause traces to a failure mode
observed in a deployed Kadena NFT stack (the Marmalade V2 analysis, 2026-07-06);
the reference implementation `royalty-sale` and the production implementation
`smartpacts-gallery` both satisfy all of them.

### S1 — Fail closed on every input
Guards and account/guard pairs are **required**, never defaulted. A missing or
malformed guard MUST abort the operation; it MUST NOT degrade to a permissive
guard. Every account paired with a guard MUST be validated as a principal
(`validate-principal`) — owner, creator, buyer, receiver, and any fee payee.
*Rationale:* a deployed guard policy set absent guards to a `true`-body guard
via `(try GUARD_SUCCESS …)`, making forgetful tokens transferable by anyone.
Never wrap guard/spec parsing in a `try` that can fall through to permissive.

### S2 — One settlement, conservation-asserted
A sale MUST settle in a **single** function that computes every cut — royalty,
fee, seller remainder — explicitly, and MUST assert
`escrow-in = Σ payouts-out` to the sale currency's full precision. No capability
that grants spend authority over the escrow MUST span independent hooks or
policies; there MUST be exactly one point at which conservation is checked. A
royalty-bearing token MUST NOT be listable at a price whose floored royalty is
zero (a dust price is otherwise a royalty-free ownership change through `buy`).
*Rationale:* the deployed manager defined conservation as "whatever survives the
policy loop," trusting every stacked policy; one hostile policy sharing the
escrow capability could skim, and the seller silently absorbed the shortfall.

### S3 — Economics live on-chain, never in the buy transaction
Royalty rate, fee rate, price, and currency MUST be bound to the token or the
listing at creation/list time and read from state at settlement. No parameter
that affects the money moved MUST be read from the transaction that triggers the
payment (no `read-msg` of a fee, rate, or payee inside `buy`). The fee rate a
sale charges MUST be the rate **snapshotted on the listing**, so a post-listing
admin rate change never alters a live sale and a buyer cannot zero the fee.
*Rationale:* the deployed manager read the marketplace fee percentage and payee
straight from the buyer's payload — any buyer could set the fee to `0.0`.
*Conformance note:* because no signature can forbid a `read-msg` in a `buy`
body, S3 is checked **adversarially** — the conformance suite drives `buy` with
a malicious payload of economic overrides (fee, royalty, price, payee) and
asserts the settlement split is the state-derived one. A conformance run without
this negative vector does not establish S3.

### S4 — "Sale-only" is an explicit, robust property
Royalty enforcement for a token that must never move royalty-free is expressed
as an explicit token property (`transferable:false`), chosen by the creator at
mint, not as a blanket transfer ban bolted on by a composed policy. A sale-only
token MUST reject free `transfer`, and its royalty MUST be enforced at
**settlement** (S2), not by making all movement impossible. No later action MUST
be able to silently void the property.
*Rationale:* the deployed royalty policy enforced royalties by making
`enforce-transfer` unconditionally fail, which both blocked legitimate gifting
and could be composed away by a second transfer-enabling policy.

### S5 — Cross-chain moves MUST NOT bypass the royalty
(Applies to `nft-xchain-v1` implementers.) A cross-chain relocation MUST NOT
change the beneficial owner of a **sale-only** token: such a token may relocate
only to its own current owner (same account **and** same guard). A transferable
token's receiver MUST be a principal account. Listings MUST NOT travel across a
move. Origin-distinct token ids MUST make a cross-chain arrival unable to
collide with or overwrite a live token on the target chain.
*Rationale:* without this, "move to a new owner on another chain" would be a
royalty-free sale — the exact bypass S2/S4 exist to prevent, reintroduced by the
transport layer.

### S6 — Cross-chain integrity: no rollback, bless in flight, devnet-proven
(Applies to `nft-xchain-v1` implementers.) A move is a two-step SPV defpact with
**no rollback** across the yield: step 0 tombstones the token on the source
chain and yields its full record; step 1 writes it resident on the target chain.
An initiated move is completed by continuation only. An upgrade performed while
moves may be in flight MUST `bless` the prior module hash so pending
continuations remain valid. Cross-chain behavior MUST be validated on a
multi-chain devnet with real SPV — SPV is unsupported in the bare REPL, so a
green cross-chain `.repl` is **not** evidence (it is a false positive).

## Conformance

A module conforms to interface X iff:
1. it declares `(implements X)` and loads (Pact checks every signature and
   schema matches exactly — a mismatch fails to load); **and**
2. it passes the conformance suite for X (see
   [conformance/README.md](conformance/README.md)), which drives the module
   **through a `module{X}` reference** — proving the surface is usable
   polymorphically, not merely name-compatible — and asserts the S-clauses that
   are REPL-observable (S1–S4, and the same-chain guards of S5); **and**
3. for `nft-xchain-v1`, it additionally passes a multi-chain devnet run of the
   SPV round trip (S5 target-side, S6) — the REPL cannot prove this.

The conformance suite is written against the interface, not against any one
module, and is run against **both** `royalty-sale` (the reference
implementation) and `smartpacts-gallery` (the production implementation). A
third-party marketplace demonstrates conformance by passing the same suite.

## Reference and production implementations

- **`royalty-sale`** (`contracts/library/royalty-sale/`) — the MIT reference
  implementation: minimal, multi-currency, seller-named marketplace fee.
- **`smartpacts-gallery`** (github.com/SmartPacts/gallery) — the production
  implementation operated by Smart Pacts: KDA sales, platform fee routed to the
  SPT revenue account, cross-chain enabled.

Both are conformance-checked members, not the definition. The definition is this
document plus the three interfaces.

## Non-goals for v1 (candidates for later interfaces)

Auctions and offers/bids; bundles/collections as first-class sale units; lazy
minting; fractional ownership; a shared cross-marketplace ledger (full
portability); metadata schema standardization beyond a `uri` string. Each is a
separate, additive interface so v1 stays small and every clause above stays
mechanically checkable.
