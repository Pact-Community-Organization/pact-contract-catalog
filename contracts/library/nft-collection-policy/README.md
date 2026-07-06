# NFT Collection Policy (marmalade-v2)

PCO library template: a **marmalade-v2 concrete policy** for NFT collections — creator-gated token creation and minting, a collection size cap, strict one-of-one NFT shape, and opt-in burning. This is the artifact an NFT project on Kadena actually writes: a module implementing `kip.token-policy-v2`, attached to tokens at `create-token` time and driven by the marmalade ledger through the policy-manager. It custodies nothing — the marmalade ledger holds the tokens; this policy only decides what is allowed.

## How it works

1. **`create-collection id name max-size burnable creator-guard`** — self-serve; the caller must satisfy `creator-guard` (signs scoped to `CREATOR-AUTH`). `max-size 0` = unbounded.
2. **`marmalade-v2.ledger.create-token …`** with this policy in the token's policies list and `"collection_id"` in tx data — the policy's `enforce-init` admits the token: only the collection creator may add tokens, the collection must have room, and precision must be 0.
3. **`marmalade-v2.ledger.mint token-id account guard 1.0`** — `enforce-mint`: creator-authorized, exactly once per token **ever**, amount exactly 1.0. The recipient may be anyone.
4. **Transfers and sales** are permitted by this policy — the ledger enforces ownership (managed `TRANSFER`/`OFFER` capabilities). Stack marmalade's royalty policy for economics.
5. **Burning** is a per-collection opt-in; the ledger additionally enforces the owner's guard. A burned NFT can never be re-minted.

## Security model

- **Hooks are unreachable outside the real flow.** Every one of the seven `kip.token-policy-v2` hooks is gated by `require-capability` on the policy-manager's corresponding `*-CALL` capability (with this policy's rendered name as argument). Direct calls — from users or hostile modules — always fail; the only path to policy state runs through the genuine ledger → policy-manager flow.
- **Collections belong to their creators.** Adding tokens and minting both enforce the guard enrolled at collection creation, inside the policy-manager-granted scope. Governance (`nft-collection-gov` keyset) can upgrade the module and nothing else.
- **One-of-one shape is a hard invariant.** Precision 0 at init; mint exactly once per token with amount exactly 1.0; the minted flag is one-way, so burn → re-mint is impossible. Supply for any token is 0 or 1, forever.
- **Size caps count created tokens — burned tokens still count.** `max-size` bounds tokens ever admitted to the collection (minted or not, burned or not): a max-N collection can only ever contain N distinct token ids. Accounting updates are transactional with the ledger's `create-token`, so an abort anywhere rolls back everything.
- **Scope your signatures.** The creator's guard is enforced inside the policy-manager's `INIT-CALL`/`MINT-CALL` scope, so creators can (and should) scope their create-token and mint signatures to those ledger capabilities instead of signing unscoped — the suite demonstrates the exact shape.

## Deployment checklist

1. Wrap the module in your namespace; replace the `"nft-collection-gov"` keyset with your deployed, namespace-qualified governance keyset (**multi-sig recommended**).
2. Deploy and `create-table` (`collections`, `tokens`). No init step — collections are self-serve.
3. Validate on **devnet against the real marmalade-v2 deployment** before mainnet — **mandatory**, not optional (see Known limits: the buy step of sales is not exercised in the REPL suite).

## Usage

```pact
;; create a collection (sign scoped to CREATOR-AUTH)
(free.nft-collection-policy.create-collection "my-art" "My Art" 100 false
  (read-keyset "creator"))

;; create a token in it (tx data: {"collection_id": "my-art"}; creator signs)
(marmalade-v2.ledger.create-token
  (marmalade-v2.ledger.create-token-id
    { 'uri: "ipfs://…", 'precision: 0, 'policies: [free.nft-collection-policy] }
    (read-keyset "creator"))
  0 "ipfs://…" [free.nft-collection-policy] (read-keyset "creator"))

;; mint it (creator signs scoped to the ledger's MINT-CALL + managed MINT)
(marmalade-v2.ledger.mint token-id "collector" (read-keyset "collector") 1.0)
```

## Testing

`examples/nft-collection-policy-test.repl` loads the **real marmalade-v2 stack** from this repo's `registry/` tree (verbatim chain snapshots — ledger, policy-manager, kip interfaces, `util.fungible-util`) plus two clearly-labeled interface stubs (`examples/support/`) for kip interfaces not yet snapshotted:

```bash
cd contracts/library/nft-collection-policy/examples && pact nft-collection-policy-test.repl
```

38 assertions: direct-call attacks on all seven hooks, creator gating on create-token and mint, precision/amount/once-only NFT shape, collection size cap, non-owner transfer denial, per-collection burn opt-in with the no-re-mint invariant, and the sale defpact's offer + withdraw steps exercised positively through the genuine ledger. CI runs this suite as a blocking check.

## Known limits

- **The sale BUY step is not exercised in the REPL suite** (it needs the quote/escrow machinery). `enforce-buy`'s capability arguments are verified against the policy-manager source, but **devnet validation of a full sale (offer → buy) against the real marmalade-v2 deployment is mandatory** before relying on sales.
- **`collection_id` comes from tx data at create-token time** — one collection per transaction when creating tokens.
- **Minting is creator-only by design.** For public/paid mint drops, front this policy with a sale contract or extend it — that is deliberately out of scope for the template.
- **No royalty logic.** Stack marmalade's concrete royalty policy alongside this one in the token's policies list.
- The two files under `examples/support/` are **REPL test support only** (interface signatures for `kip.account-protocols-v1` and `kip.updatable-uri-policy-v1`, which are pre-deployed on-chain but not yet snapshotted in the registry). Never deploy them.
- Governance holds upgrade power. Pin the deployed module hash you audited; use a multi-sig governance keyset.

## License

Apache-2.0
