# Audit Record — coin

| Field | Value |
|-------|-------|
| Module | `coin` |
| Version | 6.0.0 |
| Audit status | `audited` |
| Audited by | Kadena LLC (internal) |
| Audit date | — (pre-deployment, upstream KDA-CE) |
| Scope | Full module |

## Notes

`coin` is the canonical KDA token contract authored by Kadena LLC and maintained by the KDA Community Edition project. It was audited as part of the upstream Kadena blockchain codebase prior to genesis. The Pact Community Organization lists it here as a reference entry — this contract is **not authored by PCO** and **cannot be redeployed by community contributors**.

Security properties verified upstream:
- `TRANSFER` is `@managed` with the `TRANSFER-mgr` enforcing single-use, exact-amount semantics.
- `GAS` is granted exclusively by the runtime preamble — no user code can obtain it openly.
- `DEBIT` and `CREDIT` are `require-capability`-guarded internal helpers; never directly callable.
- `GOVERNANCE` is keyset-protected; upgrades require chain-controlled governance.

## References

- [KDA-CE chainweb-node source](https://github.com/kda-community/chainweb-node)
- [Pact formal verification](https://pact-language.readthedocs.io/en/latest/pact-reference.html#formal-verification)
