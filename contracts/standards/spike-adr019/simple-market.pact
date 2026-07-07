;; simple-market — a reference nft-marketplace (ADR-019 spike)
;;
;; A permissionless sale contract that owns NO tokens. It sells any nft-asset
;; consigned to its guard. Deployed into ITS OWN namespace (the spike deploys two
;; copies in two namespaces to prove "gallery to gallery"). Its fee account and
;; rate are its own policy; the asset caps the fee it will accept.
;;
;; The Pact-5 pattern (ADR-019 §2.4): execute-sale is PUBLIC and acquires SELL
;; internally, then calls nft::buy — a caller cannot acquire SELL from outside.
;; The NFT is a modref parameter, so one market sells any conforming NFT.

(namespace (read-msg 'ns))

(module simple-market GOVERNANCE
  @doc "A reference NFT marketplace: consignment-based, owns no tokens, charges \
       \its own fee, sells any nft-asset via a modref. Implements nft-marketplace."

  (implements std.nft-marketplace)

  (defcap GOVERNANCE () (enforce-keyset (read-msg 'admin-ks)))

  ;; This market's fee policy (its own; the asset caps what it will accept).
  ;; All bound at deploy from tx data so no call-time read-msg is needed.
  (defconst FEE-ACCOUNT:string (read-msg 'fee-account)
    @doc "Where this market's fee is paid. A principal.")
  (defconst FEE-GUARD:guard (read-keyset 'fee-guard)
    @doc "The fee account's guard, captured at deploy (used by buy's payout).")
  (defconst FEE-BPS:integer (read-integer 'fee-bps)
    @doc "This market's fee rate. The asset rejects it if above its own cap.")

  ;; The market's authority: an owner consigns to (marketplace-guard), and only
  ;; execute-sale (which acquires SELL) satisfies it.
  (defcap SELL ()
    @doc "Weak body by design: acquired ONLY inside execute-sale, never handed \
         \out. The asset's buy enforces the guard built from this cap, so only \
         \this market — and only through execute-sale — can settle a consigned \
         \sale."
    true)
  (defun sell-guard-pred:bool () (require-capability (SELL)))
  (defun marketplace-guard:guard () (create-user-guard (sell-guard-pred)))

  (defun execute-sale:string
    ( nft:module{std.nft-asset}
      buyer:string buyer-guard:guard )
    @doc "Sell NFT (consigned to this market) to BUYER. Acquires SELL internally \
         \so the asset's enforce-guard on the consignment guard passes, then \
         \calls nft::buy with this market's fee account/guard/rate. The asset \
         \pays the creator royalty itself — this market only adds its own fee."
    (with-capability (SELL)
      (nft::buy buyer buyer-guard FEE-ACCOUNT FEE-GUARD FEE-BPS)))
)
