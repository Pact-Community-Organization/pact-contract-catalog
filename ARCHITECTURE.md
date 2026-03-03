# Repository Architecture — Pact Smart Contracts Catalog

## Purpose

Provide a layered, dependency-aware catalog of production Pact smart contracts on KDA-CE. Each contract entry ships with its source code (as deployed on-chain), human-readable documentation, machine-readable metadata, and an audit record.

---

## Top-level layout

```
README.md              — repository overview, mission & vision
ARCHITECTURE.md        — this file
CONTRIBUTING.md        — how to contribute contract entries and audits
CODE_OF_CONDUCT.md     — community guidelines
LICENSE                — project license
contracts/             — contract entries, grouped by dependency layer
  kip/                 — KIP standard interfaces (no executable logic)
  core/                — Pre-deployed KDA-CE chain infrastructure
  marmalade/           — Marmalade v2 NFT framework (pre-deployed)
  ecosystem/           — Top 10 production third-party modules (from blockchain census)
  community/           — PCO community templates and reference contracts
scripts/               — validation, index generation
docs/                  — onboarding, index output (index.md, index.json)
```

---

## Dependency Layers

The `contracts/` tree is organised by **dependency order** — lower layers are depended on by higher layers, never the reverse.

```
Layer 0 — KIP Standards (kip/)
  Pure interfaces: no executable code, no state.
  Every module that claims standard compliance must implement these.

    kip/fungible-v2            ◄─── implemented by coin, custom tokens
    kip/fungible-xchain-v1     ◄─── implemented by coin (cross-chain)
    kip/gas-payer-v1           ◄─── implemented by gas station modules
    kip/token-policy-v2        ◄─── implemented by all Marmalade policies
    kip/token-manifest              module (not interface); used by ledger

Layer 1 — Core Infrastructure (core/)
  Pre-deployed production modules on all chains (0–19).
  Cannot be redeployed; integrate by calling them.

    core/coin                  implements kip/fungible-v2 + kip/fungible-xchain-v1
    core/ns                    namespace registry; called by define-namespace
    core/fungible-util         implements kip.account-protocols-v1; used by coin

Layer 2 — NFT Framework (marmalade/)
  Marmalade v2 pre-deployed NFT stack.
  Depends on kip/ interfaces and core/coin for payments.

    marmalade/ledger            implements ledger-v2 + kip.poly-fungible-v3
                                    uses  kip/token-manifest
                                    delegates to  marmalade/policy-manager
    marmalade/policy-manager    calls kip/token-policy-v2 on each policy
                                    uses  core/coin (royalty payments)

Layer 3 — Ecosystem (ecosystem/)
  Production modules from major KDA-CE ecosystem projects.
  Selected by cross-chain deployment census (all deployed on 20/20 chains).
  Methodology: live (list-modules) query on all 20 mainnet01 chains Jan 2025.

    ecosystem/kaddex/kaddex-kdx          implements fungible-v2 + fungible-xchain-v1
    ecosystem/runonflux/flux             implements fungible-v2
    ecosystem/lago/kwBTC                 (governance shell — namespace reservation only)
    ecosystem/lago/kwUSDC                (governance shell — namespace reservation only)
    ecosystem/lago/USD2                  (governance shell — namespace reservation only)
    ecosystem/kadena/spirekey            implements gas-payer-v1
    ecosystem/marmalade-sale/conventional-auction  implements marmalade-v2.sale-v2
    ecosystem/marmalade-sale/dutch-auction         implements marmalade-v2.sale-v2
    ecosystem/mok/mok-token              implements fungible-v2 + fungible-xchain-v1
    ecosystem/arkade/arkade-token        implements fungible-v2 + fungible-xchain-v1

Layer 4 — Community (community/)
  PCO-authored templates. Implements interfaces from Layer 0.
  Depends on Layer 1 for runtime calls.

    community/hello-world
    community/token-fungible    implements kip/fungible-v2
```

### Full dependency graph

