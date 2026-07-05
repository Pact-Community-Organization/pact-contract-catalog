# marmalade-sale.conventional-auction — NFT Conventional Auction

| Field | Value |
|---|---|
| **Module** | `marmalade-sale.conventional-auction` |
| **Project** | Marmalade |
| **Category** | NFT Auction Contract |
| **Chains Deployed** | 20 / 20 |
| **Blockchain Hash** | `CRTIH0nyjQlEfqWNtptm…` |
| **Source** | [marmalade-io/marmalade](https://github.com/marmalade-io/marmalade) |

## Overview

The **conventional auction** implements an ascending-price NFT auction compatible
with the Marmalade v2 sale framework. It is the primary mechanism for fixed-start
NFT auctions on Kadena — sellers set a reserve price, and the highest bidder within
the auction window wins the NFT.

## Interfaces Implemented

| Interface | Purpose |
|---|---|
| `marmalade-v2.sale-v2` | Standard Marmalade sale interface |

## Auction Flow

```
1. Seller calls (marmalade-v2.ledger.sale ...)
   → policy-manager routes to conventional-auction via sale-v2
2. Buyers call (conventional-auction.place-bid ...)
3. At auction end, winner calls (marmalade-v2.ledger.continue-pact ...)
   → NFT transferred to winner, proceeds to seller
```

## Key Functions

```pact
;; Place a bid
(marmalade-sale.conventional-auction.place-bid
  token-id auction-id bidder bid-amount)

;; Retrieve auction details
(marmalade-sale.conventional-auction.get-auction token-id)
```

## Related Modules

- [`marmalade-sale.dutch-auction`](../dutch-auction/) — declining-price alternative
- [`marmalade-v2.ledger`](../../../marmalade/ledger/) — NFT ownership and sale orchestration
- [`marmalade-v2.policy-manager`](../../../marmalade/policy-manager/) — sale routing

## References

- GitHub: https://github.com/marmalade-io/marmalade
