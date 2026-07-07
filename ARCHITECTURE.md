# Repository Architecture — Pact Smart Contracts Catalog

## Purpose

Provide a layered, dependency-aware catalog of production Pact smart contracts on KDA-CE. Each contract entry ships with its source code (as deployed on-chain), human-readable documentation, machine-readable metadata, and an audit record.

The catalog is split into
two product trees: **`contracts/registry/`** (the observatory — verbatim observed
contracts, read-only reference) and **`contracts/library/`** (the product —
PCO-authored deployable templates with a strict quality gate).

---

## Top-level layout

```
README.md              — repository overview, mission & vision
ARCHITECTURE.md        — this file
CONTRIBUTING.md        — how to contribute contract entries and audits
CODE_OF_CONDUCT.md     — community guidelines
SECURITY.md            — vulnerability disclosure policy
LICENSE                — project license (Apache-2.0)
contracts/
  library/             — PCO-authored deployable templates (the product)
  registry/            — observed contracts, grouped by dependency layer
    kip/               — KIP standard interfaces (no executable logic)
    core/              — Pre-deployed KDA-CE chain infrastructure
    marmalade/         — Marmalade v2 NFT framework (pre-deployed)
    ecosystem/         — production third-party modules (deployment breadth + call-frequency census)
    community/         — census-observed community free-namespace modules
scripts/               — validation, index generation
docs/                  — onboarding, policies, index output (index.md, index.json)
```

---

## Dependency Layers

The `contracts/registry/` tree is organised by **dependency order** — lower layers are depended on by higher layers, never the reverse. (`contracts/library/` templates sit outside the layer stack: they implement Layer-0 interfaces and call Layer-1 modules, like any project built from the catalog would.)

```
Layer 0 — KIP Standards (registry/kip/)
  Pure interfaces: no executable code, no state.
  Every module that claims standard compliance must implement these.

    kip/fungible-v2            ◄─── implemented by coin, custom tokens
    kip/fungible-xchain-v1     ◄─── implemented by coin (cross-chain)
    kip/gas-payer-v1           ◄─── implemented by gas station modules
    kip/token-policy-v2        ◄─── implemented by all Marmalade policies
    kip/token-manifest              module (not interface); used by ledger

Layer 1 — Core Infrastructure (registry/core/)
  Pre-deployed production modules on all chains (0–19).
  Cannot be redeployed; integrate by calling them.

    core/coin                  implements kip/fungible-v2 + kip/fungible-xchain-v1
    core/ns                    namespace registry; called by define-namespace
    core/fungible-util         implements kip.account-protocols-v1; used by coin

Layer 2 — NFT Framework (registry/marmalade/)
  Marmalade v2 pre-deployed NFT stack.
  Depends on kip/ interfaces and core/coin for payments.

    marmalade/ledger            implements ledger-v2 + kip.poly-fungible-v3
                                    uses  kip/token-manifest
                                    delegates to  marmalade/policy-manager
    marmalade/policy-manager    calls kip/token-policy-v2 on each policy
                                    uses  core/coin (royalty payments)

Layer 3 — Ecosystem (registry/ecosystem/)
  Production modules from major KDA-CE ecosystem projects.
  Two selection cohorts:
    Cohort A (PR#15): top-10 by deployment breadth — (list-modules) on all 20 chains, Jan 2025
    Cohort B (PR#17): top-10 by function call frequency — block-payload-sampling census,
                      stride=1000, 90-day window, all 20 chains, March 2026

    --- Cohort A: deployment breadth ---
    ecosystem/kaddex/kaddex-kdx              implements fungible-v2 + fungible-xchain-v1
    ecosystem/runonflux/flux                 implements fungible-v2
    ecosystem/lago/kwBTC                     (governance shell — namespace reservation only)
    ecosystem/lago/kwUSDC                    (governance shell — namespace reservation only)
    ecosystem/lago/USD2                      (governance shell — namespace reservation only)
    ecosystem/kadena/spirekey                implements gas-payer-v1
    ecosystem/marmalade-sale/conventional-auction  implements marmalade-v2.sale-v2
    ecosystem/marmalade-sale/dutch-auction         implements marmalade-v2.sale-v2
    ecosystem/mok/mok-token                  implements fungible-v2 + fungible-xchain-v1
    ecosystem/arkade/arkade-token            implements fungible-v2 + fungible-xchain-v1

    --- Cohort B: call frequency (rank #1–10 exc. already cataloged) ---
    ecosystem/kia/kia-oracle                 price oracle (key/value, batch writes)
    ecosystem/chips/chips                    DeFi/gaming protocol (locking, staking, orders)
    ecosystem/chips/chips-oracle             NFT price oracle for Chips protocol
    ecosystem/kdlaunch/kdswap-exchange       AMM DEX (formal verification, constant-product)
    ecosystem/brothers-dao/bro-dex-core      order-book DEX — BRO/KDA market (BUSL-1.1)
    ecosystem/brothers-dao/bro               BRO governance token (fungible-v2)
    ecosystem/heron/heron                    community utility token (fungible-v2, mass conservation FV)

Layer 4 — Community On-Chain (registry/community/)
  Census-observed community free-namespace modules (verbatim snapshots).
  Implements interfaces from Layer 0. Depends on Layer 1 for runtime calls.

    registry/community/cyberfly/cyberfly-node   DePIN node registry (staking, rewards)
    registry/community/cyberfly/cyberfly-token  CFLY token (fungible-v2 + fungible-xchain-v1)
    registry/community/p2p-escrow               P2P escrow with reputation
                                                (⚠️ CRITICAL open finding — see AUDIT.md)

Library — Deployable Templates (contracts/library/)
  PCO-authored starting points. Outside the registry layer stack.
  Quality gate: schema-A metadata, co-located .repl tests,
  audit_status self-reviewed or better. Entries with open CRITICAL
  findings can never live here.

    library/hello-world                tutorial entry point
    library/token-fungible             implements kip/fungible-v2
```

