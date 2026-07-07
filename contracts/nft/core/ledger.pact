;; nft.ledger — the shared NFT ledger: the single source of truth for token
;; identity, ownership balances, and supply, for the PCO `nft` framework.
;;
;; IDENTITY (the part of the Marmalade architecture that is correct, kept
;; verbatim in behavior): a token id is `n:{hash([token-details, chain-id,
;; creation-guard])}` — DERIVED from the creator's creation-guard. `create-token`
;; re-derives the id and enforces equality (enforce-token-reserved), and inserts
;; the token row (insert fails on a duplicate id). Therefore:
;;   * FORGERY is impossible — you cannot create a token with a given id unless
;;     you control the creation-guard that hashes to it (CREATE-TOKEN enforces
;;     that guard), and a fabricated id fails the protocol re-derivation.
;;   * DOUBLE-MINT is impossible — one id, one row, forever.
;; This is the anchor a self-sovereign per-NFT module could never provide.
;;
;; Lifecycle mutations route through nft.policy-manager.enforce-* (the extension
;; point where royalty/guard/sale-only policies run), secured by the -CALL
;; capability handshake: the manager verifies mid-call that the matching -CALL
;; cap is in scope, proving the call originated in this ledger's lifecycle path.
;;
;; Phase 1 ships identity + accounting; offer/buy settlement is Phase 2 (the
;; hardened, conservation-asserted manager). Until then the sale defpact and the
;; manager's offer/buy hooks reject.

