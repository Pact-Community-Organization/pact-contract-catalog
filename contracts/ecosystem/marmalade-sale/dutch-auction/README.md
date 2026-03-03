# marmalade-sale.dutch-auction — NFT Dutch Auction

| Field | Value |
|---|---|
| **Module** | `marmalade-sale.dutch-auction` |
| **Project** | Marmalade |
| **Category** | NFT Dutch Auction |
| **Chains Deployed** | 20 / 20 |
| **Blockchain Hash** | `tXavhdiFeIFFPHklwz2A…` |
| **Source** | [marmalade-io/marmalade](https://github.com/marmalade-io/marmalade) |

## Overview

The **Dutch auction** implements a declining-price NFT sale: the price starts at
a high ceiling and decreases at each block interval until a buyer accepts or the
floor price is reached. This mechanism is well-suited for price discovery on new
or rare NFT collections.

## Interfaces Implemented

| Interface | Purpose |
|---|---|
| `marmalade-v2.sale-v2` | Standard Marmalade sale interface |

## Auction Flow

```
1. Seller sets start-price, end-price, and duration
2. Price decreases linearly per block
3. First buyer to call (buy ...) at current price wins immediately
4. NFT transferred; proceeds go to seller
```

## Key Functions

```pact
;; Get current price at current block
(marmalade-sale.dutch-auction.current-price token-id auction-id)

;; Buy at current price
(marmalade-sale.dutch-auction.buy token-id auction-id buyer)
```

## Related Modules

- [`marmalade-sale.conventional-auction`](../conventional-auction/) — ascending-price auction
- [`marmalade-v2.ledger`](../../../marmalade/ledger/) — NFT ledger
- [`marmalade-v2.policy-manager`](../../../marmalade/policy-manager/) — routing

## References

- GitHub: https://github.com/marmalade-io/marmalade
