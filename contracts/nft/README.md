# The `nft` framework — a shared-ledger NFT standard, hardened

A complete NFT framework for Kadena (Pact 5.4ce / KDA-CE), authored by the PCO as a neutral
community standard in the `nft` namespace. It keeps the **one architectural idea worth keeping**
from the deployed Marmalade V2 stack — token identity anchored in a shared ledger — and re-authors
the settlement/policy layer around five principles the analysis of that stack produced. This is an
original implementation, not a fork; the Marmalade sources under `contracts/registry/marmalade/`
are read-only reference.

## Identity: why a shared ledger

A token id is `n:{hash([token-details, chain-id, creation-guard])}` — derived from the creator's
guard. `create-token` re-derives the id, enforces the creation guard, and inserts exactly one row:

- **Forgery is impossible** — you cannot create a token whose id claims someone else's guard;
- **Double-mint is impossible** — one id, one row, forever;
- **The id is order-independent** — the ledger canonicalizes the policy list (name-sorted,
  duplicates rejected), so the same policy *set* always derives the same id.

Self-sovereign per-NFT modules cannot provide this anchor (anyone can deploy a lookalike module);
see the consignment spike under `contracts/standards/nft-consignment-spike/` for that
proving-ground record.

## Settlement: the five principles

1. **Fail closed.** Every required input (royalty spec, operation guards, collection id, quote) is
   typed and required — absence aborts; nothing defaults to permissive.
2. **One settlement, conservation-asserted.** Policies DECLARE payouts and move no money. The
   policy-manager pays every declared cut + the marketplace fee + the seller remainder from one
   capability-guarded per-sale escrow and asserts `escrow-in = Σ payouts` at the fungible's full
   precision. Same-payee legs merge; zero legs drop.
3. **Economics on-chain, never in the buy transaction.** The quote (price, fungible, seller payout
   account, fee) binds in STATE at offer, signed by the seller. The buyer supplies only their own
   paying account; a malicious economic payload in the buy transaction is ignored.
4. **Sale-only is explicit and robust.** Enforced at settlement by the royalty policy's opt-in
   flag — a sale through the pact always works and always pays the royalty; the property cannot be
   composed away and is never a blanket transfer ban.
5. **Minimal trusted surface.** Every policy hook is unreachable outside the ledger's lifecycle
   path: the manager `require-capability`s the registered ledger's matching `-CALL` capability
   through its stored modref before dispatching. Fabricated token-info dies at the gate.

## Layout

| Path | Contents |
|---|---|
| `interfaces/` | `token-policy` (the hook surface + payout schema), `poly-fungible` (the multi-token accounting standard), `ledger-iface` (the `-CALL` handshake), `sale` (price-discovery sale contracts), `updatable-uri-policy`, `account-protocols` |
| `core/` | `ledger` (identity + balances + the offer/withdraw/buy sale defpact), `policy-manager` (dispatch + the single conservation-asserted settlement), `util` (account protocols) |
| `policies/` | `royalty-policy`, `guard-policy`, `non-fungible-policy` (strict 1/1, minted once ever), `collection-policy`, `non-updatable-uri-policy` (unconditional uri veto) |
| `test/` | one adversarial suite per policy + `identity`, `settlement`, and `composition` (a royalty+guard+1/1 stack settled and reconciled to 12 dp) |

## Relationship to the rest of the catalog

- **`contracts/standards/` (NFT interface standard v1)** — the compatibility standard for
  *standalone* marketplaces, each custodying its own tokens (the `fungible-v2` model). This
  framework is the **shared-ledger track** that SPEC.md explicitly scopes out of v1: tokens live in
  one ledger, marketplaces are sale contracts, portability is native. The two coexist; conforming
  standalone marketplaces and this framework emit compatible economics by construction (state-bound
  quotes, conservation-asserted settlement, enforceable royalties).
- **`contracts/library/royalty-sale/`** — the standalone hardened marketplace template and v1
  reference implementation. This framework generalizes its settlement discipline (dust guard,
  merged legs, conservation assert) behind a policy architecture.
- **`contracts/registry/marmalade/`** — the deployed stack whose analysis produced the principles
  above; reference only.

## Gates

Every change: all suites in `test/` green (`pact <name>.repl`) and the repository's static gate at
0 VIOLATIONs. Cross-chain classes are devnet evidence (the ledger currently rejects cross-chain
transfers outright rather than shipping them unproven).