```
kip/fungible-v2 ◄──────────────── core/coin ◄──── core/ns
kip/fungible-xchain-v1 ◄─────────┘          ◄──── core/fungible-util
kip/gas-payer-v1                                      │
kip/token-manifest ◄──────────── marmalade/ledger ◄───┤
kip/token-policy-v2 ◄────────── marmalade/policy-mgr  │
                                      └── core/coin ───┘
community/* ──────────────────── kip/* + core/*

ecosystem/kaddex.kdx──────────── kip/fungible-v2
                                ► kip/fungible-xchain-v1
                                ► kaddex.supply-control-v1
                                ► kaddex.special-accounts-v1
ecosystem/runonflux.flux──────── kip/fungible-v2
ecosystem/mok.token───────────── kip/fungible-v2 + kip/fungible-xchain-v1
ecosystem/arkade.token────────── kip/fungible-v2 + kip/fungible-xchain-v1
ecosystem/kadena.spirekey──────── kip/gas-payer-v1
ecosystem/lago.*──────────────── (governance shells — no fungible logic deployed on-chain)
ecosystem/marmalade-sale.*───────► marmalade/policy-manager
                                ► marmalade-v2.sale-v2
```

---

## Contract entry structure

Every contract directory (e.g. `core/coin/`) contains:

```
<slug>/
  metadata.yaml     — machine-readable metadata
  README.md         — API reference, dependency graph, usage examples
  AUDIT.md          — audit status, findings, references
  <module>.pact     — deployed Pact source (verbatim from chain / upstream)
  [examples/]       — optional REPL or deployment examples
  [coverage/]       — optional test coverage artefacts
```

---

## Metadata schema

```yaml
name: 'My Contract'
slug: 'my-contract'
version: '1.0.0'
repository: 'https://github.com/Pact-Community-Organization/<repo>'
license: 'Apache-2.0'
authors:
  - name: 'Author Name'
    email: 'author@example.org'
audit_status: 'audited'   # audited | in-review | not-audited
tags: ['token', 'finance']
keywords: ['pact', 'smart-contract']
```

---

## Automation

- `scripts/generate_index.sh` — builds `docs/index.md` and `docs/index.json` from all `contracts/**/metadata.yaml` (recursive; works with layered structure).
- `scripts/validate_contract.sh <contract-directory>` — validates metadata correctness and runs basic static checks on `.pact` files.
- CI: runs validate_contract.sh on every PR that modifies a contract directory.

---

## Source provenance

| Layer | Provenance | Source repository |
|-------|------------|-------------------|
| `kip/` | Upstream Kadena LLC | [kadena-io/marmalade/pact/kip/](https://github.com/kadena-io/marmalade/tree/main/pact/kip) + [chainweb-node](https://github.com/kda-community/chainweb-node) |
| `core/` | Upstream Kadena LLC | [kadena-io/marmalade/pact/root/](https://github.com/kadena-io/marmalade/tree/main/pact/root) + chainweb-node |
| `marmalade/` | Upstream Kadena LLC | [kadena-io/marmalade/pact/](https://github.com/kadena-io/marmalade/tree/main/pact) |
| `ecosystem/` | Third-party projects | Various (see each module's `metadata.yaml`) — verified from mainnet01 blockchain census Jan 2025 |
| `community/` | PCO contributors | [Pact-Community-Organization/pact-contract-catalog](https://github.com/Pact-Community-Organization/pact-contract-catalog) |

> `kip/`, `core/`, and `marmalade/` entries are **reference entries** — authored by Kadena LLC, pre-deployed on all chains, and not re-deployable by community contributors. They are catalogued here to document the interfaces and contracts that community modules build upon.

---

## Governance notes

- Additions to `kip/`, `core/`, or `marmalade/` require a maintainer PR for upstream sync.
- Additions to `ecosystem/` require evidence of deployment on mainnet01 (module hash, describe-module output, or block explorer link) plus a PR matching the census methodology in `contracts/ecosystem/README.md`.
- Additions to `community/` require a PR linking a GitHub issue, passing CI, and approval per `CONTRIBUTING.md`.
- Audit promotions (`not-audited` → `in-review` → `audited`) require evidence in `AUDIT.md`.