(namespace (read-string 'ns))

(module ledger GOVERNANCE
  @doc "The nft framework's shared poly-fungible token ledger + identity anchor."

  (implements ledger-iface)
  (implements poly-fungible)

  (use poly-fungible [account-details sender-balance-change receiver-balance-change])
  (use token-policy [token-info])

  (defconst ADMIN-KS:string (read-string 'admin-ks)
    @doc "Admin keyset name, captured ONCE at deploy from the deployer's tx — \
         \never read from a caller's payload at enforcement time.")

  (defcap GOVERNANCE ()
    (enforce-keyset ADMIN-KS))

  (defconst VERSION:integer 1)
  (defconst TOKEN-ID-PREFIX:string "n"
    @doc "Our token-id reserved protocol prefix (n:...).")
  (defconst URI-RESERVED-PREFIX:string "nft:"
    @doc "Reserved uri prefix nobody may self-assign.")

  ;; --- schemas / tables -----------------------------------------------------
  (deftable ledger-table:{account-details})

  (defschema token-schema
    id:string
    uri:string
    precision:integer
    supply:decimal
    policies:[module{token-policy}])
  (deftable tokens:{token-schema})

  (defschema token-details
    uri:string
    precision:integer
    policies:[module{token-policy}])

  ;; --- events -----------------------------------------------------------------
  (defcap TOKEN:bool (id:string precision:integer policies:[module{token-policy}] uri:string creation-guard:guard)
    @doc "Emitted once, when a token id is created."
    @event true)
  (defcap SUPPLY:bool (id:string supply:decimal)
    @doc "Emitted when the supply of ID changes."
    @event true)
  (defcap ACCOUNT_GUARD:bool (id:string account:string guard:guard)
    @doc "Emitted when an account guard is enrolled."
    @event true)
  (defcap RECONCILE:bool
    (token-id:string amount:decimal sender:object{sender-balance-change} receiver:object{receiver-balance-change})
    @doc "Accounting event: sender={\"\",0,0} for mint, receiver={\"\",0,0} for burn."
    @event true)
  (defcap SALE:bool (id:string seller:string amount:decimal timeout:integer sale-id:string)
    @doc "Wrapper cap/event for a sale of ID by SELLER until TIMEOUT. Composes \
         \the seller-authorized OFFER and the sale-private token."
    @event
    (enforce (> amount 0.0) "amount must be positive")
    (compose-capability (OFFER id seller amount timeout))
    (compose-capability (SALE_PRIVATE sale-id)))

  (defcap OFFER:bool (id:string seller:string amount:decimal timeout:integer)
    @doc "Seller offers AMOUNT of ID until TIMEOUT: escrows the NFT into the \
         \sale-account. One-shot managed (installed by the seller's signature)."
    @managed
    (enforce (sale-active timeout) "invalid or expired timeout at offer")
    (compose-capability (DEBIT id seller))
    (compose-capability (CREDIT id (sale-account))))

  (defcap WITHDRAW:bool (id:string seller:string amount:decimal timeout:integer sale-id:string)
    @doc "Return the escrowed NFT to SELLER (rollback of an unsold offer, or an \
         \expired one). One-shot managed."
    @managed
    (compose-capability (SALE_PRIVATE sale-id))
    (if (= 0 timeout)
      (enforce-guard (at 'guard (details id seller)))
      (enforce (not (sale-active timeout)) "offer still active — cannot withdraw"))
    (compose-capability (DEBIT id (sale-account)))
    (compose-capability (CREDIT id seller)))

  (defcap BUY:bool (id:string seller:string buyer:string amount:decimal sale-id:string)
    @doc "Complete the sale: move the escrowed NFT to BUYER. One-shot managed."
    @managed
    (compose-capability (SALE_PRIVATE sale-id))
    (compose-capability (DEBIT id (sale-account)))
    (compose-capability (CREDIT id buyer)))

  (defcap SALE_PRIVATE:bool (sale-id:string)
    @doc "Guards the sale-account escrow: satisfied only inside the sale defpact."
    true)

  ;; --- auth caps --------------------------------------------------------------
  (defcap CREATE-TOKEN:bool (id:string creation-guard:guard)
    @doc "The creator proves control of the CREATION-GUARD the token id is \
         \derived from — the anti-forgery signature check."
    (enforce-guard creation-guard))

  (defcap TRANSFER:bool (id:string sender:string receiver:string amount:decimal)
    @managed amount TRANSFER-mgr
    (enforce (!= sender receiver) "same sender and receiver")
    (enforce-unit id amount)
    (enforce (> amount 0.0) "positive amount")
    (compose-capability (DEBIT id sender))
    (compose-capability (CREDIT id receiver)))

  (defun TRANSFER-mgr:decimal (managed:decimal requested:decimal)
    (let ((newbal (- managed requested)))
      (enforce (>= newbal 0.0) (format "TRANSFER exceeded for balance {}" [managed]))
      newbal))

  (defcap XTRANSFER:bool (id:string sender:string receiver:string target-chain:string amount:decimal)
    @managed amount TRANSFER-mgr
    (enforce false "cross-chain transfer not supported by this ledger"))

  (defcap DEBIT:bool (id:string sender:string)
    @doc "Debit authority: the sender's account guard (bound in arg position — \
         \node-safe read)."
    (enforce-guard (account-guard id sender)))

  (defcap CREDIT:bool (id:string receiver:string)
    @doc "Internal credit token. Weak body by design: only composed into \
         \TRANSFER/MINT, never acquired externally."
    true)

  (defcap UPDATE_SUPPLY:bool ()
    @doc "Internal supply-update token. Weak body by design: only composed into \
         \MINT/BURN, never acquired externally."
    true)

  (defcap MINT:bool (id:string account:string amount:decimal)
    @doc "Mint scope: composes CREDIT + UPDATE_SUPPLY. Mint AUTHORIZATION is a \
         \policy concern (a token with no guard/mint policy is open — attach \
         \one; Phase 3 ships the concrete policy set)."
    (enforce (> amount 0.0) "positive amount")
    (compose-capability (CREDIT id account))
    (compose-capability (UPDATE_SUPPLY)))

  (defcap BURN:bool (id:string account:string amount:decimal)
    @doc "Burn scope: composes DEBIT (account-guard authorization) + UPDATE_SUPPLY."
    (enforce (> amount 0.0) "positive amount")
    (compose-capability (DEBIT id account))
    (compose-capability (UPDATE_SUPPLY)))

  ;; --- ledger-iface -CALL caps (the modref handshake with the manager) --------
  ;; Weak bodies by design: each is acquired ONLY by this ledger around the
  ;; matching policy-manager.enforce-* call; the manager require-capability's it
  ;; through its stored ledger modref, proving the call came from this ledger's
  ;; lifecycle path and not from an arbitrary caller with fabricated token-info.
  (defcap INIT-CALL:bool (id:string precision:integer uri:string)
    @doc "Scopes policy enforce-init dispatch to create-token." true)
  (defcap TRANSFER-CALL:bool (id:string sender:string receiver:string amount:decimal)
    @doc "Scopes policy enforce-transfer dispatch to transfer/transfer-create." true)
  (defcap MINT-CALL:bool (id:string account:string amount:decimal)
    @doc "Scopes policy enforce-mint dispatch to mint." true)
  (defcap BURN-CALL:bool (id:string account:string amount:decimal)
    @doc "Scopes policy enforce-burn dispatch to burn." true)
  (defcap OFFER-CALL:bool (id:string seller:string amount:decimal timeout:integer sale-id:string)
    @doc "Scopes policy enforce-offer dispatch to the sale defpact (Phase 2)." true)
  (defcap WITHDRAW-CALL:bool (id:string seller:string amount:decimal timeout:integer sale-id:string)
    @doc "Scopes policy enforce-withdraw dispatch to the sale defpact (Phase 2)." true)
  (defcap BUY-CALL:bool (id:string seller:string buyer:string amount:decimal sale-id:string)
    @doc "Scopes policy enforce-buy dispatch to the sale defpact (Phase 2)." true)
  (defcap UPDATE-URI-CALL:bool (id:string new-uri:string)
    @doc "Scopes policy enforce-update-uri dispatch (updatable-uri policies)." true)

  ;; --- key / view helpers -----------------------------------------------------
  (defun key:string (id:string account:string) (format "{}:{}" [id account]))

  (defun account-guard:guard (id:string account:string)
    (at 'guard (read ledger-table (key id account))))

  (defun get-balance:decimal (id:string account:string)
    (at 'balance (read ledger-table (key id account))))

  (defun details:object{account-details} (id:string account:string)
    (read ledger-table (key id account)))

  (defun precision:integer (id:string) (at 'precision (read tokens id)))
  (defun get-uri:string (id:string) (at 'uri (read tokens id)))
  (defun total-supply:decimal (id:string)
    (with-default-read tokens id { 'supply: 0.0 } { 'supply := s } s))
  (defun get-version:integer () VERSION)

  (defun enforce-unit:bool (id:string amount:decimal)
    (let ((p (precision id)))
      (enforce (= (floor amount p) amount) "precision violation")))

  (defun get-token-info:object{token-info} (id:string)
    (with-read tokens id { 'id := i, 'supply := s, 'precision := p, 'uri := u, 'policies := pol }
      { 'id: i, 'supply: s, 'precision: p, 'uri: u, 'policies: pol }))

  ;; --- IDENTITY (behavior kept verbatim from the correct Marmalade model) -----
  (defun create-token-id:string (details:object{token-details} creation-guard:guard)
    @doc "The token id is a hash of the token details + chain + CREATION-GUARD, \
         \so the id is derived from the creator's key — forgery-proof."
    (format "{}:{}" [TOKEN-ID-PREFIX
      (hash [(format "{}" [details]) (at 'chain-id (chain-data)) creation-guard])]))

  (defun check-reserved:string (token-id:string)
    (let ((pfx (take 2 token-id)))
      (if (= ":" (take -1 pfx)) (take 1 pfx) "")))

  (defun enforce-token-reserved:bool (token-id:string details:object{token-details} creation-guard:guard)
    @doc "The anti-forgery gate: the id MUST re-derive from the details + \
         \creation-guard."
    (let ((r (check-reserved token-id)))
      (if (= TOKEN-ID-PREFIX r)
        (enforce (= token-id (create-token-id details creation-guard)) "token protocol violation")
        (enforce false (format "unrecognized reserved protocol: {}" [r])))))

  (defun enforce-uri-reserved:bool (uri:string)
    (enforce (!= URI-RESERVED-PREFIX (take (length URI-RESERVED-PREFIX) uri))
      (format "reserved uri protocol: {}" [URI-RESERVED-PREFIX])))

  ;; --- create-token (anti-forgery / anti-double-mint entry) -------------------
  (defun create-token:bool
    ( id:string precision:integer uri:string
      policies:[module{token-policy}] creation-guard:guard )
    @doc "Create a token id. The id MUST re-derive from the details + \
         \CREATION-GUARD, the caller MUST satisfy that guard, and `insert` \
         \fails on a duplicate — one id, one token, exactly once."
    (enforce-uri-reserved uri)
    (let ((details:object{token-details} { 'uri: uri, 'precision: precision, 'policies: (sort policies) }))
      (enforce-token-reserved id details creation-guard))
    (with-capability (INIT-CALL id precision uri)
      (policy-manager.enforce-init
        { 'id: id, 'supply: 0.0, 'precision: precision, 'uri: uri, 'policies: policies }))
    (with-capability (CREATE-TOKEN id creation-guard)
      (insert tokens id { 'id: id, 'uri: uri, 'precision: precision, 'supply: 0.0, 'policies: policies })
      (emit-event (TOKEN id precision policies uri creation-guard))
      true))

  ;; --- accounts ----------------------------------------------------------------
  (defun create-account:bool (id:string account:string guard:guard)
    (util.enforce-valid-account account)
    (util.enforce-reserved account guard)
    ;; token must exist (a balance row for a non-token is meaningless)
    (precision id)
    (insert ledger-table (key id account)
      { 'id: id, 'account: account, 'balance: 0.0, 'guard: guard })
    (emit-event (ACCOUNT_GUARD id account guard))
    true)

  ;; --- mint / burn / transfer (routed through the manager handshake) ----------
  (defun mint:bool (id:string account:string guard:guard amount:decimal)
    (with-capability (MINT-CALL id account amount)
      (policy-manager.enforce-mint (get-token-info id) account guard amount))
    (with-capability (MINT id account amount)
      (let ((receiver (credit id account guard amount))
            (sender:object{sender-balance-change} { 'account: "", 'previous: 0.0, 'current: 0.0 }))
        (emit-event (RECONCILE id amount sender receiver))
        (update-supply id amount)))
    true)

  (defun burn:bool (id:string account:string amount:decimal)
    (with-capability (BURN-CALL id account amount)
      (policy-manager.enforce-burn (get-token-info id) account amount))
    (with-capability (BURN id account amount)
      (let ((sender (debit id account amount))
            (receiver:object{receiver-balance-change} { 'account: "", 'previous: 0.0, 'current: 0.0 }))
        (emit-event (RECONCILE id amount sender receiver))
        (update-supply id (- amount))))
    true)

  (defun transfer:bool (id:string sender:string receiver:string amount:decimal)
    (util.enforce-valid-transfer sender receiver (precision id) amount)
    (with-capability (TRANSFER-CALL id sender receiver amount)
      (policy-manager.enforce-transfer (get-token-info id) sender (account-guard id sender) receiver amount))
    (with-capability (TRANSFER id sender receiver amount)
      (with-read ledger-table (key id receiver) { 'guard := g }
        (let ((s (debit id sender amount)) (r (credit id receiver g amount)))
          (emit-event (RECONCILE id amount s r)))))
    true)

  (defun transfer-create:bool (id:string sender:string receiver:string receiver-guard:guard amount:decimal)
    (util.enforce-valid-transfer sender receiver (precision id) amount)
    (with-capability (TRANSFER-CALL id sender receiver amount)
      (policy-manager.enforce-transfer (get-token-info id) sender (account-guard id sender) receiver amount))
    (with-capability (TRANSFER id sender receiver amount)
      (let ((s (debit id sender amount)) (r (credit id receiver receiver-guard amount)))
        (emit-event (RECONCILE id amount s r))))
    true)

  (defpact transfer-crosschain:bool (id:string sender:string receiver:string receiver-guard:guard target-chain:string amount:decimal)
    (step (enforce false "cross-chain transfer not supported by this ledger")))

  ;; --- internal debit / credit / supply ----------------------------------------
  (defun debit:object{sender-balance-change} (id:string account:string amount:decimal)
    (require-capability (DEBIT id account))
    (enforce-unit id amount)
    (with-read ledger-table (key id account) { 'balance := bal }
      (enforce (<= amount bal) "insufficient funds")
      (let ((new-bal (- bal amount)))
        (update ledger-table (key id account) { 'balance: new-bal })
        { 'account: account, 'previous: bal, 'current: new-bal })))

  (defun credit:object{receiver-balance-change} (id:string account:string guard:guard amount:decimal)
    (require-capability (CREDIT id account))
    (enforce-unit id amount)
    (util.enforce-valid-account account)
    (util.enforce-reserved account guard)
    (with-default-read ledger-table (key id account)
      { 'balance: -1.0, 'guard: guard }
      { 'balance := bal, 'guard := existing }
      (let ((is-new (= bal -1.0)))
        (enforce (= existing guard) "account guard does not match")
        (let ((prev (if is-new 0.0 bal)) (new-bal (if is-new amount (+ bal amount))))
          (write ledger-table (key id account) { 'id: id, 'account: account, 'balance: new-bal, 'guard: guard })
          (if is-new (emit-event (ACCOUNT_GUARD id account guard)) true)
          { 'account: account, 'previous: prev, 'current: new-bal }))))

  (defun update-supply:bool (id:string amount:decimal)
    (require-capability (UPDATE_SUPPLY))
    (with-default-read tokens id { 'supply: 0.0 } { 'supply := s }
      (let ((new-s (+ s amount)))
        (update tokens id { 'supply: new-s })
        (emit-event (SUPPLY id new-s))
        true)))

  ;; --- sale defpact (offer -> buy, with withdraw rollback) --------------------
  ;; The NFT escrows into the sale-account (a capability-pact-guarded principal)
  ;; at offer, and moves to the buyer at buy. The FUNGIBLE settlement (payment +
  ;; the conservation-asserted split) is the hardened policy-manager's job — this
  ;; ledger only moves the token. Timeout is a unix-seconds deadline (0 = the
  ;; seller may withdraw anytime; otherwise withdrawal is only after expiry).

  (defpact sale:string (id:string seller:string amount:decimal timeout:integer)
    (step-with-rollback
      ;; step 0: offer — run policy enforce-offer, then escrow the NFT
      (let ((token-info (get-token-info id)))
        (with-capability (OFFER-CALL id seller amount timeout (pact-id))
          (policy-manager.enforce-offer token-info seller amount timeout (pact-id)))
        (with-capability (SALE id seller amount timeout (pact-id))
          (offer id seller amount))
        (pact-id))
      ;; step 0 rollback: withdraw — run policy enforce-withdraw, return the NFT
      (let ((token-info (get-token-info id)))
        (with-capability (WITHDRAW-CALL id seller amount timeout (pact-id))
          (policy-manager.enforce-withdraw token-info seller amount timeout (pact-id)))
        (with-capability (WITHDRAW id seller amount timeout (pact-id))
          (withdraw id seller amount))
        (pact-id)))
    (step
      ;; step 1: buy — the buyer + guard come from the buy continuation payload
      (let ( (buyer:string (read-msg "buyer"))
             (buyer-guard:guard (read-msg "buyer-guard")) )
        (with-capability (BUY-CALL id seller buyer amount (pact-id))
          (policy-manager.enforce-buy (get-token-info id) seller buyer buyer-guard amount (pact-id)))
        (with-capability (BUY id seller buyer amount (pact-id))
          (buy id seller buyer buyer-guard amount))
        (pact-id))))

  (defun offer:bool (id:string seller:string amount:decimal)
    @doc "Escrow AMOUNT of the NFT from SELLER into the sale-account."
    (require-capability (SALE_PRIVATE (pact-id)))
    (let ((sender (debit id seller amount))
          (receiver (credit id (sale-account) (create-capability-pact-guard (SALE_PRIVATE (pact-id))) amount)))
      (emit-event (TRANSFER id seller (sale-account) amount))
      (emit-event (RECONCILE id amount sender receiver)))
    true)

  (defun withdraw:bool (id:string seller:string amount:decimal)
    @doc "Return the escrowed NFT to SELLER."
    (require-capability (SALE_PRIVATE (pact-id)))
    (let ((sender (debit id (sale-account) amount))
          (receiver (credit-account id seller amount)))
      (emit-event (TRANSFER id (sale-account) seller amount))
      (emit-event (RECONCILE id amount sender receiver)))
    true)

  (defun buy:bool (id:string seller:string buyer:string buyer-guard:guard amount:decimal)
    @doc "Move the escrowed NFT to BUYER (fungible settlement is the manager's)."
    (require-capability (SALE_PRIVATE (pact-id)))
    (let ((sender (debit id (sale-account) amount))
          (receiver (credit id buyer buyer-guard amount)))
      (emit-event (TRANSFER id (sale-account) buyer amount))
      (emit-event (RECONCILE id amount sender receiver)))
    true)

  (defun credit-account:object{receiver-balance-change} (id:string account:string amount:decimal)
    @doc "Credit AMOUNT to an EXISTING account using its stored guard (used by \
         \withdraw to return the NFT to the seller's account)."
    (require-capability (CREDIT id account))
    (credit id account (account-guard id account) amount))

  (defun sale-active:bool (timeout:integer)
    @doc "A sale is active until TIMEOUT (unix seconds; 0 = always active)."
    (if (= 0 timeout)
      true
      (< (at 'block-time (chain-data)) (add-time (time "1970-01-01T00:00:00Z") timeout))))

  (defun sale-account:string ()
    @doc "The per-sale NFT escrow principal (guarded by SALE_PRIVATE of this pact)."
    (create-principal (create-capability-pact-guard (SALE_PRIVATE (pact-id)))))
)
