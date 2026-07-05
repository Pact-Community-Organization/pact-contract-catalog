# marmalade/ — Marmalade v2 NFT Framework

This layer contains the **Marmalade v2** NFT framework pre-deployed on all KDA-CE chains. Marmalade is KDA-CE's production NFT standard — it powers token creation, minting, burning, and multi-step sales with composable policies.

---

## Architecture

Marmalade v2 is split into two complementary modules:

```
marmalade-v2.ledger  ←────────────────────────────────────────────┐
  │  manages all token state (balances, supply, guards)            │
  │  enforces ledger rules (precision, account guards)             │
  │  delegates policy enforcement to ──────────────────────────▶  marmalade-v2.policy-manager
  │                                                                   │
  │  implements ──────────────────────────────────────────────────▶  marmalade-v2.ledger-v2 (interface)
  │  implements ──────────────────────────────────────────────────▶  kip.poly-fungible-v3 (interface)
  │                                                                   │
  │  uses ─────────────────────────────────────────────────────────▶ kip/token-manifest
  │                                                                   │  (token ID + metadata)
  │                                                                   │
  │                                                        calls each ▼
  │                                                   <policy module implementing kip/token-policy-v2>
  │                                                  ├── marmalade-v2.guard-policy-v1
  │                                                  ├── marmalade-v2.royalty-policy-v1
  │                                                  ├── marmalade-v2.non-fungible-policy-v1
  │                                                  ├── marmalade-v2.collection-policy-v1
  │                                                  └── <your custom policy>
  │
  └── SALE defpact (two-step: offer → buy/withdraw)
        step 0: offer  → enforce-offer on all policies
        step 1a: buy   → enforce-buy, KDA payment → royalty-policy
        step 1b: withdraw → enforce-withdraw, return tokens
```

---

## Contents

| Module | Directory | Description |
|--------|-----------|-------------|
| `marmalade-v2.ledger` | [ledger/](ledger/README.md) | Central NFT ledger — create-token, mint, burn, transfer, SALE |
| `marmalade-v2.policy-manager` | [policy-manager/](policy-manager/README.md) | Policy orchestration — routes enforce-* to all token policies |

---

## Source files in this layer

| File | Description |
|------|-------------|
| `ledger/marmalade-v2-ledger.pact` | Full ledger implementation (757 lines) |
| `ledger/ledger-v2-interface.pact` | `marmalade-v2.ledger-v2` interface |
| `ledger/ledger-interface.pact` | `marmalade-v2.ledger` interface (base) |
| `policy-manager/policy-manager.pact` | Full policy-manager implementation (560 lines) |
| `policy-manager/sale-interface.pact` | `marmalade-v2.sale-v2` sale pact interface |

---

## Creating an NFT — end-to-end flow

```pact
;; 1. Build a manifest
(let* ((uri (kip.token-manifest.uri "image/png" "ipfs://Qm..."))
       (datum (kip.token-manifest.create-datum uri {"name": "My NFT #1"}))
       (manifest (kip.token-manifest.create-manifest uri [datum])))

  ;; 2. Derive token ID (deterministic, content-addressed)
  (let ((token-id (marmalade-v2.ledger.create-token-id manifest "free")))

    ;; 3. Register token with policies
    (marmalade-v2.ledger.create-token
      token-id 0 manifest          ;; precision=0 → true NFT
      marmalade-v2.guard-policy-v1
      marmalade-v2.non-fungible-policy-v1)

    ;; 4. Mint to creator
    (marmalade-v2.ledger.mint token-id "alice" (read-keyset "alice-ks") 1.0)

    ;; 5. Put on sale
    (marmalade-v2.ledger.sale token-id "alice" 1.0 0)
    ;; Step 2: buyer calls (continue ...) with sale-id
  ))
```

---

## Related KIP interfaces

- [kip/token-policy-v2](../kip/token-policy-v2/README.md) — implement this to write custom policies
- [kip/token-manifest](../kip/token-manifest/README.md) — use this to build token metadata
- [core/coin](../core/coin/README.md) — KDA payments in royalty-policy and SALE
