# library/ — PCO Deployable Contract Templates

This tree contains **Pact Community Organization (PCO)** contract templates: deployable starting points you copy, adapt, and build on. Unlike everything under `contracts/registry/`, these contracts are **authored, maintained, and quality-gated by PCO** — this is the product the catalog exists to deliver.

---

## Contents

| Contract | Directory | Description |
|---------|-----------|-------------|
| Hello World | [hello-world/](hello-world/README.md) | Introductory contract — entry point for new Pact developers |
| Token (fungible-v2) | [token-fungible/](token-fungible/README.md) | Reference fungible token implementation (PCO template) |

Planned templates: gas-station, NFT collection + policy, multisig treasury, vesting escrow, DAO voting, oracle consumer.

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

```
library/<your-nft-policy>/
 └── implements  registry/kip/token-policy-v2
 └── used by     registry/marmalade/policy-manager  (via policy-manager routing)
```
