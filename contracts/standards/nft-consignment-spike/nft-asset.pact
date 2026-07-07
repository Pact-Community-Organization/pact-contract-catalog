;; nft-asset — self-custody NFT standard
;;
;; The asset half of the asset/marketplace SEPARATION. Unlike a marketplace-owned
;; token (a row inside a marketplace ledger), an nft-asset module OWNS ITSELF: it
;; records its own owner, its immutable creator royalty, and the
;; single active CONSIGNMENT (which marketplace guard may currently sell it).
;; This is what lets the same NFT be sold by any marketplace, in any namespace —
;; "the painting moves gallery to gallery."
;;
;; Two Pact-5 facts drive the shape (design note):
;;   * A foreign marketplace cannot acquire this module's capabilities, so a sale
;;     is authorized by an enforce-guard on the RECORDED consignment guard, not a
;;     cap the caller acquires. `buy` is public; its guard check passes only for
;;     the currently-consigned marketplace.
;;   * The NFT pays its OWN royalty inside `buy`, so no marketplace can skim or
;;     bypass it, whoever triggers the sale.
;;
;; Spike interface — signatures are provisional (a production interface is frozen
;; forever; this one is a proving ground, not published).

(interface nft-asset

  @doc "A self-custody 1-of-1 NFT with an immutable creator royalty and a single \
       \active marketplace consignment. Ownership, royalty, and the consignment \
       \are authoritative HERE, in the asset — a marketplace owns no tokens."

  ;; --- views (read-only) ----------------------------------------------------
  (defun get-owner:string ()
    @doc "The current owner account.")
  (defun get-creator:string ()
    @doc "The permanent royalty payee, fixed at mint.")
  (defun get-royalty-bps:integer ()
    @doc "The immutable royalty rate in basis points.")
  (defun get-price:decimal ()
    @doc "The consigned sale price (0.0 when not listed).")
  (defun is-listed:bool ()
    @doc "True iff the NFT is currently consigned to a marketplace. Total.")
  (defun is-frozen:bool ()
    @doc "True iff the economic terms are locked (always true after mint). Total.")

  ;; --- owner actions --------------------------------------------------------
  (defun transfer:string (receiver:string receiver-guard:guard)
    @doc "Free (no-payment) transfer. Owner-authorized. MUST reject when the NFT \
         \is currently consigned (delist first). RECEIVER MUST be a principal.")

  (defun list-for-sale:string (mkt-guard:guard price:decimal)
    @doc "Consign this NFT to ONE marketplace: record MKT-GUARD (the guard only \
         \that marketplace can satisfy) and PRICE. Owner-authorized. A second \
         \list-for-sale SUPERSEDES the first — exactly one consignment is ever \
         \active, so two marketplaces can never both sell it. PRICE MUST be \
         \positive and MUST NOT floor the royalty to zero.")

  (defun delist:string ()
    @doc "Revoke the active consignment (the painting returns to the wallet). \
         \Owner-authorized.")

  ;; --- the sale (public; authorized by the consignment guard) ---------------
  (defun buy:string
    ( buyer:string buyer-guard:guard
      fee-account:string fee-guard:guard fee-bps:integer )
    @doc "Purchase the consigned NFT. Callable by ANYONE, but MUST enforce the \
         \recorded consignment guard — so in practice only the consigned \
         \marketplace's `execute-sale` (which holds that guard) can complete it. \
         \BUYER signs the coin transfer of the full price into THIS module's \
         \escrow; the module pays royalty (from state, to the creator) + the \
         \marketplace fee (FEE-BPS, to FEE-ACCOUNT, capped so a hostile fee \
         \cannot exceed the module's limit) + the remainder to the seller, and \
         \asserts the escrow returns to baseline. BUYER and FEE-ACCOUNT MUST be \
         \principals. Economics (royalty, price) come from STATE, never the tx.")
)
