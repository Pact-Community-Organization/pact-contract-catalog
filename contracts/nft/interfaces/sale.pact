;; nft.sale — the interface a sale contract (auction, timed sale, …) implements
;; so the policy-manager can drive quoted sales through it. Two read-only hooks
;; the manager enforces during the offer/buy defpact. Part of the PCO `nft`
;; framework. Fixed-price sales need no sale contract (handled inline by the
;; hardened manager); this interface is for price-discovery sale types.

(namespace (read-string 'ns))

(interface sale

  (defun enforce-quote-update:bool (sale-id:string price:decimal)
    @doc "Enforced at buy time to finalize/update the quote price for SALE-ID \
         \(e.g. an auction's winning bid). Read-only w.r.t. the manager's state.")

  (defun enforce-withdrawal:bool (sale-id:string)
    @doc "Enforced to allow the seller to withdraw the offer SALE-ID (e.g. only \
         \after an auction times out with no winning bid). Read-only.")
)
