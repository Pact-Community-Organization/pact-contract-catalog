;; nft.issuance-policy — a fixed print run, minted only where the token was born.
;;
;; ADR-NFT-002. A token's supply is a per-chain number that falls on burn and on
;; relocation, so a cap on SUPPLY re-opens after copies leave or die (that is
;; the flaw in every "max supply" policy that checks supply + amount <= max).
;; This policy caps what was EVER PRINTED instead:
;;   * `issued` counts every mint of this token on its ORIGIN chain and never
;;     goes down — a burn or a relocation frees no quota;
;;   * mint is refused on every chain but the origin chain (token-info carries
;;     `origin-chain`, the chain hashed into the id), so the row that a
;;     relocation materialises elsewhere can never grow there;
;;   * `max-issued` and `min-mint` are REQUIRED at creation (fail closed) and
;;     immutable; a new print run is a new token (new serial, new id).
;; Invariant, provable on the origin chain alone: copies in existence across
;; every chain <= max-issued. For a unique, set max-issued 1 with precision 0
;; and (optionally) attach non-fungible-policy for the minted-once marker.
;;
;; Every hook requires the ledger's matching -CALL capability in scope, so no
;; hook is reachable outside the real ledger lifecycle path.

(namespace (read-string 'ns))

(module issuance-policy GOVERNANCE
  @doc "Fixed print run for the nft framework: max-issued and min-mint bound \
       \at creation, a cumulative issued counter that never decreases, and \
       \minting allowed only on the token's origin chain."

  (implements token-policy)
  (use token-policy [token-info payout])

  (defconst ADMIN-KS:string (read-string 'admin-ks)
    @doc "Admin keyset name, captured ONCE at deploy — never read from a \
         \caller's payload at enforcement time.")

  (defcap GOVERNANCE ()
    (enforce-keyset ADMIN-KS))

  (defconst ISSUANCE-MSG-KEY:string "issuance_spec"
    @doc "Creation payload key: { max-issued: decimal, min-mint: decimal }. \
         \Typed read — a missing or partial spec aborts creation.")

  (defschema issuance-spec
    @doc "What the creator fixes at creation."
    max-issued:decimal
    min-mint:decimal)

  (defschema issuance-row
    max-issued:decimal
    min-mint:decimal
    issued:decimal)
  (deftable issuance:{issuance-row})

  (defcap ISSUANCE:bool (token-id:string max-issued:decimal min-mint:decimal)
    @doc "Emitted at creation with the print run fixed for TOKEN-ID."
    @event true)
  (defcap ISSUED:bool (token-id:string issued:decimal max-issued:decimal)
    @doc "Emitted on every mint on the origin chain with the cumulative count."
    @event true)

  ;; --- views -------------------------------------------------------------------
  (defun get-issuance:object{issuance-row} (token-id:string)
    (read issuance token-id))

  (defun remaining:decimal (token-id:string)
    @doc "What can still be printed, anywhere, ever: max-issued - issued. \
         \Authoritative only on the origin chain; elsewhere it reflects the \
         \last passport that arrived."
    (with-read issuance token-id { 'max-issued := mx, 'issued := is } (- mx is)))

  (defun is-origin-chain:bool (token:object{token-info})
    (= (at 'origin-chain token) (at 'chain-id (chain-data))))

  (defun enforce-valid-spec:bool (precision:integer max-issued:decimal min-mint:decimal)
    (enforce (> max-issued 0.0) "max-issued must be positive")
    (enforce (> min-mint 0.0) "min-mint must be positive")
    (enforce (<= min-mint max-issued) "min-mint cannot exceed max-issued")
    (enforce (= (floor max-issued precision) max-issued) "max-issued violates the token precision")
    (enforce (= (floor min-mint precision) min-mint) "min-mint violates the token precision"))

  ;; --- token-policy hooks --------------------------------------------------------
  ;; Each hook first requires the ledger's matching -CALL capability (via the
  ;; manager's registered ledger modref), so it is unreachable outside the real
  ;; ledger lifecycle path — direct calls with fabricated token-info fail.

  (defun enforce-init:bool (token:object{token-info})
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::INIT-CALL (at 'id token) (at 'precision token) (at 'uri token))))
    ;; REQUIRED spec, typed read: absence or a partial object aborts (fail closed)
    (let ((spec:object{issuance-spec} (read-msg ISSUANCE-MSG-KEY)))
      (enforce-valid-spec (at 'precision token) (at 'max-issued spec) (at 'min-mint spec))
      (insert issuance (at 'id token)
        { 'max-issued: (at 'max-issued spec), 'min-mint: (at 'min-mint spec), 'issued: 0.0 })
      (emit-event (ISSUANCE (at 'id token) (at 'max-issued spec) (at 'min-mint spec))))
    true)

  ;; payout stance (ADR-NFT-011): this policy claims nothing from a sale
  (defun payout-bps:integer (token:object{token-info}) 0)

  (defun enforce-mint:bool (token:object{token-info} account:string guard:guard amount:decimal)
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::MINT-CALL (at 'id token) account amount)))
    ;; the print run lives where the token was born: a row materialised by a
    ;; relocation on another chain can never grow
    (enforce (is-origin-chain token) "mint only on the token's origin chain")
    (with-read issuance (at 'id token) { 'max-issued := mx, 'min-mint := mn, 'issued := is }
      (enforce (>= amount mn) "mint below the minimum mint amount")
      (let ((new-issued (+ is amount)))
        (enforce (<= new-issued mx) "print run exhausted (max-issued)")
        ;; cumulative: never decremented by burn or relocation
        (update issuance (at 'id token) { 'issued: new-issued })
        (emit-event (ISSUED (at 'id token) new-issued mx))))
    true)

  (defun enforce-burn:bool (token:object{token-info} account:string amount:decimal)
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::BURN-CALL (at 'id token) account amount)))
    true)

  (defun enforce-offer:bool (token:object{token-info} seller:string amount:decimal timeout:integer sale-id:string)
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::OFFER-CALL (at 'id token) seller amount timeout sale-id)))
    true)

  (defun enforce-withdraw:bool (token:object{token-info} seller:string amount:decimal timeout:integer sale-id:string)
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::WITHDRAW-CALL (at 'id token) seller amount timeout sale-id)))
    true)

  (defun enforce-buy:[object{payout}] (token:object{token-info} seller:string buyer:string buyer-guard:guard amount:decimal sale-id:string)
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::BUY-CALL (at 'id token) seller buyer amount sale-id)))
    [])

  (defun enforce-transfer:bool (token:object{token-info} sender:string guard:guard receiver:string amount:decimal)
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::TRANSFER-CALL (at 'id token) sender receiver amount)))
    true)

  ;; --- cross-chain passport (policy state travels with the token) ---------------
  (defun enforce-xchain-send:object (token:object{token-info} sender:string receiver:string receiver-guard:guard target-chain:string amount:decimal)
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::XCHAIN-SEND-CALL (at 'id token) sender receiver target-chain amount)))
    (read issuance (at 'id token)))

  (defun enforce-xchain-receive:bool (token:object{token-info} receiver:string receiver-guard:guard amount:decimal state:object)
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::XCHAIN-RECEIVE-CALL (at 'id token) receiver amount)))
    (let ((mx:decimal (at 'max-issued state))
          (mn:decimal (at 'min-mint state))
          (is:decimal (at 'issued state)))
      (enforce-valid-spec (at 'precision token) mx mn)
      (enforce (and (>= is 0.0) (<= is mx)) "malformed issuance passport")
      (with-default-read issuance (at 'id token)
        { 'max-issued: -1.0, 'min-mint: -1.0, 'issued: -1.0 }
        { 'max-issued := lmx, 'min-mint := lmn, 'issued := lis }
        (if (= lmx -1.0)
          ;; first arrival on this chain: bind the print run as it stood
          (insert issuance (at 'id token) { 'max-issued: mx, 'min-mint: mn, 'issued: is })
          (let ((_ (enforce (and (= lmx mx) (= lmn mn)) "issuance passport mismatch")))
            ;; the ORIGIN chain is authoritative for `issued`: it can only have
            ;; grown since this copy left, never shrunk; a non-origin chain just
            ;; refreshes its informational copy to the larger value
            (if (is-origin-chain token)
              (enforce (>= lis is) "issuance passport claims more issued than the origin chain")
              (if (> is lis) (update issuance (at 'id token) { 'issued: is }) true))))))
    true)

  ;; --- stances: this policy bounds HOW MANY, never WHO or WHAT -------------------
  (defun mint-decision:string (token:object{token-info}) (identity "abstain"))

  (defun uri-decision:string (token:object{token-info}) (identity "abstain"))
  (defun enforce-update-uri:bool (token:object{token-info} new-uri:string)
    (enforce false "this policy does not permit uri updates"))
)
