;; nft.non-fungible-policy — the strict 1/1 NFT shape.
;;
;; Enforces at init that the token has precision 0, and at mint that the
;; amount is exactly 1.0 and that the mint happens ONCE, EVER: the mint marker
;; is an `insert` (fails on a duplicate key), so even after a burn drops the
;; supply back to zero the token can never be re-minted. Burn must take the
;; whole token (amount 1.0), so supply is always exactly 0 or 1.
;;
;; Every hook requires the ledger's matching -CALL capability in scope, so no
;; hook is reachable outside the real ledger lifecycle path.

(namespace (read-string 'ns))

(module non-fungible-policy GOVERNANCE
  @doc "1/1 NFT shape policy for the nft framework: precision 0, supply \
       \exactly 1, minted once ever, burned whole."

  (implements token-policy)
  (use token-policy [token-info payout])

  (defconst ADMIN-KS:string (read-string 'admin-ks)
    @doc "Admin keyset name, captured ONCE at deploy — never read from a \
         \caller's payload at enforcement time.")

  (defcap GOVERNANCE ()
    (enforce-keyset ADMIN-KS))

  (defschema minted-schema
    @doc "One-way mint marker: the insert is the once-ever gate (a burned \
         \token cannot be re-minted)."
    minted:bool)
  (deftable minted-table:{minted-schema})

  ;; --- views -------------------------------------------------------------------
  (defun is-minted:bool (token-id:string)
    (with-default-read minted-table token-id { 'minted: false } { 'minted := m } m))

  ;; --- token-policy hooks --------------------------------------------------------
  ;; Each hook first requires the ledger's matching -CALL capability (via the
  ;; manager's registered ledger modref), so it is unreachable outside the real
  ;; ledger lifecycle path — direct calls with fabricated token-info fail.

  (defun enforce-init:bool (token:object{token-info})
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::INIT-CALL (at 'id token) (at 'precision token) (at 'uri token))))
    (enforce (= 0 (at 'precision token)) "a 1/1 NFT requires precision 0")
    true)

  (defun enforce-mint:bool (token:object{token-info} account:string guard:guard amount:decimal)
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::MINT-CALL (at 'id token) account amount)))
    (enforce (= amount 1.0) "a 1/1 NFT mints exactly 1.0")
    (enforce (= (at 'supply token) 0.0) "a 1/1 NFT is already minted")
    ;; the once-EVER gate: insert fails on a duplicate, so a burned token
    ;; (supply back to 0) still cannot be re-minted
    (insert minted-table (at 'id token) { 'minted: true })
    true)

  (defun enforce-burn:bool (token:object{token-info} account:string amount:decimal)
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::BURN-CALL (at 'id token) account amount)))
    (enforce (= amount 1.0) "a 1/1 NFT burns whole (amount 1.0)")
    true)

  (defun enforce-offer:bool (token:object{token-info} seller:string amount:decimal timeout:integer sale-id:string)
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::OFFER-CALL (at 'id token) seller amount timeout sale-id)))
    (enforce (= amount 1.0) "a 1/1 NFT sells whole (amount 1.0)")
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
    (enforce (= amount 1.0) "a 1/1 NFT relocates whole (amount 1.0)")
    { 'minted: true })

  (defun enforce-xchain-receive:bool (token:object{token-info} receiver:string receiver-guard:guard amount:decimal state:object)
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::XCHAIN-RECEIVE-CALL (at 'id token) receiver amount)))
    (enforce (= amount 1.0) "a 1/1 NFT relocates whole (amount 1.0)")
    (enforce (= true (at 'minted state)) "malformed 1/1 passport")
    ;; carry the once-EVER marker: on first arrival bind it (blocks any mint
    ;; here); a returning token already has it
    (with-default-read minted-table (at 'id token) { 'minted: false } { 'minted := m }
      (if m true (insert minted-table (at 'id token) { 'minted: true })))
    true)

)
