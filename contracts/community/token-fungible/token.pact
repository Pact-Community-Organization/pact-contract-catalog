(module token GOV

  @doc "Minimal fungible token implementing fungible-v2 and fungible-xchain-v1.\n  \n  This module is designed as a neutral, reference-friendly implementation\n  focusing on clarity, capability-based security, and interface compliance."

  (implements fungible-v2)


  ;; -----------------------------
  ;; Schema and Table
  ;; -----------------------------

  (defschema token-row
    @doc "Account row with balance and guard"
    @model [(invariant (>= balance 0.0))]
    balance:decimal
    guard:guard)

  (deftable token-table:{token-row})

  ; details schema (match fungible-v2)
  ; details schema not needed; use interface type

  ;; -----------------------------
  ;; Governance and Internal Caps
  ;; -----------------------------

  (defcap GOV ()
    @doc "Admin governance capability for restricted operations"
    (enforce-guard (keyset-ref-guard "token-gov")))

  (defcap DEBIT (sender:string)
    @doc "Restricts debiting to valid sender"
    (enforce (!= sender "") "invalid sender"))

  (defcap CREDIT (receiver:string)
    @doc "Receiver crediting constraint"
    (enforce (!= receiver "") "invalid receiver"))

  (defcap ROTATE (account:string)
    @doc "Managed capability for guard rotation"
    @managed
    true)

  ;; -----------------------------
  ;; Constants and Utilities
  ;; -----------------------------

  (defconst MIN_PRECISION 12)

  (defun enforce-unit:bool (amount:decimal)
    @doc "Enforce minimum decimal precision"
    (enforce (= (floor amount MIN_PRECISION) amount)
      (format "Amount violates minimum precision: {}" [amount])))

  (defun precision:integer () MIN_PRECISION)

  ;; -----------------------------
  ;; Interface Capabilities (Managers)
  ;; -----------------------------

  (defcap TRANSFER:bool (sender:string receiver:string amount:decimal)
    @managed amount TRANSFER-mgr
    (enforce (!= sender receiver) "same sender and receiver")
    (enforce-unit amount)
    (enforce (> amount 0.0) "positive amount required")
    (compose-capability (DEBIT sender))
    (compose-capability (CREDIT receiver)))

  (defun TRANSFER-mgr:decimal (managed:decimal requested:decimal)
    (let ((newbal (- managed requested)))
      (enforce (>= newbal 0.0)
        (format "TRANSFER exceeded for balance {}" [managed]))
      newbal))

  ; No cross-chain in minimal token

  ;; -----------------------------
  ;; Core Ledger Ops
  ;; -----------------------------

  (defun get-balance:decimal (account:string)
    (at 'balance (read token-table account)))

  (defun details:object{fungible-v2.account-details} (account:string)
    (with-read token-table account
      { 'balance := bal, 'guard := g }
      { 'account: account, 'balance: bal, 'guard: g }))

  (defun create-account:string (account:string guard:guard)
    (enforce (!= account "") "empty account")
    (insert token-table account { 'balance: 0.0, 'guard: guard })
    account)

  (defun rotate:string (account:string new-guard:guard)
    (with-capability (ROTATE account)
      (enforce-guard (at 'guard (read token-table account)))
      (update token-table account { 'guard: new-guard })
      account))

  (defun debit:string (account:string amount:decimal)
    (require-capability (DEBIT account))
    (enforce (> amount 0.0) "debit amount must be positive")
    (enforce-unit amount)
    (with-read token-table account { 'balance := bal }
      (enforce (<= amount bal) "Insufficient funds")
      (update token-table account { 'balance: (- bal amount) })
      "DEBIT_OK"))

  (defun credit:string (account:string guard:guard amount:decimal)
    (require-capability (CREDIT account))
    (enforce (> amount 0.0) "credit amount must be positive")
    (enforce-unit amount)
    (with-default-read token-table account { 'balance: -1.0, 'guard: guard }
      { 'balance := bal, 'guard := retg }
      (enforce (= retg guard) "account guards do not match")
      (let ((is-new (= bal -1.0)))
        (write token-table account
          { 'balance: (if is-new amount (+ bal amount)), 'guard: retg })
        "CREDIT_OK")))

  (defun transfer:string (sender:string receiver:string amount:decimal)
    (with-capability (TRANSFER sender receiver amount)
      (debit sender amount)
      (with-read token-table receiver { 'guard := g }
        (credit receiver g amount))
      "TRANSFER_OK"))

  (defun transfer-create:string (sender:string receiver:string receiver-guard:guard amount:decimal)
    (with-capability (TRANSFER sender receiver amount)
      (debit sender amount)
      (credit receiver receiver-guard amount)
      "TRANSFER_CREATE_OK"))

  ; Minimal cross-chain pact to satisfy interface requirements
  (defschema crosschain-schema
    receiver:string
    receiver-guard:guard
    amount:decimal)

  (defpact transfer-crosschain:string (sender:string receiver:string receiver-guard:guard target-chain:string amount:decimal)
    (step
      (with-capability (DEBIT sender)
        (enforce (!= target-chain "") "empty target-chain")
        (enforce (> amount 0.0) "transfer quantity must be positive")
        (enforce-unit amount)
        (debit sender amount)
        (let ((x:object{crosschain-schema} {'receiver: receiver, 'receiver-guard: receiver-guard, 'amount: amount}))
          (yield x target-chain))))
    (step
      (resume {'receiver:= receiver, 'receiver-guard:= receiver-guard, 'amount:= amount}
        (with-capability (CREDIT receiver)
          (credit receiver receiver-guard amount)))))

  ;; -----------------------------
  ;; Admin helpers (for testing / provisioning)
  ;; -----------------------------

  ; Admin funding helper removed per requirements
)
