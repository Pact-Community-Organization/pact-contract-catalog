# Fixed-Supply Token (frozen, one-shot mint)

A `fungible-v2` token whose **entire supply is minted exactly once** at
initialization and can only ever **decrease** afterwards (holders may burn
their own tokens). The module is **non-upgradeable by construction**: its
governance capability is a hard `(enforce false)`, so there is no owner, no
admin surface, and no path to mint more, freeze accounts, or rewrite rules.

Use this when immutability is the product — community tokens, fair-launch
distributions, any token whose holders should never have to trust an
operator. If you need governed mint, cross-chain transfers, or upgradeability,
use [`token-fungible`](../token-fungible/) instead.

## Security model (what makes this safe to build on)

- **One-shot mint by construction.** `init-mint` starts by `insert`-ing the
  singleton supply row; a second call fails on the existing key before any
  balance is touched. The distribution must sum to exactly `TOTAL-SUPPLY`.
  After the one call, the minter keyset is powerless.
- **Frozen governance.** `GOV` always fails, so module upgrade and any
  admin-gated path are unreachable forever. (Corollary: tables are created in
  the deploy transaction itself — see the checklist.)
- **Coin-pattern ledger discipline.** Managed `TRANSFER` capability with a
  budget manager; debit authorization = the sender's own account guard;
  reserved-name protocol on every credit path (a `k:` account only ever binds
  to the guard whose principal it is — no account squatting); principal
  accounts cannot rotate their guard away.
- **Self-burn only.** `burn` is gated on the burning account's own guard and
  updates the supply ledger, so `circulating-supply` is always exact.
- **Single-chain by design.** `transfer-crosschain` is disabled: a frozen
  module cannot coordinate deployments across chains, so pretending to
  support it would be dishonest.

## Deployment checklist

1. Rename the module and wrap it in your namespace.
2. Deploy with the parameters in **transaction data** (they bake into
   constants at load): `symbol`, `precision` (0..12), `total-supply`
   (positive, at `precision` units), `token-minter` (keyset for the one
   mint). Bad values abort the deploy.
3. **Keep the `(create-table ...)` calls in the deploy transaction.** Frozen
   governance means module admin exists only during that transaction; tables
   can never be created later.
4. Call `init-mint` with the full distribution (every recipient gets
   `account`, `guard`, `amount`). **Distribute to principal (`k:`/`w:`)
   accounts, or run `init-mint` in the deploy transaction itself**: anyone
   can pre-create a vanity account name under their own guard, which would
   abort a mint that targets that name (griefing only — no value moves, and
   principal names are immune).
5. Run the co-located REPL suite, then validate on devnet before any
   production deployment.

## Usage

```pact
;; transfer under a scoped, managed capability
(env-sigs [{ "key": "sender-key"
           , "caps": [(fixed-supply-token.TRANSFER "sender" "receiver" 10.0)] }])
(fixed-supply-token.transfer "sender" "receiver" 10.0)

;; burn your own tokens (signature satisfies your account guard)
(fixed-supply-token.burn "sender" 5.0)

;; supply views
(fixed-supply-token.initial-supply)      ;; the fixed supply
(fixed-supply-token.burned-total)        ;; cumulative burns
(fixed-supply-token.circulating-supply)  ;; initial - burned
```

## Testing

```bash
cd examples
pact fixed-supply-token-test.repl
```

The suite is self-contained (interfaces load from this repository's registry
tree) and covers the one-shot mint, exact-distribution enforcement, managed
transfer scoping, the reserved-name/principal protocol, rotation safety,
burn supply accounting, and the disabled cross-chain path.

## Known limits

- **Deploy-time validation is load-time validation.** The precision and
  supply bounds are enforced inside `defconst`s when the module loads.
  A REPL limitation (`expect-failure` around `load` corrupts repl state)
  prevents asserting bad deploys in-suite; verify manually by loading with,
  e.g., `"precision": 13` and observing the abort.
- **Send deploy parameters as exact JSON numbers.** `read-integer` coerces
  decimals by rounding (`"precision": 12.4` silently loads as `12`); a typo
  in the fractional part can succeed at the wrong precision instead of
  aborting. Double-check the deploy payload — the result is irreversible.
- **Non-principal account names are first-come.** Anyone may create a vanity
  name under their own guard; only that guard can ever use it (standard
  fungible-v2 behavior — no value at risk). Principal `k:`/`w:` names are
  squat-proof: they only ever bind to the guard whose principal they are.
- **Irreversible by design.** There is no recovery path for a wrong symbol,
  precision, or distribution — re-deploy under a new name and abandon the
  mistake. Treat a mainnet deploy like signing a legal document.
- **Single chain.** No cross-chain transfers, ever. Deploying the same code
  on two chains produces two unrelated tokens.
- One class of node-side bug (table reads inside `enforce` conditions) is
  invisible in the REPL — validate on devnet before production.

## License

Apache-2.0 — see the repository [LICENSE](../../../LICENSE).
