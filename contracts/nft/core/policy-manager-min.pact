;; nft.policy-manager (Phase 1 — dispatcher with the ledger handshake)
;;
;; The ledger routes every lifecycle mutation through policy-manager.enforce-*,
;; and this manager verifies MID-CALL that the registered ledger's matching
;; -CALL capability is in scope (require-capability through the stored ledger
;; modref). That closes the fabricated-token-info hole: nobody can invoke a
;; policy hook directly with fake token data — the call must originate inside
;; the ledger's own lifecycle path.
;;
;; PHASE 2 UPGRADES THIS MODULE with the hardened settlement: one
;; conservation-asserted routine (escrow-in = Σ payouts), economics bound in
;; state at offer time (no read-msg of money at buy), no shared-escrow policy
;; sweep. Until then offer/buy/withdraw reject.

(namespace (read-string 'ns))

(module policy-manager GOVERNANCE
  @doc "Policy dispatcher for the nft framework: maps enforce-* hooks over each \
       \token policy, gated by the registered ledger's -CALL handshake."

  (use token-policy [token-info])

  (defconst ADMIN-KS:string (read-string 'admin-ks)
    @doc "Admin keyset name, captured ONCE at deploy — never read from a \
         \caller's payload at enforcement time.")

  (defcap GOVERNANCE ()
    (enforce-keyset ADMIN-KS))

  ;; --- the registered ledger (set once at init) -------------------------------
  (defschema ledger-ref
    ledger:module{ledger-iface})
  (deftable ledgers:{ledger-ref})
  (defconst LEDGER-KEY:string "l")

  (defun init:bool (ledger:module{ledger-iface})
    @doc "One-time registration of the ledger this manager serves (insert fails \
         \on a second call). Governance-gated."
    (with-capability (GOVERNANCE)
      (insert ledgers LEDGER-KEY { 'ledger: ledger }))
    true)

  (defun retrieve-ledger:module{ledger-iface} ()
    (at 'ledger (read ledgers LEDGER-KEY)))

  ;; --- hooks (each verifies the ledger handshake, then dispatches) -------------
  (defun enforce-init:bool (token:object{token-info})
    (let ((l:module{ledger-iface} (retrieve-ledger)))
      (require-capability (l::INIT-CALL (at 'id token) (at 'precision token) (at 'uri token))))
    (map (lambda (p:module{token-policy}) (p::enforce-init token)) (at 'policies token))
    true)

  (defun enforce-mint:bool (token:object{token-info} account:string guard:guard amount:decimal)
    (let ((l:module{ledger-iface} (retrieve-ledger)))
      (require-capability (l::MINT-CALL (at 'id token) account amount)))
    (map (lambda (p:module{token-policy}) (p::enforce-mint token account guard amount)) (at 'policies token))
    true)

  (defun enforce-burn:bool (token:object{token-info} account:string amount:decimal)
    (let ((l:module{ledger-iface} (retrieve-ledger)))
      (require-capability (l::BURN-CALL (at 'id token) account amount)))
    (map (lambda (p:module{token-policy}) (p::enforce-burn token account amount)) (at 'policies token))
    true)

  (defun enforce-transfer:bool (token:object{token-info} sender:string guard:guard receiver:string amount:decimal)
    (let ((l:module{ledger-iface} (retrieve-ledger)))
      (require-capability (l::TRANSFER-CALL (at 'id token) sender receiver amount)))
    (map (lambda (p:module{token-policy}) (p::enforce-transfer token sender guard receiver amount)) (at 'policies token))
    true)

  ;; --- settlement hooks: delivered by the Phase-2 hardened manager -------------
  (defun enforce-offer:bool (token:object{token-info} seller:string amount:decimal timeout:integer sale-id:string)
    (enforce false "offer/buy settlement is delivered in Phase 2 (hardened manager)"))

  (defun enforce-buy:bool (token:object{token-info} seller:string buyer:string buyer-guard:guard amount:decimal sale-id:string)
    (enforce false "offer/buy settlement is delivered in Phase 2 (hardened manager)"))

  (defun enforce-withdraw:bool (token:object{token-info} seller:string amount:decimal timeout:integer sale-id:string)
    (enforce false "offer/buy settlement is delivered in Phase 2 (hardened manager)"))
)
