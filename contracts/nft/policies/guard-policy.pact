;; nft.guard-policy — per-operation guards, FAIL CLOSED.
;;
;; The four operation guards (mint, burn, sale, transfer) are ALL REQUIRED in
;; the create-token transaction — a missing guard ABORTS creation instead of
;; silently becoming "anyone can, forever" (the POL-1 fix). Each lifecycle hook
;; then enforces its matching stored guard:
;;
;;   mint-guard     — who may mint (the ledger's mint has no owner yet;
;;                    without a policy gate, minting is open);
;;   burn-guard     — who may authorize burns, IN ADDITION to the ledger's own
;;                    owner-guard (DEBIT) check;
;;   sale-guard     — who may LIST the token for sale (checked at offer; the
;;                    buyer is deliberately not gated — a buyer cannot carry
;;                    the seller-side guard);
;;   transfer-guard — who may authorize free transfers, in addition to the
;;                    ledger's owner-guard check.
;;
;; The guards bind once at creation and are immutable after. Every hook
;; requires the ledger's matching -CALL capability in scope, so no hook is
;; reachable outside the real ledger lifecycle path.

(namespace (read-string 'ns))

(module guard-policy GOVERNANCE
  @doc "Fail-closed per-operation guard policy for the nft framework: all \
       \four operation guards are required at create, enforced per hook."

  (implements token-policy)
  (use token-policy [token-info payout])

  (defconst ADMIN-KS:string (read-string 'admin-ks)
    @doc "Admin keyset name, captured ONCE at deploy — never read from a \
         \caller's payload at enforcement time.")

  (defcap GOVERNANCE ()
    (enforce-keyset ADMIN-KS))

  (defconst GUARDS-MSG-KEY:string "operation_guards"
    @doc "Create-token-tx payload key carrying the four operation guards. \
         \ALL fields are required — a partial object aborts creation.")

  (defschema operation-guards-spec
    @doc "The create-token-tx payload shape: ALL four guards, no defaults."
    mint-guard:guard
    burn-guard:guard
    sale-guard:guard
    transfer-guard:guard)

  (defschema operation-guards
    @doc "The per-operation guards, bound once at token creation. token-id \
         \mirrors the row key (\"\" is the never-stored sentinel used by the \
         \cross-chain receive to detect absence)."
    token-id:string
    mint-guard:guard
    burn-guard:guard
    sale-guard:guard
    transfer-guard:guard)
  (deftable op-guards:{operation-guards})

  (defcap GUARDS:bool (token-id:string)
    @doc "Emitted once, when the operation guards bind at token creation."
    @event true)

  ;; --- views -------------------------------------------------------------------
  (defun get-guards:object{operation-guards} (token-id:string)
    (read op-guards token-id))

  ;; --- token-policy hooks --------------------------------------------------------
  ;; Each hook first requires the ledger's matching -CALL capability (via the
  ;; manager's registered ledger modref), so it is unreachable outside the real
  ;; ledger lifecycle path — direct calls with fabricated token-info fail.

  (defun enforce-init:bool (token:object{token-info})
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::INIT-CALL (at 'id token) (at 'precision token) (at 'uri token))))
    ;; ALL four guards are REQUIRED (typed read: absent or partial -> abort,
    ;; fail closed — a missing guard never defaults to "anyone can")
    (let ((gs:object{operation-guards-spec} (read-msg GUARDS-MSG-KEY)))
      (insert op-guards (at 'id token)
        { 'token-id: (at 'id token)
        , 'mint-guard: (at 'mint-guard gs), 'burn-guard: (at 'burn-guard gs)
        , 'sale-guard: (at 'sale-guard gs), 'transfer-guard: (at 'transfer-guard gs) })
      (emit-event (GUARDS (at 'id token))))
    true)

  (defun enforce-mint:bool (token:object{token-info} account:string guard:guard amount:decimal)
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::MINT-CALL (at 'id token) account amount)))
    (with-read op-guards (at 'id token) { 'mint-guard := g }
      (enforce-guard g))
    true)

  (defun enforce-burn:bool (token:object{token-info} account:string amount:decimal)
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::BURN-CALL (at 'id token) account amount)))
    (with-read op-guards (at 'id token) { 'burn-guard := g }
      (enforce-guard g))
    true)

  (defun enforce-offer:bool (token:object{token-info} seller:string amount:decimal timeout:integer sale-id:string)
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::OFFER-CALL (at 'id token) seller amount timeout sale-id)))
    (with-read op-guards (at 'id token) { 'sale-guard := g }
      (enforce-guard g))
    true)

  (defun enforce-withdraw:bool (token:object{token-info} seller:string amount:decimal timeout:integer sale-id:string)
    ;; the ledger's WITHDRAW cap already enforces the seller's own account
    ;; guard (or offer expiry); gating withdrawal behind the sale-guard would
    ;; let the guard holder hold the seller's escrowed token hostage
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::WITHDRAW-CALL (at 'id token) seller amount timeout sale-id)))
    true)

  (defun enforce-buy:[object{payout}] (token:object{token-info} seller:string buyer:string buyer-guard:guard amount:decimal sale-id:string)
    ;; the sale was authorized by the sale-guard at OFFER; the buyer side is
    ;; deliberately not gated (a buyer cannot carry the seller-side guard)
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::BUY-CALL (at 'id token) seller buyer amount sale-id)))
    [])

  (defun enforce-transfer:bool (token:object{token-info} sender:string guard:guard receiver:string amount:decimal)
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::TRANSFER-CALL (at 'id token) sender receiver amount)))
    (with-read op-guards (at 'id token) { 'transfer-guard := g }
      (enforce-guard g))
    true)
  ;; --- cross-chain passport (policy state travels with the token) ---------------
  (defun enforce-xchain-send:object (token:object{token-info} sender:string receiver:string receiver-guard:guard target-chain:string amount:decimal)
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::XCHAIN-SEND-CALL (at 'id token) sender receiver target-chain amount)))
    (read op-guards (at 'id token)))

  (defun enforce-xchain-receive:bool (token:object{token-info} receiver:string receiver-guard:guard amount:decimal state:object)
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::XCHAIN-RECEIVE-CALL (at 'id token) receiver amount)))
    (let ((gs:object{operation-guards}
            { 'token-id: (at 'id token)
            , 'mint-guard: (at 'mint-guard state), 'burn-guard: (at 'burn-guard state)
            , 'sale-guard: (at 'sale-guard state), 'transfer-guard: (at 'transfer-guard state) }))
      (with-default-read op-guards (at 'id token) { 'token-id: "" } { 'token-id := existing }
        (if (= "" existing)
          (insert op-guards (at 'id token) gs)
          ;; a RETURNING token: the immutable guard set must be identical
          (let ((local (read op-guards (at 'id token))))
            (enforce (= local gs) "operation-guards passport mismatch")))))
    true)

  ;; --- uri stance: this policy has no uri concern (abstain) --------------------
  (defun uri-decision:string (token:object{token-info}) (identity "abstain"))
  (defun enforce-update-uri:bool (token:object{token-info} new-uri:string)
    (enforce false "this policy does not permit uri updates"))
)
