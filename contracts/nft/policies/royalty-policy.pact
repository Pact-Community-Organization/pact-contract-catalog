;; nft.royalty-policy — genuinely enforced on-chain creator royalties.
;;
;; The royalty terms (creator, creator-guard, bps, sale-only) are REQUIRED in
;; the create-token transaction and bound into this policy's OWN state at init
;; — fail closed: a missing or partial spec aborts token creation (the POL-1
;; fix), and nothing about the royalty is ever read from a buy transaction
;; (the ARCH-2 fix).
;;
;; At settlement this policy DECLARES the creator's cut — computed from its
;; stored spec and the manager's state-bound quote price — and moves no money;
;; the policy-manager's single conservation-asserted settlement pays it (the
;; ARCH-1 / POL-3 fix).
;;
;; Sale-only is an explicit opt-in flag in the spec, enforced by rejecting
;; free transfers — a sale through the ledger's sale pact ALWAYS works and
;; always pays the royalty, so the royalty cannot be composed away by another
;; policy and never becomes a blanket transfer ban (the POL-2 fix). The
;; dust-price guard at offer rejects a price whose floored royalty would be
;; zero, closing the round-to-zero evasion path.
;;
;; CURRENCY: the royalty is denominated in the QUOTE's fungible — the seller
;; picks the sale currency per listing (multi-currency by design, matching the
;; catalog's marketplace standard). A creator who wants royalties in one fixed
;; currency can stack a currency-pinning policy; note that no on-chain rule can
;; stop economically-equivalent evasion (e.g. under-priced quotes settled
;; off-chain), so the guarantees here are: the rate binds at create, the cut is
;; computed from state, and every on-pact sale pays it.
;;
;; Every hook requires the ledger's matching -CALL capability in scope, so no
;; hook is reachable outside the real ledger lifecycle path.

(namespace (read-string 'ns))

(module royalty-policy GOVERNANCE
  @doc "Hardened creator-royalty policy for the nft framework: spec bound at \
       \create, cut declared from state at settlement, explicit sale-only."

  (implements token-policy)
  (use token-policy [token-info payout])

  (defconst ADMIN-KS:string (read-string 'admin-ks)
    @doc "Admin keyset name, captured ONCE at deploy — never read from a \
         \caller's payload at enforcement time.")

  (defcap GOVERNANCE ()
    (enforce-keyset ADMIN-KS))

  (defconst BPS-DENOM:integer 10000)
  (defconst MAX-ROYALTY-BPS:integer 5000
    @doc "Sanity cap on the royalty rate a creator may set: 50%.")
  (defconst ROYALTY-SPEC-MSG-KEY:string "royalty_spec"
    @doc "Create-token-tx payload key carrying the royalty spec (the \
         \CREATOR's tx — economics are never read from a buy tx).")

  (defschema royalty-spec
    @doc "The royalty terms, bound once at token creation, immutable after."
    creator:string
    creator-guard:guard
    bps:integer
    sale-only:bool)
  (deftable royalties:{royalty-spec})

  (defcap ROYALTY:bool (token-id:string creator:string bps:integer sale-only:bool)
    @doc "Emitted once, when the royalty terms bind at token creation."
    @event true)

  ;; --- views -------------------------------------------------------------------
  (defun get-royalty:object{royalty-spec} (token-id:string)
    (read royalties token-id))

  ;; --- the creator's cut, computed from STATE ----------------------------------
  (defun royalty-cut:decimal (sale-id:string bps:integer)
    @doc "floor(price * bps / 10000) at the quote fungible's precision. The \
         \price comes from the manager's state-bound quote, never a payload."
    (let* ((q (policy-manager.get-quote sale-id))
           (fungible:module{fungible-v2} (at 'fungible q))
           (prec:integer (fungible::precision)))
      (floor (/ (* (at 'price q) (dec bps)) (dec BPS-DENOM)) prec)))

  ;; --- token-policy hooks --------------------------------------------------------
  ;; Each hook first requires the ledger's matching -CALL capability (via the
  ;; manager's registered ledger modref), so it is unreachable outside the real
  ;; ledger lifecycle path — direct calls with fabricated token-info fail.

  (defun enforce-init:bool (token:object{token-info})
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::INIT-CALL (at 'id token) (at 'precision token) (at 'uri token))))
    ;; the spec is REQUIRED (typed read: absent or partial -> abort, fail closed)
    (let ((spec:object{royalty-spec} (read-msg ROYALTY-SPEC-MSG-KEY)))
      (let ((creator:string (at 'creator spec))
            (creator-guard:guard (at 'creator-guard spec))
            (bps:integer (at 'bps spec)))
        (enforce (and (>= bps 0) (<= bps MAX-ROYALTY-BPS))
          (format "royalty bps must be in [0, {}]" [MAX-ROYALTY-BPS]))
        (enforce (validate-principal creator-guard creator)
          "creator must be the principal account of creator-guard")
        (insert royalties (at 'id token) spec)
        (emit-event (ROYALTY (at 'id token) creator bps (at 'sale-only spec)))))
    true)

  (defun enforce-mint:bool (token:object{token-info} account:string guard:guard amount:decimal)
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::MINT-CALL (at 'id token) account amount)))
    true)

  (defun enforce-burn:bool (token:object{token-info} account:string amount:decimal)
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::BURN-CALL (at 'id token) account amount)))
    true)

  (defun enforce-offer:bool (token:object{token-info} seller:string amount:decimal timeout:integer sale-id:string)
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::OFFER-CALL (at 'id token) seller amount timeout sale-id)))
    ;; dust guard: a price whose floored royalty is zero would evade the
    ;; royalty — reject it at offer (only when a royalty is actually set).
    ;; A QUOTED sale's price is 0 at offer (discovered at settlement); its
    ;; dust guard fires in enforce-buy against the finalized price instead.
    (with-read royalties (at 'id token) { 'bps := bps }
      (if (> bps 0)
        (let ((price:decimal (policy-manager.get-quote-price sale-id)))
          (if (> price 0.0)
            (let ((cut:decimal (royalty-cut sale-id bps)))
              (enforce (> cut 0.0) "price too low: the royalty would floor to zero"))
            true))
        true))
    true)

  (defun enforce-withdraw:bool (token:object{token-info} seller:string amount:decimal timeout:integer sale-id:string)
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::WITHDRAW-CALL (at 'id token) seller amount timeout sale-id)))
    true)

  (defun enforce-buy:[object{payout}] (token:object{token-info} seller:string buyer:string buyer-guard:guard amount:decimal sale-id:string)
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::BUY-CALL (at 'id token) seller buyer amount sale-id)))
    (with-read royalties (at 'id token)
      { 'creator := creator, 'creator-guard := creator-guard, 'bps := bps }
      (let ((cut:decimal (royalty-cut sale-id bps)))
        ;; settlement-time dust guard: for a quoted sale (price finalized at
        ;; buy) this is where round-to-zero evasion is caught
        (if (> bps 0)
          (enforce (> cut 0.0) "price too low: the royalty would floor to zero")
          true)
        (if (> cut 0.0)
          [{ 'account: creator, 'guard: creator-guard, 'amount: cut }]
          []))))

  (defun enforce-transfer:bool (token:object{token-info} sender:string guard:guard receiver:string amount:decimal)
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::TRANSFER-CALL (at 'id token) sender receiver amount)))
    (with-read royalties (at 'id token) { 'sale-only := sale-only }
      (enforce (not sale-only)
        "sale-only token: free transfer is disabled — sell via the sale pact"))
    true)
)
