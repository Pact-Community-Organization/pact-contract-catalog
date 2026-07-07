# NFT consignment spike — the painting model, proven

> **OUTCOME (2026-07-07): mechanics proven; identity model not adopted.** The production NFT build
> went a different way — a **shared-ledger framework** (the `nft` namespace series) — because token
> identity is the one property a self-sovereign per-NFT module can never anchor: anyone can deploy a
> lookalike module claiming any provenance, so forgery/double-mint impossibility requires an id
> derived and enforced in one shared ledger. What this spike proved **stands as reference**:
> cross-namespace sale authorization via a recorded consignment guard (`enforce-guard` on state, not
> a foreign capability), frozen-after-mint economics, and a marketplace that sells what it does not
> own. Read it as a proving-ground record, not the adopted architecture.

**Result: the consignment mechanics work.** An NFT deployed as its own module in an artist's namespace
can be consigned to a marketplace in a *different* namespace, sold there with the creator royalty paid
by the asset, then re-consigned by the new owner to a *third* namespace's marketplace and sold again —
the same painting, gallery to gallery, royalty to the original creator every time, and no marketplace
able to skim it.

## What the spike contains

| File | Role |
|---|---|
| `nft-asset.pact` | the self-custody asset interface (owner/royalty/consignment authoritative in the asset) |
| `nft-marketplace.pact` | the sale-contract interface (owns no tokens; sells any `module{nft-asset}`) |
| `nft-single.pact` | a reference **one-NFT-per-module** implementation — artist-owned, frozen at mint, own escrow, pays its own royalty |
| `simple-market.pact` | a reference marketplace — deployed twice, into two different namespaces, each with its own fee |
| `spike.repl` | the end-to-end proof (below) |

## What it proves (spike.repl — Load successful, 0 FAILURE)

The scenario, all reconciled to 12 dp:

1. **Self-custody + frozen at mint.** The NFT is minted in namespace `art` with a 10% royalty to the
   artist. After mint, acquiring the module's `GOVERNANCE` (its upgrade authority) **aborts** with
   "frozen" — the artist governs deployment but can never change royalty/creator/terms afterward.
2. **Consign to gallery A** (namespace `gala`, 2.5% fee). The owner records gallery A's guard on the
   NFT via `list-for-sale`.
3. **A non-consigned marketplace cannot sell.** Gallery B (namespace `galb`) calling `execute-sale`
   on the same NFT is **rejected** — its `execute-sale` can only acquire *its own* `SELL`, which
   doesn't satisfy the consignment guard recorded for gallery A (`require-capability: not granted`).
4. **Sale 1 through gallery A** (cross-namespace, via a `module{nft-asset}` modref): price 100 →
   royalty 10 to the artist (creator), fee 2.5 to gallery A, proceeds 87.5 to the artist (seller).
   Creator == seller here, so the legs **merge** → the artist nets 97.5. Escrow returns to baseline.
5. **Re-consign to gallery B** — the new owner (collector-1) moves the painting to a different
   marketplace in a different namespace. The prior consignment to gallery A is **superseded**:
   gallery A can no longer sell it (verified — `not granted`). Exactly one marketplace is ever
   authorized.
6. **Sale 2 through gallery B**: price 200 → royalty 20 to the **original artist** (not the seller),
   fee 10 to gallery B, proceeds 170 to collector-1. The creator is paid the royalty on the resale,
   on a different marketplace, in a different namespace.
7. **Full reconciliation** (absolute balances): artist 117.5 (97.5 + 20 resale royalty), collector-1
   1070 (1000 − 100 + 170), collector-2 800 (1000 − 200), gallery A 2.5, gallery B 10. **Global coin
   conserved** to 2000 across all accounts.

## The two Pact-5 facts the design rests on (both exercised here)

1. **A marketplace cannot acquire the NFT's capabilities** (that needs the NFT module's admin). So the
   NFT's `buy` authorizes via an **`enforce-guard` on the recorded consignment guard**, not a cap the
   caller acquires. `buy` is public; only the consigned marketplace satisfies the guard.
2. **A caller cannot acquire the marketplace's `SELL` cap externally.** So the marketplace exposes a
   public `execute-sale` that acquires `SELL` **internally** and calls `nft::buy`, taking the NFT as a
   **modref parameter** — one marketplace sells any conforming NFT.

Because the guard an owner consigns to is built from the marketplace's *own* `SELL` cap, only that
marketplace's `execute-sale` can ever satisfy it — which is simultaneously the authorization mechanism
AND the "one marketplace at a time / others fail" enforcement. Re-consigning records a different
guard, atomically superseding the prior one.

## Safety properties demonstrated

- **Royalty inviolable** — paid inside the NFT module on every sale; no marketplace can redirect or
  skip it (it isn't a parameter a marketplace controls).
- **Fee capped by the asset** — `nft-single` rejects any `fee-bps` above its own `MAX-FEE-BPS` (10%),
  so a hostile marketplace can't set an absurd fee on someone's NFT.
- **Conservation** — every sale asserts the escrow returns to its pre-sale baseline; global coin is
  conserved.
- **Frozen terms** — the artist-governor cannot change royalty/creator after mint.
- **One consignment at a time** — deterministic at consign time; no cross-marketplace race.

## Gates

- `spike.repl`: **Load successful, 0 FAILURE**.
- Static gate: 0 VIOLATIONs on the modules; **1 dispositioned WARN** — `nft-marketplace.pact` fails a
  *bare* `pact <file>` load because it references `std.nft-asset` (a dependency the `.repl` harness
  loads first). Same benign dependency-load class as any interface with a cross-namespace dependency;
  the file loads and runs correctly in the harness. These are spike files (a proving ground), not
  published production standard files.

## What the spike deliberately did NOT cover (for the production build)

- **Cross-chain** for self-sovereign per-NFT modules (SPV move of an nft-single) — deferred to the
  implementation phase; it is the main open design question.
- **Devnet** (root namespace is locked on KDA-CE, so on a real node the interfaces + NFT + markets
  deploy into real namespaces exactly as the spike does in-REPL; a devnet campaign is the next
  evidence tier, as for every prior module).
- **The marketplace refactor** (an existing token-owning marketplace becomes a sale contract that
  stops owning tokens) and the **fee-account-guard UX** (here the fee guard is captured at deploy;
  production wants the marketplace's live coin guard).
- Production interface **signature freeze** — these spike signatures are provisional; the published
  interface is finalized only after the production build + testnet validation (interfaces are
  `CannotUpgradeInterface`).

## Verdict

The consignment-via-guard mechanics — cross-namespace sale authorization, frozen terms, royalty paid
by the asset, one marketplace at a time — are **sound and buildable on Kadena today**, and the spike
demonstrates them end-to-end with conservation asserted. The **per-NFT-module identity model was not
carried into production** (see the outcome note at the top): the production build anchors identity in
a shared ledger, where the guard-based authorization patterns proven here continue to apply.
