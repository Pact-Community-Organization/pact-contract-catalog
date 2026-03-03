# Ecosystem Layer

Production contracts deployed by major projects on the Kadena Community Edition blockchain.
All modules in this layer appear on **every one of Kadena's 20 chains** (20/20 deployment)
and were selected based on live blockchain census data from `mainnet01`.

## Selection methodology

1. Called `(list-modules)` on all 20 chains via the `/local` API.
2. Counted cross-chain deployment frequency (max 20/20).
3. Excluded modules already in `core/`, `kip/`, or `marmalade/` layers.
4. Excluded coin, meme tokens, and test modules.
5. Selected the top 10 by frequency + ecosystem significance.

## Modules

| Module | Project | Category | Chains |
|--------|---------|----------|--------|
| [`kaddex.kdx`](kaddex/kaddex-kdx/) | Ecko DEX | Governance token | 20/20 |
| [`runonflux.flux`](runonflux/flux/) | RunOnFlux | Cloud-computing token | 20/20 |
| [`lago.kwBTC`](lago/kwBTC/) | Lago Bridge | Wrapped Bitcoin | 20/20 |
| [`lago.kwUSDC`](lago/kwUSDC/) | Lago Bridge | Wrapped USDC | 20/20 |
| [`lago.USD2`](lago/USD2/) | Lago Bridge | USD stablecoin | 20/20 |
| [`kadena.spirekey`](kadena/spirekey/) | Kadena Inc. | WebAuthn auth / gas payer | 20/20 |
| [`marmalade-sale.conventional-auction`](marmalade-sale/conventional-auction/) | Marmalade | NFT fixed-price auction | 20/20 |
| [`marmalade-sale.dutch-auction`](marmalade-sale/dutch-auction/) | Marmalade | NFT Dutch auction | 20/20 |
| [`mok.token`](mok/mok-token/) | Momentum | Governance token | 20/20 |
| [`arkade.token`](arkade/arkade-token/) | Arkade | Gaming utility token | 20/20 |

## Dependency overview

```
kaddex.kdx────────────implements──────► fungible-v2
                                      ► fungible-xchain-v1
                                      ► kaddex.supply-control-v1
                                      ► kaddex.special-accounts-v1

runonflux.flux────────implements──────► fungible-v2

lago.kwBTC / kwUSDC / USD2──────────── (standalone, bridge-managed)

kadena.spirekey───────implements──────► gas-payer-v1

marmalade-sale.conventional-auction──► marmalade-v2.sale-v2
marmalade-sale.dutch-auction─────────► marmalade-v2.sale-v2

mok.token─────────────implements──────► fungible-v2
                                      ► fungible-xchain-v1

arkade.token──────────implements──────► fungible-v2
                                      ► fungible-xchain-v1
```

## Adding ecosystem modules

1. Create a directory `contracts/ecosystem/<project>/<module-name>/`.
2. Add `metadata.yaml`, `README.md`, `AUDIT.md`, and the `.pact` source file.
3. Run `scripts/generate_index.sh` to rebuild `docs/index.md`.
4. Open a PR that links to the issuing project's GitHub or deployment transaction.
