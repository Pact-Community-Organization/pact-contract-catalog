# Token (fungible-v2 + fungible-xchain-v1)

PCO library template: a fungible token implementing `fungible-v2` and `fungible-xchain-v1` with coin-contract-grade capability security. Copy it, adapt it, deploy it — this is a starting point for real projects, hardened to the same authorization model as the chain's native `coin` contract.

## Security model (what makes this safe to build on)

- **Sender-guard enforcement in `DEBIT`** — every outgoing transfer (including cross-chain step 0) enforces the sender's stored account guard. Scoping the managed `TRANSFER` capability with your own signature is *not* enough to move someone else's funds. This is the exact pattern used by `coin` (see `registry/core/coin`).
- **Managed `TRANSFER` / `TRANSFER_XCHAIN` caps** — amount-metered by manager functions; auto-emit events on acquisition (Pact 5 managed caps emit — no explicit `emit-event` needed or wanted on the direct path).
- **Reserved-account protocol** — `k:`-prefixed accounts must be the principal of their guard (`enforce-reserved`), preventing account squatting; enforced at `create-account` *and* on implicit creation inside `credit`.
- **Rotation safety** — `rotate` is authorized by the *old* guard under a one-shot managed `ROTATE` cap, and principal accounts cannot rotate away from their proper guard.
- **Governed supply** — `mint` is `GOV`-gated and emits a `MINT` event. There is deliberately no unauthenticated supply path.
- **Validation everywhere** — account length/charset bounds, positive amounts, 12-decimal precision (`enforce-unit`), valid Chainweb chain-id check on cross-chain targets.

## Deployment checklist

1. Rename the module and wrap it in your namespace (`(namespace "free")` or your own).
2. Replace the `"token-gov"` keyset reference with your deployed, namespace-qualified governance keyset — **multi-sig strongly recommended**. (The unqualified name in the template works only in the REPL; chainweb requires namespaced keysets.)
3. Adjust `VALID_CHAIN_IDS` if your target network does not have exactly chains 0–19.
4. Deploy, then `(create-table token-table)` in the same transaction.
5. Run the co-located REPL suite against your adapted module.
6. **Validate on devnet before mainnet** — cross-chain step 1 (`resume`) requires SPV and cannot be proven in the bare REPL. A passing REPL run is *not* evidence for the cross-chain path.
7. **Upgrading a deployed copy while cross-chain transfers are in flight?** The new module version must `(bless "<pre-upgrade-hash>")` — otherwise every pending step-1 resume fails with `Yield provenance does not match` until a later upgrade blesses the old hash. Get the hash via `(at 'hash (describe-module "<your.module>"))` *before* upgrading.

## Usage

```pact
;; governance mints initial supply
(token.mint "k:<key>" (read-keyset "operator") 1000000.0)

;; transfers: sender signs, scoping the managed TRANSFER cap
;; sigs: [{ key: <sender-key>, caps: [(token.TRANSFER "k:<sender>" "k:<receiver>" 25.0)] }]
(token.transfer "k:<sender>" "k:<receiver>" 25.0)

;; cross-chain: sender signs, scoping TRANSFER_XCHAIN; step 1 completes on the target chain via SPV
(token.transfer-crosschain "k:<sender>" "k:<receiver>" (read-keyset "receiver") "1" 10.0)
```

## Testing

`examples/token-test.repl` is **self-contained** — it loads the `fungible-v2` / `fungible-xchain-v1` interfaces from this repository's `registry/` tree; no external sandbox needed:

```bash
cd contracts/library/token-fungible/examples && pact token-test.repl
```

The suite covers: account creation and duplicate rejection, governed mint (and mint-without-governance rejection), transfers and `transfer-create`, **the drain-attack regression** (attacker scoping `TRANSFER`/`TRANSFER_XCHAIN` for someone else's account must fail on the sender guard), input validation (funds, self-transfer, precision, account length), `k:` squatting prevention, rotation authorization and principal-rotation protection, and cross-chain step-0 guards. CI runs this suite as a blocking check.

## Known limits

- Cross-chain step 1 is devnet/mainnet-only (SPV). Test it there before shipping.
- Cross-chain step 0 fails fast on a `k:` receiver whose guard doesn't match (prevents locking funds in an uncompletable defpact). It *cannot* detect the one remaining doomed case: a receiver account that already exists on the target chain with a different guard — step 1 will fail on the guard mismatch. Verify the receiver's target-chain guard before large transfers.
- No burn function — add one gated by your governance if your tokenomics need it.
- The governance keyset has absolute power (unlimited mint, module upgrade). That is inherent to a keyset-governed template — use multi-sig and consider a supply-cap constant for your tokenomics.
- `@model` annotations are documentation: Pact 5.4ce has no `verify` native.

## License

Apache-2.0
