# Per-NFT cross-chain spike — the painting moves chain to chain

**Result: it works.** A self-sovereign per-NFT module can move across Chainweb chains **without being
pre-deployed on every chain** — it is deployed on demand at the destination and mints itself from a
verified SPV proof of its departure at the source. Proven on a real multi-chain KDA-CE devnet, **14/14
checks pass**, including the two adversarial defenses (replay to the wrong chain, double-claim).

This resolves the one open design question the consignment spike deliberately deferred.

## The hard constraint, and the mechanism that solves it

A Pact module lives only on the chains it is deployed to, and the defpact **continuation** transport
(the current Gallery pattern) resumes the *same module* on the target chain — so it needs that module
already deployed everywhere. With one-module-per-NFT that would force an artist to deploy on all 20
chains up front, even for an NFT that only ever lives on one.

The other cross-chain mechanism is **`verify-spv "TXOUT"`** — a generic native that verifies a proof
of another chain's *transaction output* inside arbitrary code. We use it so a **freshly-deployed**
module on the target chain verifies a proof of the *departure* on the source chain and mints itself
from the proven payload. The artist pays deploy gas **only on chains the NFT actually visits**.

### The verify-spv recipe (established here, non-obvious)
- The source transaction whose proof you verify **must return an object** (a `TXOUT` proof verifies
  the tx *result*; a non-object result fails `verifySPV: command result not an object`).
- `@kadena/client`'s `pollCreateSpv` returns **base64(JSON)**; `verify-spv "TXOUT"` wants the **decoded
  JSON object** (`Buffer.from(proof,'base64')` → `JSON.parse` → pass as env-data).
- The SPV layer **natively binds the proof's target chain** — redeeming a proof on the wrong chain
  fails with `verifySPV: cannot redeem spv proof on wrong target chain`, independent of any app check.

## The model (residency + SPV-gated transition)

Each chain's copy of the NFT carries `present:bool` — true on exactly one chain, false everywhere it
has left. A move is two steps:

- **`depart(target-chain)`** on the source: owner-authorized; the token must be present here and not
  consigned; sets `present:false`; **returns** the move payload (origin-id, owner, creator, royalty,
  uri, source-chain, target-chain) as the transaction's object result.
- **`claim(proof)`** on the target: `verify-spv "TXOUT"` returns the proven payload; the module
  `insert`s itself `present:true` with the **same** creator/royalty/owner; enforces
  `target-chain == this-chain`.

**Double-residency is uncreatable by construction:** `present:true` on the target is reachable only by
consuming a proof that `present:false` was set on the source. The invariant is maintained by the
transition, not by a global cross-chain scan (which is impossible to do atomically — no contract can
synchronously read all 20 chains). A residency scan across chains remains useful as an off-chain
indexer sanity check, but it is not what enforces correctness.

## What the devnet campaign proves (`gallery/devnet/src/nft-xchain-spike.ts`, 14/14)

| Check | Result |
|---|---|
| X01 mint on c1 — present, owner=artist | PASS |
| X02 depart c1→c0 — succeeds, present=false on c1, payload returned | PASS |
| X03 claim on c0 (deploy-on-demand + verify-spv) — present=true, **owner/royalty/creator all preserved** | PASS |
| X04 replay the c0-proof onto c2 — **REJECTED** (SPV layer: "wrong target chain"; claim also enforces the chain) | PASS |
| X05 double-claim on c0 — **REJECTED** (`insert` fails: already present) | PASS |
| X06 sell the arrived NFT on c0 — buyer owns it; the **original creator** gets royalty+proceeds (97.5) on the sale chain | PASS |

Gas: NFT module deploy 17,654 (one-time, per chain visited, artist-paid); mint 235; depart/claim/sale
all well under the 150k ceiling.

## Interface finding (de-risks the freeze)

**Cross-chain needs NO change to the `nft-asset` interface.** `depart`/`claim` are module-level
extensions the *owner* calls; a marketplace never touches them (it only calls the standard `buy` via a
modref). So the provisional interface signatures are stable regardless of the cross-chain mechanism —
the interface can be frozen without waiting on cross-chain.

## Contents

- `nft-single-xchain.pact` — the cross-chain NFT (the consignment `nft-single` plus `present`
  residency and `depart`/`claim`). Static gate: 0 violations.
- `nft-asset.pact` / `nft-marketplace.pact` / `simple-market.pact` — the same standard surface as the
  consignment spike (reused verbatim).
- The runnable devnet campaign lives in the gallery devnet harness
  (`gallery/devnet/src/nft-xchain-spike.ts`) because it depends on that `@kadena/client` infra; it
  reads the modules from this directory.

## Open items for the production build

- **Consignment across a move** — this spike departs an *unconsigned* token (delist before moving, as
  in the current Gallery). Whether a listing should survive a move (it should not — listings are
  chain-local) is confirmed, but the production module should reject a move-while-consigned explicitly
  (it does: `depart` enforces not-listed).
- **Origin-id uniqueness** — here `origin-id` is the module's `SELF` key; production wants a globally
  unique origin id (e.g. the origin module's namespaced name) so an indexer can follow one painting
  across chains and distinguish it from another module's token.
- **Signatures** remain provisional until the production build + testnet validation (a published
  interface freezes forever).
