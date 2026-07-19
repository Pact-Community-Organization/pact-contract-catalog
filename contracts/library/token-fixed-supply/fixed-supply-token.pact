(module fixed-supply-token GOV

  @doc "PCO library template: a FIXED-SUPPLY, NON-UPGRADEABLE fungible-v2     \
  \token. The entire supply is minted exactly once at initialization and can  \
  \only ever decrease afterwards (holders may burn their own tokens). There   \
  \is no owner, no admin function, and no upgrade path: what you deploy is    \
  \the token, forever. That immutability is the product - holders never have  \
  \to trust an operator not to mint, freeze, or rewrite the rules.           \
  \                                                                          \
  \Deploy-time parameterization (transaction data, baked into constants):     \
  \  symbol        - display symbol                                          \
  \  precision     - decimal precision, 0..12                                \
  \  total-supply  - the fixed supply, positive, at 'precision' units        \
  \  token-minter  - keyset authorized to call init-mint EXACTLY ONCE        \
  \                                                                          \
  \Deployment checklist (see README.md):                                     \
  \  1. Rename the module and wrap it in your namespace.                     \
  \  2. Deploy WITH the parameters above in the same transaction - the      \
  \     (create-table ...) calls at the end of this file MUST stay in the    \
  \     deploy transaction: governance is frozen, so tables can never be     \
  \     created afterwards.                                                  \
  \  3. Call init-mint with the full distribution; a second call is          \
  \     impossible by construction.                                          \
  \  4. Run the co-located REPL suite, then validate on devnet before any    \
  \     production deployment.                                               \
  \                                                                          \
  \This token is SINGLE-CHAIN by design: transfer-crosschain is disabled.    \
  \A frozen module cannot coordinate upgrades across chains, so honest       \
  \cross-chain support would require a different (governed) template."

  (implements fungible-v2)

  ;; -----------------------------
  ;; Governance: frozen forever
  ;; -----------------------------

  (defcap GOV ()
    @doc "Deliberately unsatisfiable: the deployed module is non-upgradeable."
    (enforce false "frozen: this token is non-upgradeable"))

  ;; -----------------------------
  ;; Deploy-time constants
  ;; -----------------------------

  (defconst SYMBOL (read-string 'symbol)
    "Display symbol, fixed at deploy.")

  (defconst PRECISION:integer
    (let ((p (read-integer 'precision)))
      (enforce (and (>= p 0) (<= p 12)) "precision must be in 0..12")
      p)
    "Decimal precision, fixed at deploy (12 matches coin).")

  (defconst TOTAL-SUPPLY:decimal
    (let ((s (read-decimal 'total-supply)))
      (enforce (> s 0.0) "total-supply must be positive")
      (enforce (= (floor s PRECISION) s) "total-supply must respect precision")
      s)
    "The fixed supply: minted exactly once, only ever decreased by burns.")

  (defconst MINT-GUARD:guard (read-keyset 'token-minter)
    "The keyset allowed to perform the ONE initial mint. Powerless afterwards.")

  (defconst MINIMUM_ACCOUNT_LENGTH 3
    "Minimum account name length")

  (defconst MAXIMUM_ACCOUNT_LENGTH 256
    "Maximum account name length")

  (defconst SUPPLY-KEY "supply")

  ;; -----------------------------
  ;; Schemas and Tables
  ;; -----------------------------

  (defschema account
    @doc "Account row with balance and guard"
    @model [(invariant (>= balance 0.0))]
    balance:decimal
    guard:guard)

  (deftable accounts:{account})

  (defschema supply-row
    @doc "Singleton supply ledger: the one-shot insert here is what makes a \
         \second init-mint impossible (insert fails on an existing key)."
    initial:decimal
    burned:decimal)

  (deftable supply:{supply-row})

  (defschema recipient
    @doc "One initial-distribution entry for init-mint."
    account:string
    guard:guard
    amount:decimal)

  ;; -----------------------------
  ;; Capabilities
  ;; -----------------------------

  (defcap DEBIT (sender:string)
    @doc "Internal debit permission: enforces the sender's account guard."
    (enforce-guard (at 'guard (read accounts sender))))

  (defcap CREDIT (receiver:string)
    @doc "Internal credit permission. Safe as a weak-body cap: only ever \
         \required by code paths that already validated the credit."
    true)

  (defcap MINT ()
    @doc "The one-shot initial mint, guarded by the deploy-time minter keyset."
    (enforce-guard MINT-GUARD))

  (defcap BURN (account:string)
    @doc "Self-burn permission: the account's own guard, nobody else's."
    (enforce-guard (at 'guard (read accounts account))))

  (defcap ROTATE (account:string)
    @doc "Guard-rotation authorization: the account's CURRENT guard. A       \
         \capability-scoped signature can target exactly this rotation."
    (enforce-guard (at 'guard (read accounts account))))

  (defcap BURNED (account:string amount:decimal)
    @event
    true)

  (defcap TRANSFER:bool (sender:string receiver:string amount:decimal)
    @managed amount TRANSFER-mgr
    (enforce (!= sender receiver) "same sender and receiver")
    (enforce (> amount 0.0) "amount must be positive")
    (enforce-unit amount)
    (compose-capability (DEBIT sender))
    (compose-capability (CREDIT receiver)))

  (defun TRANSFER-mgr:decimal (managed:decimal requested:decimal)
    (let ((newbal (- managed requested)))
      (enforce (>= newbal 0.0) "TRANSFER exceeded for balance")
      newbal))

  ;; -----------------------------
  ;; Account name protocol
  ;; -----------------------------

  (defun validate-account (account:string)
    @doc "Enforce account name length bounds and latin-1 charset."
    (enforce (is-charset CHARSET_LATIN1 account)
      (format "Account does not conform to the token contract charset: {}" [account]))
    (let ((account-length (length account)))
      (enforce (>= account-length MINIMUM_ACCOUNT_LENGTH)
        (format "Account name does not conform to the min length requirement: {}" [account]))
      (enforce (<= account-length MAXIMUM_ACCOUNT_LENGTH)
        (format "Account name does not conform to the max length requirement: {}" [account]))))

  (defun check-reserved:string (account:string)
    @doc "Return reserved-name protocol prefix ('k' for 'k:...'), or ''."
    (let ((pfx (take 2 account)))
      (if (= ":" (take -1 pfx)) (take 1 pfx) "")))

  (defun enforce-reserved:bool (account:string guard:guard)
    @doc "Enforce reserved account name protocols: a 'k:'-prefixed account \
         \must be the principal of its guard (prevents account squatting)."
    (if (validate-principal guard account)
      true
      (let ((r (check-reserved account)))
        (if (= r "")
          true
          (if (= r "k")
            (enforce false "Single-key account protocol violation")
            (enforce false
              (format "Reserved protocol guard violation: {}" [r])))))))

  ;; -----------------------------
  ;; fungible-v2 surface
  ;; -----------------------------

  (defun transfer:string (sender:string receiver:string amount:decimal)
    (with-capability (TRANSFER sender receiver amount)
      (debit sender amount)
      (with-read accounts receiver { "guard" := g }
        (credit receiver g amount))))

  (defun transfer-create:string
      (sender:string receiver:string receiver-guard:guard amount:decimal)
    (with-capability (TRANSFER sender receiver amount)
      (debit sender amount)
      (credit receiver receiver-guard amount)))

  (defpact transfer-crosschain:string
      (sender:string receiver:string receiver-guard:guard
       target-chain:string amount:decimal)
    (step (enforce false "cross-chain transfers are disabled: single-chain token")))

  (defun debit (account:string amount:decimal)
    (require-capability (DEBIT account))
    (with-read accounts account { "balance" := b }
      (enforce (<= amount b) "insufficient funds")
      (update accounts account { "balance": (- b amount) })))

  (defun credit (account:string guard:guard amount:decimal)
    (require-capability (CREDIT account))
    (validate-account account)
    (enforce-reserved account guard)
    (with-default-read accounts account
      { "balance": 0.0, "guard": guard }
      { "balance" := b, "guard" := g }
      (enforce (= g guard) "account guard mismatch")
      (write accounts account { "balance": (+ b amount), "guard": g })))

  (defun get-balance:decimal (account:string)
    (at 'balance (read accounts account)))

  (defun details:object{fungible-v2.account-details} (account:string)
    (with-read accounts account { "balance" := b, "guard" := g }
      { "account": account, "balance": b, "guard": g }))

  (defun precision:integer ()
    PRECISION)

  (defun enforce-unit:bool (amount:decimal)
    (enforce (= (floor amount PRECISION) amount) "precision violation"))

  (defun create-account:string (account:string guard:guard)
    (validate-account account)
    (enforce-reserved account guard)
    (insert accounts account { "balance": 0.0, "guard": guard })
    (format "created {}" [account]))

  (defun rotate:string (account:string new-guard:guard)
    ;; principal accounts must not rotate away from their proper guard -
    ;; a rotated 'k:' account would falsify the reserved-name protocol.
    (enforce (or (not (is-principal account))
                 (validate-principal new-guard account))
      "It is unsafe for principal accounts to rotate their guard")
    (with-capability (ROTATE account)
      (update accounts account { "guard": new-guard }))
    (format "rotated {}" [account]))

  ;; -----------------------------
  ;; One-shot mint, burn, supply views
  ;; -----------------------------

  (defun init-mint:string (recipients:[object{recipient}])
    @doc "One-shot: mint EXACTLY TOTAL-SUPPLY across the recipients. The     \
         \insert into the supply row makes a second call impossible by       \
         \construction (insert fails on an existing key), so the minter      \
         \keyset is powerless after this returns. Distribute to principal    \
         \(k:/w:) accounts, or mint in the deploy transaction itself: a      \
         \pre-created vanity name under a foreign guard aborts the mint      \
         \(griefing, not theft - principal names are immune)."
    (with-capability (MINT)
      (insert supply SUPPLY-KEY { "initial": TOTAL-SUPPLY, "burned": 0.0 })
      (let ((total (fold (lambda (acc:decimal r:object{recipient})
                           (+ acc (at 'amount r)))
                         0.0 recipients)))
        (enforce (= total TOTAL-SUPPLY) "mint must distribute exactly TOTAL-SUPPLY"))
      (map (lambda (r:object{recipient})
             (let ((amt:decimal (at 'amount r)))
               (enforce (> amt 0.0) "recipient amount must be positive")
               (enforce-unit amt)
               (with-capability (CREDIT (at 'account r))
                 (credit (at 'account r) (at 'guard r) amt))))
           recipients)
      "minted"))

  (defun burn:string (account:string amount:decimal)
    @doc "Self-burn under the account's own guard; decrements live supply."
    (enforce (> amount 0.0) "amount must be positive")
    (enforce-unit amount)
    (with-capability (BURN account)
      (with-read accounts account { "balance" := b }
        (enforce (<= amount b) "insufficient funds")
        (update accounts account { "balance": (- b amount) }))
      (with-read supply SUPPLY-KEY { "burned" := bu }
        (update supply SUPPLY-KEY { "burned": (+ bu amount) })))
    (emit-event (BURNED account amount))
    "burned")

  (defun initial-supply:decimal ()
    @doc "The fixed supply as minted (0.0 before init-mint)."
    (with-default-read supply SUPPLY-KEY { "initial": 0.0 } { "initial" := i } i))

  (defun burned-total:decimal ()
    @doc "Cumulative burned amount."
    (with-default-read supply SUPPLY-KEY { "burned": 0.0 } { "burned" := b } b))

  (defun circulating-supply:decimal ()
    @doc "initial - burned: the live supply."
    (- (initial-supply) (burned-total)))
)

;; Frozen governance means module admin exists ONLY inside the deploy
;; transaction - tables MUST be created here, they can never be created later.
(create-table accounts)
(create-table supply)