### Full dependency graph

```
kip/fungible-v2 ◄──────────────── core/coin ◄──── core/ns
kip/fungible-xchain-v1 ◄─────────┘          ◄──── core/fungible-util
kip/gas-payer-v1                                      │
kip/token-manifest ◄──────────── marmalade/ledger ◄───┤
kip/token-policy-v2 ◄────────── marmalade/policy-mgr  │
                                      └── core/coin ───┘
library/* + registry/community/* ── kip/* + core/*

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

cohort-B additions (call-frequency census):
ecosystem/kia/kia-oracle──────── free.util-time
ecosystem/chips/chips─────────── kip/fungible-v2 ► core/coin
                                ► chips-oracle ► chips-presale
ecosystem/chips/chips-oracle──── core/coin
ecosystem/kdlaunch/kdswap──────── kip/fungible-v2 ► core/coin
ecosystem/brothers-dao/bro──────── kip/fungible-v2 + kip/fungible-xchain-v1
                                 ► free.util-fungible
ecosystem/brothers-dao/bro-dex── bro ► core/coin ► free.util-lists ► free.util-math
ecosystem/heron/heron────────────kip/fungible-v2 + kip/fungible-xchain-v1

registry/community/cyberfly-token── kip/fungible-v2 + kip/fungible-xchain-v1
                                 ► free.util-fungible
registry/community/cyberfly-node── core/coin ► free.cyberfly_token
registry/community/p2p-escrow──── core/coin  (⚠️ governance: true — CRITICAL, unaudited)

library/token-fungible─────────── kip/fungible-v2
library/hello-world────────────── (no deps)
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

| Tree | Provenance | Source repository |
|------|------------|-------------------|
| `registry/kip/` | Upstream Kadena LLC | [kadena-io/marmalade/pact/kip/](https://github.com/kadena-io/marmalade/tree/main/pact/kip) + [chainweb-node](https://github.com/kda-community/chainweb-node) |
| `registry/core/` | Upstream Kadena LLC | [kadena-io/marmalade/pact/root/](https://github.com/kadena-io/marmalade/tree/main/pact/root) + chainweb-node |
| `registry/marmalade/` | Upstream Kadena LLC | [kadena-io/marmalade/pact/](https://github.com/kadena-io/marmalade/tree/main/pact) |
| `registry/ecosystem/` | Third-party projects | Various (see each module's `metadata.yaml`) — verified from mainnet01 blockchain census Jan 2025 / Mar 2026 |
| `registry/community/` | Community projects | Census-observed free-namespace modules (see each module's `metadata.yaml`) |
| `library/` | PCO contributors | [Pact-Community-Organization/pact-contract-catalog](https://github.com/Pact-Community-Organization/pact-contract-catalog) |

> All `registry/` entries are **observed entries** — verbatim snapshots of upstream or on-chain code, catalogued to document what community modules build upon and integrate with. PCO makes no security claim beyond the recorded audit status. Only `library/` entries are authored, maintained, and quality-gated by PCO.

---

## Governance notes

- Additions to `registry/kip/`, `registry/core/`, or `registry/marmalade/` require a maintainer PR for upstream sync.
- Additions to `registry/ecosystem/` and `registry/community/` require evidence of deployment on mainnet01 (module hash, describe-module output, or block explorer link) plus a PR matching the census methodology in `contracts/registry/ecosystem/README.md`.
- Additions to `library/` require a PR linking a GitHub issue, passing CI (including the library quality gate: schema-A metadata, co-located `.repl` tests, `audit_status` of `self-reviewed` or better), and approval per `CONTRIBUTING.md`.
- Entries with an open CRITICAL finding live in `registry/`, never `library/`.
- Audit promotions follow the ladder in `docs/CONTRACT_POLICIES.md` §3.1 (`reference` / `unaudited` / `self-reviewed` / `community-reviewed` / `independently-audited`) and require evidence in `AUDIT.md`.