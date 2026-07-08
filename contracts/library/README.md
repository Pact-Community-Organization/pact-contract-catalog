# library/ — PCO Deployable Contract Templates

This tree contains **Pact Community Organization (PCO)** contract templates: deployable starting points you copy, adapt, and build on. Unlike everything under `contracts/registry/`, these contracts are **authored, maintained, and quality-gated by PCO** — this is the product the catalog exists to deliver.

---

## Contents

| Contract | Directory | Description |
|---------|-----------|-------------|
| Hello World | [hello-world/](hello-world/README.md) | Introductory contract — entry point for new Pact developers |
| Token (fungible-v2 + fungible-xchain-v1) | [token-fungible/](token-fungible/README.md) | Hardened fungible token: coin-pattern guard enforcement, governed mint, cross-chain steps |
| Gas Station | [gas-station/](gas-station/README.md) | Drain-defended gas sponsorship with a per-user on-chain allowlist |
| Multisig Treasury | [multisig-treasury/](multisig-treasury/README.md) | M-of-N treasury: capability-guarded vault, propose/approve/execute, stale-approval revocation |
| Token Vesting | [vesting/](vesting/README.md) | Cliff + linear vesting, escrowed upfront; revoke returns only the unvested part |
| DAO Voting | [dao-voting/](dao-voting/README.md) | Membership voting with quorum + threshold and per-proposal passage snapshots |
| Oracle Feed | [oracle-feed/](oracle-feed/README.md) | Median data/price feed with fail-closed staleness windows and publisher rotation |
| Property Lease | [property-lease/](property-lease/README.md) | Rental rails: escrowed deposit, rent buckets with revenue split, vault conservation |
| Royalty Sale | [royalty-sale/](royalty-sale/README.md) | Conservation-checked NFT marketplace; reference implementation of the [NFT interface standard](../standards/SPEC.md) |

**Building NFTs?** The catalog's NFT architecture is the [NFT Framework](../nft/README.md) (`contracts/nft/`) — a separate product tree, not a library template. `royalty-sale` remains here as the standalone single-module variant and the interface standard's reference implementation; the framework generalizes its settlement discipline behind a shared-ledger policy architecture.

---

## The library quality gate

Every entry in this tree must satisfy (enforced by CI via `scripts/validate_contract.sh`):

1. **Schema-A metadata** — `name`, `slug`, `version`, `repository`, `license`, `authors`, `audit_status`, `tags` in a co-located `metadata.yaml`.
2. **Co-located `.repl` test suite** — under `examples/`, runnable against the [kadena_repl_sandbox](https://github.com/CryptoPascal31/kadena_repl_sandbox).
3. **`AUDIT.md` at `self-reviewed` or better** — per the ladder in [docs/CONTRACT_POLICIES.md](../../docs/CONTRACT_POLICIES.md) §3.1.
4. **No open CRITICAL findings** — entries with a CRITICAL finding live in `registry/`, never here.

---

## Contributing a template

1. Create a directory under `contracts/library/<your-slug>/`
2. Add: `README.md`, `metadata.yaml`, `AUDIT.md`, your `.pact` source, and `examples/*.repl` tests
3. Run `scripts/validate_contract.sh contracts/library/<your-slug>/`
4. Submit a PR per the [CONTRIBUTING.md](../../CONTRIBUTING.md) guidelines

**Minimum metadata fields:**

```yaml
name: 'My Contract'
slug: 'my-contract'
version: '1.0.0'
repository: 'https://github.com/...'
license: 'Apache-2.0'
authors:
  - name: 'Your Name'
    email: 'you@example.com'
audit_status: 'self-reviewed'   # library minimum — be honest
tags: ['your', 'tags']
```

---

## Dependencies from this tree

Library templates **use** (not re-implement) the registry layers:

```
library/<your-token>/
 └── implements  registry/kip/fungible-v2
 └── uses        registry/core/coin          (for cross-checks, gas)
 └── uses        registry/core/fungible-util (for validation helpers)
```
