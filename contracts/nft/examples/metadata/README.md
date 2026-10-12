# Example metadata

Off-chain JSON a creator pins (IPFS) and names in the token `uri`. The shape is the
Marmalade-NG `meta-schema-v1` (`name`, `description`, `image` required; `attributes`;
`properties.{external_url, animation_url, authors, collection}`), the closest thing to a
Kadena-wide convention, so any indexer that reads Marmalade metadata reads ours.

Two rules the examples follow:

1. **Display copy lives here; anything a CONTRACT must read lives on chain.** The
   Pokémon-style card keeps its name and art here, but its mana/hp/atk/def/abilities and
   the game-written level/wins are `nft.attributes-policy` keys, readable with one call
   (`get-attributes`, `get-attribute-or`). The `properties.onchain` block documents which
   keys exist and who writes them; it is documentation, never the source of truth.
2. **Nothing here is trusted by the chain.** The uri is pinned in the token id; what the
   JSON says about editions, royalties or odds is a courtesy copy of what the policies
   enforce (`issuance-policy`, `royalty-policy`, `pack-engine.get-odds`).

| File | Family | Policies in the emulation suite |
|---|---|---|
| `baseball-card.json` | edition of 10 in a capped season | collection, issuance, royalty, non-updatable-uri, transfer-mode(free) |
| `pokemon-card.json` | unique card with on-chain game stats | attributes, issuance(1), royalty, transfer-mode |
| `art.json` | evolving 1/1 | royalty, guarded-uri(onchain history, holder freeze), issuance(1), transfer-mode(free) |
| `music-edition.json` | edition of 100, 3-way split | issuance, royalty(beneficiaries + primary), transfer-mode(free) |
| `pack.json` | sealed booster | issuance, transfer-mode(free) + pack-engine series |

The suites that exercise these shapes: `test/emulation-collectibles.repl` and `test/market-sim.repl`.
