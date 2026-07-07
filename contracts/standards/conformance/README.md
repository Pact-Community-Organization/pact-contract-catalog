# NFT standard — conformance

A candidate module conforms to the Kadena NFT standard (see [../SPEC.md](../SPEC.md)) iff:

1. it declares `(implements nft-asset-v1)` (and `nft-market-v1` / `nft-xchain-v1` as applicable) and
   **loads** — Pact checks every function/cap/schema signature matches exactly; and
2. it passes the **conformance suite** below, which drives the module **through a `module{X}`
   reference** — proving the surface is polymorphically usable, not merely name-compatible; and
3. for `nft-xchain-v1`, it additionally passes a **multi-chain devnet** run of the SPV round trip
   (the REPL cannot prove SPV — a green cross-chain `.repl` is a false positive).

## How it works

[`conformance-driver.pact`](conformance-driver.pact) is a module that knows only
`module{nft-asset-v1}` / `module{nft-market-v1}` — it never names a concrete implementation. Each
`d-*` function forwards one interface call through the modref. A conformance suite names the
candidate module **once** (as the modref argument) and makes every assertion through the driver, so
the assertions are implementation-agnostic. If a suite passes, the candidate is usable through the
standard by any tool that knows only the interface.

## Suites

| Suite | Candidate | Covers | Run |
|---|---|---|---|
| [`royalty-sale-conformance.repl`](royalty-sale-conformance.repl) | `royalty-sale` (reference) | asset + market (S1–S4) | `pact contracts/standards/conformance/royalty-sale-conformance.repl` |
| `gallery-conformance.repl` (in the gallery repo) | `smartpacts-gallery` (production) | asset + market; xchain on devnet | see the gallery repo |

Both pass the **same** modref-driven assertions — two independently-built marketplaces, one
interface. That is the "compatible between marketplaces" guarantee, demonstrated rather than claimed.

## Writing a conformance suite for your marketplace

1. Load `coin` + the three interfaces + `conformance-driver`.
2. Deploy your module (into a namespace — KDA-CE locks root; a module and an interface in the same
   namespace resolve by bare name).
3. Name your module **once** and pass it to each `conformance-driver.d-*` call; assert only on the
   projected interface schemas and the event amounts.
4. If you implement `nft-xchain-v1`, add a multi-chain devnet run for the SPV round trip.

## Note on the reference implementation

This suite already tightened the reference: `royalty-sale` originally lacked the S2 dust-price
listing guard (a price whose floored royalty is zero is a royalty-free ownership change). The
conformance run flagged it; it was fixed in `list-token-with-fee`. A conformance gate that never
fails is not testing anything.
