# Audit Record — marmalade-v2.ledger

| Field | Value |
|-------|-------|
| Module | `marmalade-v2.ledger` |
| Version | 2.0.0 |
| Audit status | `audited` |
| Audited by | Kadena LLC (internal) |

## Notes

`marmalade-v2.ledger` is authored by Kadena LLC. Pre-deployed on all KDA-CE chains. All state-changing operations emit events (`@event` capabilities: MINT, BURN, RECONCILE, UPDATE_SUPPLY) enabling full off-chain auditability. The TRANSFER capability is `@managed`. Listed here as a reference entry; not authored or deployable by PCO.

## References

- [Marmalade documentation](https://docs.kadena.io/marmalade)
- [KDA-CE chainweb-node source](https://github.com/kda-community/chainweb-node)
