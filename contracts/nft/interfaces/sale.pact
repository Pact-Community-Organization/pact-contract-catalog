;; nft.sale — the interface a sale contract (auction, timed sale, …) implements
;; so the policy-manager can drive quoted sales through it. Fixed-price sales
;; need no sale contract (handled inline by the hardened manager); this
;; interface is for price-discovery sale types, and only GOVERNANCE-REGISTERED
;; implementations participate.
;;
;; Both hooks run inside the manager's settlement/withdraw path only — an
;; implementation gates them with the manager's QUOTE-CALL / WITHDRAWAL-CALL
;; capabilities so they are unreachable from arbitrary callers. They must not
;; write the manager's state; they MAY read it, write their OWN state, and
;; move their OWN escrow (e.g. refund escrowed bids when permitting a
;; withdrawal).

(namespace (read-string 'ns))

(interface sale

  (defun enforce-quote-update:bool (sale-id:string price:decimal)
    @doc "Enforced at buy time to validate the finalized price for SALE-ID. \
         \PRICE arrives as a candidate from the buy transaction; the \
         \implementation MUST validate it against its own on-chain state \
         \(recorded bids, the price curve) — never accept a raw payload value \
         \— and reject a settlement whose buyer its rules do not allow.")

  (defun enforce-withdrawal:bool (sale-id:string)
    @doc "Enforced to allow the seller to withdraw the offer SALE-ID (e.g. \
         \only after an auction times out with no winning bid). If the \
         \implementation holds funds for SALE-ID, permitting withdrawal MUST \
         \also return them — no path may strand funds.")
)
