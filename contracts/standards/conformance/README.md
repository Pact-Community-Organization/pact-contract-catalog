# NFT standard — conformance

A candidate module conforms to the Kadena NFT standard (see [../SPEC.md](../SPEC.md)) iff:

1. it declares `(implements <pco-ns>.nft-asset-v1)` (and `nft-market-v1` / `nft-xchain-v1` as
   applicable) **fully qualified against the PCO namespace the standard is published in**
   (testnet06: `n_e82dd10f74b7e8c253553de95629fdfa35cf8379`) and **loads** — Pact checks every
   function/cap/schema signature matches exactly; and
2. it passes the **conformance suite** below, which drives the module **through a
   `module{<pco-ns>.X}` reference** — proving the surface is polymorphically usable, not merely
   name-compatible; and
3. for `nft-xchain-v1`, it additionally passes a **multi-chain devnet** run of the SPV round trip
   (the REPL cannot prove SPV — a green cross-chain `.repl` is a false positive).

A module that implements a *private copy* of the interfaces does **not** conform: same-text
interfaces in different namespaces are different types in Pact, so tooling that dispatches
`module{<pco-ns>.nft-asset-v1}` cannot use it.

## How it works

[`conformance-driver.pact`](conformance-driver.pact) is a module that knows only
`module{<pco-ns>.nft-asset-v1}` / `module{<pco-ns>.nft-market-v1}` — it never names a concrete
implementation. Each `d-*` function forwards one interface call through the modref. A conformance
suite names the candidate module **once** (as the modref argument) and makes every assertion through
the driver, so the assertions are implementation-agnostic. If a suite passes, the candidate is
usable through the standard by any tool that knows only the interface.

The suites reproduce the real deployment topology inside the REPL: the interfaces load into the PCO
namespace, the driver loads into `user`, and the candidate loads into its own namespace — every
dispatch crosses namespaces exactly as it does on-chain. The PCO namespace literal in the driver
and suites is the testnet06 value; targeting another network means patching that one literal to
that network's published PCO namespace (the same deploy-literal treatment as an admin keyset name).

## Suites

| Suite | Candidate | Covers | Run |
|---|---|---|---|
| [`royalty-sale-conformance.repl`](royalty-sale-conformance.repl) | `royalty-sale` (reference) | asset + market (S1–S4) | `pact contracts/standards/conformance/royalty-sale-conformance.repl` |
| `gallery-conformance.repl` (in the gallery repo) | `smartpacts-gallery` (production) | asset + market; xchain on devnet | see the gallery repo |

Both pass the **same** modref-driven assertions — two independently-built marketplaces, one
interface. That is the "compatible between marketplaces" guarantee, demonstrated rather than claimed.

## Writing a conformance suite for your marketplace

1. Load `coin`, then the three interfaces **into the PCO namespace** (in the REPL:
   `define-namespace` the PCO namespace name, `(namespace ...)`, load the interface files — signed
   as the namespace owner), then `conformance-driver` into `user`.
2. Deploy your module into its own namespace, with the `implements` lines fully qualified.
3. Name your module **once** and pass it to each `user.conformance-driver.d-*` call; assert only on
   the projected interface schemas and the event amounts.
4. If you implement `nft-xchain-v1`, add a multi-chain devnet run for the SPV round trip.

On a live network you do not deploy the interfaces — they are already published in the PCO
namespace; your module simply implements them qualified.

## Note on the reference implementation

This suite already tightened the reference: `royalty-sale` originally lacked the S2 dust-price
listing guard (a price whose floored royalty is zero is a royalty-free ownership change). The
conformance run flagged it; it was fixed in `list-token-with-fee`. A conformance gate that never
fails is not testing anything.
