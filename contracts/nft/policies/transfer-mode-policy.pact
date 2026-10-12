;; nft.transfer-mode-policy — how a token may change hands, fixed at creation.
;;
;; ADR-NFT-007. One creation-time, immutable, per-type setting with three values:
;;   * "free"      — transfer, gift, sale and relocation to anyone;
;;   * "sale-only" — ownership changes ONLY through the ledger's sale defpact
;;                   (every change of hands settles and pays whatever the
;;                   attached payout policies declare); a relocation may only
;;                   go owner -> same owner;
;;   * "bound"     — the soul-bound shape: no transfer, no sale; relocation only
;;                   owner -> same owner; the OWNER may still burn it.
;; The mode used to live inside royalty-policy as a flag, which tied a trading
;; rule to a payout rule and left a token without a royalty no way to be
;; sale-only. It is its own policy now: one source of truth, readable from the
;; attached policy set (hence from the token id) and from an event.
;;
;; Every hook requires the ledger's matching -CALL capability in scope, so no
;; hook is reachable outside the real ledger lifecycle path.

(namespace (read-string 'ns))

(module transfer-mode-policy GOVERNANCE
  @doc "Trading mode for the nft framework: free, sale-only or bound, chosen \
       \once at creation and travelling with the token."

  (implements token-policy)
  (use token-policy [token-info payout])

  (defconst ADMIN-KS:string (read-string 'admin-ks)
    @doc "Admin keyset name, captured ONCE at deploy — never read from a \
         \caller's payload at enforcement time.")

  (defcap GOVERNANCE ()
    (enforce-keyset ADMIN-KS))

  (defconst MODE-MSG-KEY:string "transfer_mode"
    @doc "Creation payload key: one of MODES. Required (fail closed).")
  (defconst MODE-FREE:string "free")
  (defconst MODE-SALE-ONLY:string "sale-only")
  (defconst MODE-BOUND:string "bound")
  (defconst MODES:[string] [MODE-FREE MODE-SALE-ONLY MODE-BOUND])

  (defschema mode-row
    mode:string)
  (deftable modes:{mode-row})

  (defcap TRANSFER-MODE:bool (token-id:string mode:string)
    @doc "Emitted once, when the mode binds at token creation (and on first \
         \arrival on another chain)."
    @event true)

  ;; --- views -------------------------------------------------------------------
  (defun get-mode:string (token-id:string)
    (at 'mode (read modes token-id)))

  (defun enforce-valid-mode:bool (mode:string)
    (enforce (contains mode MODES)
      (format "transfer_mode must be one of {}" [MODES])))

  ;; --- token-policy hooks --------------------------------------------------------
  ;; Each hook first requires the ledger's matching -CALL capability (via the
  ;; manager's registered ledger modref), so it is unreachable outside the real
  ;; ledger lifecycle path — direct calls with fabricated token-info fail.

  (defun enforce-init:bool (token:object{token-info})
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::INIT-CALL (at 'id token) (at 'precision token) (at 'uri token))))
    ;; REQUIRED mode: a missing key aborts creation (fail closed)
    (let ((mode:string (read-string MODE-MSG-KEY)))
      (enforce-valid-mode mode)
      (insert modes (at 'id token) { 'mode: mode })
      (emit-event (TRANSFER-MODE (at 'id token) mode)))
    true)

  (defun enforce-mint:bool (token:object{token-info} account:string guard:guard amount:decimal)
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::MINT-CALL (at 'id token) account amount)))
    true)

  (defun enforce-burn:bool (token:object{token-info} account:string amount:decimal)
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::BURN-CALL (at 'id token) account amount)))
    ;; the owner may always destroy what they own (the ledger's DEBIT proves
    ;; ownership); a bound token is bound to its owner, not to existence
    true)

  (defun enforce-offer:bool (token:object{token-info} seller:string amount:decimal timeout:integer sale-id:string)
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::OFFER-CALL (at 'id token) seller amount timeout sale-id)))
    (with-read modes (at 'id token) { 'mode := mode }
      (enforce (!= mode MODE-BOUND) "bound token: cannot be offered for sale"))
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
    (with-read modes (at 'id token) { 'mode := mode }
      (enforce (!= mode MODE-SALE-ONLY)
        "sale-only token: free transfer is disabled — sell via the sale pact")
      (enforce (!= mode MODE-BOUND)
        "bound token: free transfer is disabled"))
    true)

  ;; --- cross-chain passport (policy state travels with the token) ---------------
  (defun enforce-xchain-send:object (token:object{token-info} sender:string receiver:string receiver-guard:guard target-chain:string amount:decimal)
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::XCHAIN-SEND-CALL (at 'id token) sender receiver target-chain amount)))
    (with-read modes (at 'id token) { 'mode := mode }
      ;; a relocation that changes the owner is a free transfer in two hops.
      ;; This reads the account NAME and means the OWNER; the inference is sound
      ;; only because ledger.enforce-account-principal (applied to the receiver
      ;; at the head of the send) accepts no name that is not the immutable
      ;; principal of its guard (k:/w:/c:) — see royalty-policy's history of
      ;; this rule and redteam L6/L7.
      (if (= mode MODE-FREE)
        true
        (enforce (= sender receiver)
          (format "{} token: cross-chain relocation only to the same owner" [mode])))
      { 'mode: mode }))

  (defun enforce-xchain-receive:bool (token:object{token-info} receiver:string receiver-guard:guard amount:decimal state:object)
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::XCHAIN-RECEIVE-CALL (at 'id token) receiver amount)))
    (let ((mode:string (at 'mode state)))
      (enforce-valid-mode mode)
      (with-default-read modes (at 'id token) { 'mode: "" } { 'mode := existing }
        (if (= "" existing)
          (let ((_ (insert modes (at 'id token) { 'mode: mode })))
            (emit-event (TRANSFER-MODE (at 'id token) mode)))
          ;; a RETURNING token: the immutable mode must be identical
          (enforce (= existing mode) "transfer-mode passport mismatch"))))
    true)

  ;; --- stances: this policy decides HOW a token changes hands, nothing else -----
  (defun mint-decision:string (token:object{token-info}) (identity "abstain"))

  (defun uri-decision:string (token:object{token-info}) (identity "abstain"))
  (defun enforce-update-uri:bool (token:object{token-info} new-uri:string)
    (enforce false "this policy does not permit uri updates"))
)
