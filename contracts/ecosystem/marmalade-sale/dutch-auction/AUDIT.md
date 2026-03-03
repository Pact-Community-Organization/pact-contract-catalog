# AUDIT — marmalade-sale.dutch-auction

## Summary

| Field | Value |
|---|---|
| **Module** | `marmalade-sale.dutch-auction` |
| **Deployed Hash** | `tXavhdiFeIFFPHklwz2A…` |
| **Audit Status** | Community Reviewed |

## Security Observations

- Price calculation must be deterministic given block height; verify no off-chain price oracle dependency.
- First-buyer-wins race condition: at very low prices, front-running may occur. This is inherent to Dutch auctions.
- Same escrow safety as conventional-auction via policy-manager.

## Risk Rating

**LOW** — Standard Dutch auction using Marmalade escrow protections.
