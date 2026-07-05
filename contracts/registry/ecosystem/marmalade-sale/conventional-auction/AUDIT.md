# AUDIT — marmalade-sale.conventional-auction

## Summary

| Field | Value |
|---|---|
| **Module** | `marmalade-sale.conventional-auction` |
| **Deployed Hash** | `CRTIH0nyjQlEfqWNtptm…` |
| **Audit Status** | Community Reviewed |

## Security Observations

- Implements `marmalade-v2.sale-v2` — all bid and finalization logic is routed
  through the policy-manager's escrow pattern. Funds are not held directly by
  this module; the policy-manager holds them during auction.
- Bid escrow: losing bids must be refundable. Verify the refund logic cannot
  be blocked (e.g., by a malicious bidder guard).
- Auction finalization: callable by anyone after the deadline; proceeds go
  directly to seller as defined when the auction was created.

## Compliance with PCO Standards

| Check | Status |
|---|---|
| `sale-v2` fully implemented | ✅ |
| Escrow via policy-manager | ✅ |
| Open source | ✅ |

## Risk Rating

**LOW** — Standard Marmalade sale contract with open source and framework protections.
