# community/ — PCO Community Contract Templates

This layer contains **Pact Community Organization (PCO)** contract templates and reference implementations. Unlike the `core/`, `kip/`, and `marmalade/` layers, these contracts are **authored by PCO contributors** and are intended to be adapted, deployed, and built upon by the community.

---

## Contents

| Contract | Directory | Description |
|---------|-----------|-------------|
| Hello World | [hello-world/](hello-world/README.md) | Introductory contract — entry point for new Pact developers |
| Token (fungible-v2) | [token-fungible/](token-fungible/README.md) | Reference fungible token implementation (PCO template) |

---

## Contributing a contract

To add a contract to this layer:

1. Create a directory under `community/<your-slug>/`
2. Add: `README.md`, `metadata.yaml`, `AUDIT.md`, and your `.pact` source
3. Run `pact-contract-catalog/scripts/validate_contract.sh community/<your-slug>/`
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
audit_status: 'not-audited'   # be honest
tags: ['your', 'tags']
```

---

## Dependencies from this layer

Community contracts typically **use** (not re-implement) the lower layers:

```
community/<your-token>/
 └── implements  kip/fungible-v2
 └── uses        core/coin          (for cross-checks, gas)
 └── uses        core/fungible-util (for validation helpers)
```

```
community/<your-nft-policy>/
 └── implements  kip/token-policy-v2
 └── used by     marmalade/policy-manager  (via policy-manager routing)
```
