# registry/community/ — Census-Observed Community Modules

This layer contains **community-authored free-namespace modules observed on mainnet01** via the call-frequency census (block-payload sampling, stride=1000, 90-day window, all 20 chains — see [../ecosystem/README.md](../ecosystem/README.md) for the methodology).

These are **verbatim snapshots** of deployed code, catalogued for reference and due diligence. They are *not* PCO-authored, *not* quality-gated, and **not starting templates** — for deployable templates, see [`contracts/library/`](../../library/README.md).

---

## Contents

| Module | Directory | Description | Audit status |
|--------|-----------|-------------|--------------|
| `free.cyberfly_node` | [cyberfly/cyberfly-node/](cyberfly/cyberfly-node/README.md) | DePIN node registry (staking, rewards) | community-reviewed |
| `free.cyberfly_token` | [cyberfly/cyberfly-token/](cyberfly/cyberfly-token/README.md) | CFLY token (fungible-v2 + xchain) | community-reviewed |
| `free.p2p-escrow` | [p2p-escrow/](p2p-escrow/README.md) | P2P escrow with reputation | **unaudited — ⚠️ CRITICAL open finding** |

> ⚠️ `p2p-escrow` carries an open CRITICAL finding — `(defcap GOVERNANCE () true)`
> means anyone can upgrade the module. It is catalogued here as an observed on-chain
> artifact and a cautionary reference. **Do not deploy it.** See its
> [AUDIT.md](p2p-escrow/AUDIT.md).

---

## Adding an entry to this layer

1. Evidence of mainnet01 deployment is required: module hash, `describe-module` output, or a block-explorer link.
2. Create `contracts/registry/community/<project>/<module>/` with `metadata.yaml` (schema B: namespace/module/layer/census fields), `README.md`, `AUDIT.md`, and the verbatim `.pact` source.
3. Run `scripts/validate_contract.sh` on the directory and submit a PR per [CONTRIBUTING.md](../../../CONTRIBUTING.md).
