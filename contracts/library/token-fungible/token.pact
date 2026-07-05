(module token GOV

  @doc "PCO library template: fungible token implementing fungible-v2 and     \
  \fungible-xchain-v1.                                                        \
  \                                                                           \
  \Deployment checklist (see README.md):                                      \
  \  1. Rename the module and wrap it in your namespace.                      \
  \  2. Replace the 'token-gov' keyset reference with your deployed,          \
  \     namespace-qualified governance keyset (multi-sig recommended).        \
  \  3. Run the co-located REPL suite, then validate on devnet -              \
  \     cross-chain steps CANNOT be proven in the bare REPL (no SPV)."

  (implements fungible-v2)
  (implements fungible-xchain-v1)

  ;; -----------------------------
  ;; Schema and Table
  ;; -----------------------------

  (defschema token-row
    @doc "Account row with balance and guard"
    @model [(invariant (>= balance 0.0))]
    balance:decimal
    guard:guard)

  (deftable token-table:{token-row})

  ;; -----------------------------
  ;; Constants
  ;; -----------------------------

  (defconst MINIMUM_PRECISION 12
    "Minimum allowed precision for token amounts")

  (defconst MINIMUM_ACCOUNT_LENGTH 3
    "Minimum account name length")

  (defconst MAXIMUM_ACCOUNT_LENGTH 256
    "Maximum account name length")

  (defconst VALID_CHAIN_IDS (map (int-to-str 10) (enumerate 0 19))
    "List of all valid Chainweb chain ids")

  ;; -----------------------------
  ;; Governance and Internal Caps
  ;; -----------------------------

  (defcap GOV ()
    @doc "Module governance. Replace 'token-gov' with your deployed keyset."
    (enforce-guard (keyset-ref-guard "token-gov")))

  (defcap DEBIT (sender:string)
    @doc "Internal debit permission. Enforces the SENDER's account guard - \
         \this is the authorization for every outgoing transfer."
    (enforce (!= sender "") "valid sender")
    (let ((sender-guard (at 'guard (read token-table sender))))
      (enforce-guard sender-guard)))

  (defcap CREDIT (receiver:string)
    @doc "Internal credit permission. Safe as a weak-body cap: only ever \
         \acquired composed under DEBIT/GOV-guarded paths."
    (enforce (!= receiver "") "valid receiver"))

  (defcap ROTATE (account:string)
    @doc "Autonomously managed one-shot capability for guard rotation. \
         \Authorization is the old guard, enforced in rotate."
    @managed
    true)

  (defcap MINT (account:string amount:decimal)
    @doc "Mint event. Weak-body: only acquired under GOV in mint."
    @event
    true)

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

  (defcap TRANSFER_XCHAIN:bool
    ( sender:string
      receiver:string
      amount:decimal
      target-chain:string )
    @managed amount TRANSFER_XCHAIN-mgr
    (enforce-unit amount)
    (enforce (> amount 0.0) "Cross-chain transfers require a positive amount")
    (compose-capability (DEBIT sender)))

  (defun TRANSFER_XCHAIN-mgr:decimal (managed:decimal requested:decimal)
    (enforce (>= managed requested)
      (format "TRANSFER_XCHAIN exceeded for balance {}" [managed]))
    0.0)

  (defcap TRANSFER_XCHAIN_RECD:bool
    ( sender:string
      receiver:string
      amount:decimal
      source-chain:string )
    @event
    true)

  ;; -----------------------------
  ;; Utilities
  ;; -----------------------------

  (defun enforce-unit:bool (amount:decimal)
    @doc "Enforce minimum decimal precision"
    (enforce (= (floor amount MINIMUM_PRECISION) amount)
      (format "Amount violates minimum precision: {}" [amount])))

  (defun precision:integer () MINIMUM_PRECISION)

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
  ;; Core Ledger Ops
  ;; -----------------------------

  (defun get-balance:decimal (account:string)
    (with-read token-table account
      { 'balance := balance }
      balance))

  (defun details:object{fungible-v2.account-details} (account:string)
    (with-read token-table account
      { 'balance := bal, 'guard := g }
      { 'account: account, 'balance: bal, 'guard: g }))

  (defun create-account:string (account:string guard:guard)
    (validate-account account)
    (enforce-reserved account guard)
    (insert token-table account { 'balance: 0.0, 'guard: guard })
    account)

  (defun rotate:string (account:string new-guard:guard)
    (with-capability (ROTATE account)
      ; principal accounts must not rotate away from their proper guard
      (enforce (or (not (is-principal account))
                   (validate-principal new-guard account))
        "It is unsafe for principal accounts to rotate their guard")
      (with-read token-table account
        { 'guard := old-guard }
        (enforce-guard old-guard)
        (update token-table account { 'guard: new-guard }))
      account))

  (defun debit:string (account:string amount:decimal)
    @doc "Internal. Callable only under DEBIT (sender-guard enforced there)."
    (require-capability (DEBIT account))
    (validate-account account)
    (enforce (> amount 0.0) "debit amount must be positive")
    (enforce-unit amount)
    (with-read token-table account
      { 'balance := balance }
      (enforce (<= amount balance) "Insufficient funds")
      (update token-table account { 'balance: (- balance amount) })
      "DEBIT_OK"))

  (defun credit:string (account:string guard:guard amount:decimal)
    @doc "Internal. Callable only under CREDIT."
    (require-capability (CREDIT account))
    (validate-account account)
    (enforce (> amount 0.0) "credit amount must be positive")
    (enforce-unit amount)
    (with-default-read token-table account
      { 'balance: -1.0, 'guard: guard }
      { 'balance := balance, 'guard := retg }
      ; never overwrite an existing guard with the caller-supplied one
      (enforce (= retg guard) "account guards do not match")
      (let ((is-new
             (if (= balance -1.0)
                 (enforce-reserved account guard)
               false)))
        (write token-table account
          { 'balance: (if is-new amount (+ balance amount)), 'guard: retg })
        "CREDIT_OK")))

  (defun transfer:string (sender:string receiver:string amount:decimal)
    @model [ (property (> amount 0.0))
             (property (!= sender receiver)) ]
    (enforce (!= sender receiver) "sender cannot be the receiver of a transfer")
    (validate-account sender)
    (validate-account receiver)
    (enforce (> amount 0.0) "transfer amount must be positive")
    (enforce-unit amount)
    (with-capability (TRANSFER sender receiver amount)
      (debit sender amount)
      (with-read token-table receiver
        { 'guard := g }
        (credit receiver g amount))))

  (defun transfer-create:string
    ( sender:string
      receiver:string
      receiver-guard:guard
      amount:decimal )
    (enforce (!= sender receiver) "sender cannot be the receiver of a transfer")
    (validate-account sender)
    (validate-account receiver)
    (enforce (> amount 0.0) "transfer amount must be positive")
    (enforce-unit amount)
    (with-capability (TRANSFER sender receiver amount)
      (debit sender amount)
      (credit receiver receiver-guard amount)))

  ;; -----------------------------
  ;; Cross-chain transfer
  ;; -----------------------------
  ;; NOTE: step 1 (resume) requires an SPV proof — full lifecycle is
  ;; provable ONLY on devnet/mainnet, never in the bare REPL.

  (defschema crosschain-schema
    @doc "Schema for yielded value in cross-chain transfers"
    receiver:string
    receiver-guard:guard
    amount:decimal
    source-chain:string)

  (defpact transfer-crosschain:string
    ( sender:string
      receiver:string
      receiver-guard:guard
      target-chain:string
      amount:decimal )
    (step
      (with-capability (TRANSFER_XCHAIN sender receiver amount target-chain)
        (validate-account sender)
        (validate-account receiver)
        ; fail fast: a k: receiver with a mismatched guard would debit here,
        ; then fail forever at step 1's enforce-reserved (funds locked in an
        ; uncompletable defpact). Reject before any state change.
        (enforce-reserved receiver receiver-guard)
        (enforce (!= "" target-chain) "empty target-chain")
        (enforce (!= (at 'chain-id (chain-data)) target-chain)
          "cannot run cross-chain transfers to the same chain")
        (enforce (> amount 0.0) "transfer quantity must be positive")
        (enforce-unit amount)
        (enforce (contains target-chain VALID_CHAIN_IDS)
          "target chain is not a valid chainweb chain id")
        (debit sender amount)
        (emit-event (TRANSFER sender "" amount))
        (let
          ((crosschain-details:object{crosschain-schema}
            { 'receiver: receiver
            , 'receiver-guard: receiver-guard
            , 'amount: amount
            , 'source-chain: (at 'chain-id (chain-data))
            }))
          (yield crosschain-details target-chain))))
    (step
      (resume
        { 'receiver := receiver
        , 'receiver-guard := receiver-guard
        , 'amount := amount
        , 'source-chain := source-chain
        }
        (emit-event (TRANSFER "" receiver amount))
        (emit-event (TRANSFER_XCHAIN_RECD "" receiver amount source-chain))
        (with-capability (CREDIT receiver)
          (credit receiver receiver-guard amount)))))

  ;; -----------------------------
  ;; Supply (governance-gated)
  ;; -----------------------------

  (defun mint:string (account:string guard:guard amount:decimal)
    @doc "Create AMOUNT new tokens for ACCOUNT. Governance-gated; emits MINT \
         \plus the ecosystem-standard (TRANSFER \"\" account amount) so       \
         \indexers reconstructing balances from fungible-v2 events stay      \
         \consistent (coin supply-increase pattern)."
    (with-capability (GOV)
      (with-capability (MINT account amount)
        (with-capability (CREDIT account)
          (emit-event (TRANSFER "" account amount))
          (credit account guard amount)))))
)
