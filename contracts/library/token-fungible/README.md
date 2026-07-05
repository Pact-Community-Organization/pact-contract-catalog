# Token (fungible-v2 + fungible-xchain-v1)

Minimal fungible token implementing `fungible-v2` and `fungible-xchain-v1` with capability-based security, suitable as a reference for Pact ecosystems.

## Highlights
- Interface compliance for `fungible-v2` and `fungible-xchain-v1`.
- Capability-based security: `DEBIT`, `CREDIT`, `TRANSFER`, `ROTATE`, and xchain caps.
- Clear ledger model: `token-table` storing `balance` and `guard`.
- Admin helpers: `fund` and `burn` gated by `GOV` for testing/provisioning.

## Usage
Define a `token-gov` keyset, then load the module and provision accounts:

```pact
(define-keyset 'token-gov (read-keyset "token-gov"))
(load "./token.pact")
(with-capability (GOV) (fund "alice" 100.0))
```

Transfers require the sender’s guard to be satisfied:

```pact
(transfer "alice" "bob" 25.0)
```

## Testing
See `examples/token-test.repl` for a runnable REPL script that:
- Initializes standard interfaces and guards.
- Sets up keysets for `alice`, `bob`, and governance.
- Runs positive tests (transfers, transfer-create, details, precision).
- Runs negative tests (insufficient funds, same account, missing signer).
- Validates capability enforcement and guard rotation.

## Notes
- Cross-chain transfer (`transfer-crosschain`) is provided as a skeleton (yield/credit), SPV validation left for network integration.
- Precision is enforced at 12 decimal places by default.

## License
Apache-2.0
