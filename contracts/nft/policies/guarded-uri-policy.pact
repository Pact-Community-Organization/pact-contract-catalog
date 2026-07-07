;; nft.guarded-uri-policy — guard-authorized uri updates.
;;
;; The uri-update authority is REQUIRED in the create-token transaction and
;; bound into this policy's own state at init — fail closed: a missing guard
;; aborts creation, it never defaults to "anyone may update" or to "the
;; framework admin may update". At update time the manager routes the request
;; here (this policy registers itself as an updatable-uri handler) and the
;; stored guard authorizes it. Stack nft.non-updatable-uri-policy alongside
;; and its veto wins — every policy must pass.
;;
;; All token-policy lifecycle hooks are permissive; each still requires the
;; ledger's matching -CALL capability in scope, so no hook is reachable
;; outside the real ledger lifecycle path.

(namespace (read-string 'ns))

(module guarded-uri-policy GOVERNANCE
  @doc "Guard-gated uri updates for the nft framework: the update guard binds \
       \once at token creation; the manager's update-uri routing enforces it."

  (implements token-policy)
  (implements updatable-uri-policy)
  (use token-policy [token-info payout])

  (defconst ADMIN-KS:string (read-string 'admin-ks)
    @doc "Admin keyset name, captured ONCE at deploy — never read from a \
         \caller's payload at enforcement time.")

  (defcap GOVERNANCE ()
    (enforce-keyset ADMIN-KS))

  (defconst URI-GUARD-MSG-KEY:string "uri_guard"
    @doc "Create-token-tx payload key carrying the uri-update guard. REQUIRED \
         \for any token carrying this policy — fail closed.")

  (defschema uri-guard-schema
    @doc "Who may update the token's uri, bound once at token creation. \
         \token-id mirrors the row key (\"\" = the never-stored sentinel the \
         \cross-chain receive uses to detect absence)."
    token-id:string
    guard:guard)
  (deftable uri-guards:{uri-guard-schema})

  (defcap URI-GUARD:bool (token-id:string)
    @doc "Emitted once, when the uri-update guard binds at token creation."
    @event true)

  ;; --- views -------------------------------------------------------------------
  (defun get-uri-guard:guard (token-id:string)
    (at 'guard (read uri-guards token-id)))

  ;; --- updatable-uri-policy: the guard decides ----------------------------------
  (defun enforce-update-uri:bool (token:object{token-info} new-uri:string)
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::UPDATE-URI-CALL (at 'id token) new-uri)))
    (with-read uri-guards (at 'id token) { 'guard := g }
      (enforce-guard g))
    true)

  ;; --- token-policy hooks (permissive, -CALL gated) -------------------------------
  (defun enforce-init:bool (token:object{token-info})
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::INIT-CALL (at 'id token) (at 'precision token) (at 'uri token))))
    ;; the guard is REQUIRED (typed read: absent -> abort, fail closed)
    (let ((g:guard (read-msg URI-GUARD-MSG-KEY)))
      (insert uri-guards (at 'id token) { 'token-id: (at 'id token), 'guard: g })
      (emit-event (URI-GUARD (at 'id token))))
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
    { 'guard: (get-uri-guard (at 'id token)) })

  (defun enforce-xchain-receive:bool (token:object{token-info} receiver:string receiver-guard:guard amount:decimal state:object)
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::XCHAIN-RECEIVE-CALL (at 'id token) receiver amount)))
    (let ((g:guard (at 'guard state)))
      (with-default-read uri-guards (at 'id token) { 'token-id: "" } { 'token-id := existing }
        (if (= "" existing)
          (insert uri-guards (at 'id token) { 'token-id: (at 'id token), 'guard: g })
          ;; a RETURNING token: the immutable uri guard must be identical
          (enforce (= g (get-uri-guard (at 'id token))) "uri-guard passport mismatch"))))
    true)

)
