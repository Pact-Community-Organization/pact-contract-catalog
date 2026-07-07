;; nft.non-updatable-uri-policy — the immutable-metadata marker.
;;
;; A token's uri is only updatable if its policy set includes a policy
;; implementing `updatable-uri-policy` that PERMITS the update. This policy
;; implements that interface with an unconditional REJECT, so attaching it
;; VETOES uri updates no matter what other policies are stacked on the token
;; — every policy must pass, so one veto is final. Attach it to make "this
;; metadata can never change" an on-chain guarantee rather than a convention.
;;
;; All token-policy lifecycle hooks are permissive; each still requires the
;; ledger's matching -CALL capability in scope, so no hook is reachable
;; outside the real ledger lifecycle path (a direct caller could otherwise
;; mistake the permissive `true` for an authorization).

(namespace (read-string 'ns))

(module non-updatable-uri-policy GOVERNANCE
  @doc "Immutable-metadata marker for the nft framework: permits the whole \
       \token lifecycle, vetoes every uri update."

  (implements token-policy)
  (implements updatable-uri-policy)
  (use token-policy [token-info payout])

  (defconst ADMIN-KS:string (read-string 'admin-ks)
    @doc "Admin keyset name, captured ONCE at deploy — never read from a \
         \caller's payload at enforcement time.")

  (defcap GOVERNANCE ()
    (enforce-keyset ADMIN-KS))

  ;; --- updatable-uri-policy: the unconditional veto ------------------------------
  (defun enforce-update-uri:bool (token:object{token-info} new-uri:string)
    (enforce false "the token uri is immutable"))

  ;; --- token-policy hooks (permissive, -CALL gated) -------------------------------
  (defun enforce-init:bool (token:object{token-info})
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::INIT-CALL (at 'id token) (at 'precision token) (at 'uri token))))
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
    ;; stateless marker: the veto is the module itself, not per-token state
    {})

  (defun enforce-xchain-receive:bool (token:object{token-info} receiver:string receiver-guard:guard amount:decimal state:object)
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::XCHAIN-RECEIVE-CALL (at 'id token) receiver amount)))
    true)

)
