# Contract Index

_Generated from `contracts/**/metadata.yaml`._

- **Library** — PCO-authored deployable templates: copy, adapt, deploy.
- **Registry** — observed contracts (upstream standards + on-chain census): read-only reference.
- **Standards** — the Kadena NFT interface standard v1: not metadata-indexed; see [contracts/standards/](../contracts/standards/SPEC.md).
- **NFT Framework** — the PCO shared-ledger NFT ecosystem: not metadata-indexed; see [contracts/nft/](../contracts/nft/README.md).

## Library — Deployable Templates (`library/`)

| Name | Slug | Version | Audit Status | Tags |
|------|------|---------|--------------|------|
| DAO Voting (membership, quorum + threshold) | dao-voting | 1.0.0 | self-reviewed | dao, voting, governance, template, library |
| Gas Station (drain-defended) | gas-station | 1.0.0 | self-reviewed | gas-station, gas-payer-v1, gasless, template, library |
| Hello World | hello-world | 1.0.0 | self-reviewed | hello-world, tutorial, basic |
| Multisig Treasury (M-of-N) | multisig-treasury | 1.0.0 | self-reviewed | treasury, multisig, governance, template, library |
| Oracle Feed (median, staleness-guarded) | oracle-feed | 1.0.0 | self-reviewed | oracle, price-feed, median, template, library |
| Property Lease (rental rails) | property-lease | 1.0.0 | self-reviewed | lease, rental, escrow, revenue-split, template, library |
| Royalty Sale (conservation-checked NFT marketplace) | royalty-sale | 1.0.0 | self-reviewed | nft, royalty, marketplace, escrow, template, library |
| Fixed-Supply Token with Advisory Governance | token-fixed-supply-gov | 1.0.0 | self-reviewed | token, fungible, fixed-supply, governance, voting, template, library |
| Fixed-Supply Token (frozen, one-shot mint) | token-fixed-supply | 1.0.0 | self-reviewed | token, fungible, fixed-supply, non-upgradeable, template, library |
| Token (fungible-v2 + fungible-xchain-v1) | token-fungible | 0.2.0 | self-reviewed | token, fungible, template, library |
| Token Vesting (cliff + linear) | vesting | 1.0.0 | self-reviewed | vesting, escrow, timelock, template, library |

## Registry — KIP Standards (`registry/kip/`)

| Name | Slug | Version | Audit Status | Tags |
|------|------|---------|--------------|------|
| fungible-v2 | fungible-v2 | 2.0.0 | reference | interface, fungible, token, standard, kip, core, pre-deployed |
| fungible-xchain-v1 | fungible-xchain-v1 | 1.0.0 | reference | interface, fungible, cross-chain, xchain, spv, core, pre-deployed |
| gas-payer-v1 | gas-payer-v1 | 1.0.0 | reference | interface, gas, gas-station, meta, core, pre-deployed |

## Registry — Core Infrastructure (`registry/core/`)

| Name | Slug | Version | Audit Status | Tags |
|------|------|---------|--------------|------|
| coin | coin | 6.0.0 | reference | coin, kda, fungible, transfer, gas, core, pre-deployed |
| util.fungible-util | util-fungible-util | 1.0.0 | reference | utility, fungible, validation, helper, pre-deployed |
| ns | ns | 1.0.0 | reference | namespace, governance, registry, core, pre-deployed |

## Registry — Ecosystem Modules (`registry/ecosystem/`) — census

| Name | Slug | Version | Audit Status | Category | Chains |
|------|------|---------|--------------|----------|--------|
| arkade.token | arkade.token | 1.0 | unaudited | gaming-token | 20/20 |
| n_f6aa9328b19b8bf7e788603bd669dcf549e07575.bro-dex-core-BRO-KDA-M | n_f6aa9328b19b8bf7e788603bd669dcf549e07575.bro-dex-core-BRO-KDA-M | 1.0 | community-reviewed | dex | 1/20 |
| n_582fed11af00dc626812cd7890bb88e72067f28c.bro | n_582fed11af00dc626812cd7890bb88e72067f28c.bro | 1.0 | community-reviewed | governance-token | 1/20 |
| n_e98a056e3e14203e6ec18fada427334b21b667d8.chips-oracle | n_e98a056e3e14203e6ec18fada427334b21b667d8.chips-oracle | 1.0 | community-reviewed | oracle | 1/20 |
| n_e98a056e3e14203e6ec18fada427334b21b667d8.chips | n_e98a056e3e14203e6ec18fada427334b21b667d8.chips | 1.0 | community-reviewed | defi-protocol | 1/20 |
| n_e309f0fa7cf3a13f93a8da5325cdad32790d2070.heron | n_e309f0fa7cf3a13f93a8da5325cdad32790d2070.heron | 1.0 | community-reviewed | fungible-token | 1/20 |
| kaddex.kdx | kaddex.kdx | 1.0 | community-reviewed | governance-token | 20/20 |
| kadena.spirekey | kadena.spirekey | 1.0 | community-reviewed | authentication | 20/20 |
| kdlaunch.kdswap-exchange | kdlaunch.kdswap-exchange | 1.0 | community-reviewed | dex | 1/20 |
| n_40c883decc192e1e3214898f04656b2e9ea7b74e.kia-oracle | n_40c883decc192e1e3214898f04656b2e9ea7b74e.kia-oracle | 1.0 | community-reviewed | oracle | 1/20 |
| lago.USD2 | lago.USD2 | 1.0 | unaudited | governance-shell | 20/20 |
| lago.kwBTC | lago.kwBTC | 1.0 | unaudited | governance-shell | 20/20 |
| lago.kwUSDC | lago.kwUSDC | 1.0 | unaudited | governance-shell | 20/20 |
| mok.token | mok.token | 1.0 | unaudited | governance-token | 20/20 |
| runonflux.flux | runonflux.flux | 1.0 | community-reviewed | utility-token | 20/20 |

## Registry — Community On-Chain Modules (`registry/community/`) — census

| Name | Slug | Version | Audit Status | Category | Chains |
|------|------|---------|--------------|----------|--------|
| free.cyberfly_node | free.cyberfly_node | 1.0 | community-reviewed | depin | 1/20 |
| free.cyberfly_token | free.cyberfly_token | 1.0 | community-reviewed | governance-token | 1/20 |
| free.p2p-escrow | free.p2p-escrow | 1.0 | unaudited | utility | 1/20 |

