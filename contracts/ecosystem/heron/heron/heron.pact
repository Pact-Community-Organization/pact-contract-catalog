(module heron GOV
        
  @doc "Heron coin is a fun community driven utility memecoin"

  @model
    [ (defproperty conserves-mass
        (= (column-delta coin-table 'balance ) 0.0))

      (defproperty valid-account (account:string)
        (and
          (>= (length account) 3)
          (<= (length account) 256)))
    ]

  ; --------------------------------------------------------------------------
  ; Governance

  (defcap GOV ()
    (enforce-keyset "n_e309f0fa7cf3a13f93a8da5325cdad32790d2070.heron-token-gov")
  )

  ; --------------------------------------------------------------------------
  ; Tokenomics

  ;; Tokenomics initialization for your token
  (defun init-token:[string] (init-data:object)
    @doc "Initialize the tokens for the contract"

    (with-capability (GOV)
      (let
        (
          (sum-percent
            (lambda (curr-percent:decimal account-data:object)
              (+ curr-percent (at 'percent account-data))
            )
          )
          (init-token-account
            (lambda (initial-supply:decimal account-data:object)
              (let
                (
                  (account (at 'account account-data))
                  (percent (at 'percent account-data))
                  (guard (at 'guard account-data))
                )

                (insert coin-table account
                  { "balance" : (* initial-supply percent)
                  , "guard" : guard
                  }
                )
              )
            )
          )
        )

        ; Step 1: Validate the percentages
        ; fold iterations
        ; Iteration 1: Sum Percent with 0 and ROOT account -> (0 + 0.8) = 0.8
        ; Iteration 2: Sum Percent with 0.8 and LIQDUIDITY account -> (0.8 + 0.2) = 1.0
        (enforce
          (=
            (fold
              (sum-percent)
              0.0
              (at "accounts" init-data)
            )
            1.0
          )
          "Percentages must add up to 1.0"
        )

        ; Step 2: Initialize the token accounts
        (map
          (init-token-account (at "initial-supply" init-data))
          (at "accounts" init-data)
        )
      )
    )
  )

  ; --------------------------------------------------------------------------
  ; Implementation

  (implements fungible-v2)
  (implements fungible-xchain-v1)

  (use free.util-fungible)
  (use free.util-chain-data)

  ; v1 Fixed TX fee distribution and added emit BURN events.
  (bless "_LYeaSn3Vebi8d9jHugsNgUsCHZO4jg9IoFUpjNWzrw")

  ; Reduced burn fees to 4% and tx to 1% for easier visbility
  (bless "E4V2vqd5J3cGHI6gzu2Oiga13NEV5-V2xV2y0UTpuZQ")

  ; Reduced burn to 1%, rewrote mechanism for efficiency, dex, and simplicity
  (bless "dYIBCESg_ow7V-hD9UP_u6RPiEFzHzxWiG9ThUAFkPc")

  ; --------------------------------------------------------------------------
  ; Schemas and Tables

  (defschema coin-schema
    @doc "The coin contract token schema"
    @model [ (invariant (>= balance 0.0)) ]

    balance:decimal
    guard:guard)

  (deftable coin-table:{coin-schema})

  ; --------------------------------------------------------------------------
  ; Capabilities

  (defcap DEBIT (sender:string)
    "Capability for managing debiting operations"
    (enforce-guard (at 'guard (read coin-table sender)))
    (enforce (!= sender "") "valid sender"))

  (defcap CREDIT (receiver:string)
    "Capability for managing crediting operations"
    (enforce (!= receiver "") "valid receiver"))

  (defcap ROTATE (account:string)
    @doc "Autonomously managed capability for guard rotation"
    @managed
    true)

  (defcap TRANSFER:bool
    ( sender:string
      receiver:string
      amount:decimal
    )
    @managed amount TRANSFER-mgr
    (enforce (!= sender receiver) "same sender and receiver")
    (enforce-unit amount)
    (enforce (> amount 0.0) "Positive amount")
    (compose-capability (DEBIT sender))
    (compose-capability (CREDIT receiver))
  )

  (defun TRANSFER-mgr:decimal
    ( managed:decimal
      requested:decimal
    )

    (let ((newbal (- managed requested)))
      (enforce (>= newbal 0.0)
        (format "TRANSFER exceeded for balance {}" [managed]))
      newbal)
  )

  (defcap TRANSFER_XCHAIN:bool
    ( sender:string
      receiver:string
      amount:decimal
      target-chain:string
    )

    @managed amount TRANSFER_XCHAIN-mgr
    (enforce-unit amount)
    (enforce (> amount 0.0) "Cross-chain transfers require a positive amount")
    (compose-capability (DEBIT sender))
  )

  (defun TRANSFER_XCHAIN-mgr:decimal
    ( managed:decimal
      requested:decimal
    )

    (enforce (>= managed requested)
      (format "TRANSFER_XCHAIN exceeded for balance {}" [managed]))
    0.0
  )

  (defcap TRANSFER_XCHAIN_RECD:bool
    ( sender:string
      receiver:string
      amount:decimal
      source-chain:string
    )
    @event true
  )

  (defcap INTERNAL ()
      @doc "only for internal use"
      true
  )

  ; --------------------------------------------------------------------------
  ; Constants

  (defconst COIN_CHARSET CHARSET_LATIN1
    "The default coin contract character set")

  (defconst MINIMUM_PRECISION 12
    "Minimum allowed precision for transactions")

  (defconst MINIMUM_ACCOUNT_LENGTH 3
    "Minimum account length admissible for accounts")

  (defconst MAXIMUM_ACCOUNT_LENGTH 256
    "Maximum account name length admissible for accounts")

  (defconst VALID_CHAIN_IDS (map (int-to-str 10) (enumerate 0 19))
    "List of all valid Chainweb chain ids")

  (defconst ROOT_ACCOUNT_ID:string 'ROOT
    "ID for the account which initially owns all the tokens. ")

  (defconst TX_BURN:decimal 0.01
    "Percentage of every transaction burned")
  
  (defconst BURN:string "c:KI4cQnLt-DLK31X7mKay1c3DNPr-adIel5op8CkEOYo"
    "ID of burn account")
  
  (defconst KTGSWAP:string "c:dmr6Tk0MZspZ8LRjOnmtkeOn27_weWO1NoERdHMqPb8"
    "ID of KTG swap account")

  (defconst ESWAP:string "PUS35mt6HequLHptLo9cid_X6x1sSPOTUgWLuuQM0hc")

  (defconst BOND:string "c:l2mNQLajRJl3Lv7Rv6XOCJXvtlRl5j6qEfMJ3BsGKhA")

  (defconst SENDER:string "k:f186668ac03b8b152dc87eac29909f58e58453e2485a6d44046c3413cd77f789")

  (defconst NOBURNSERVICES:[string] [BURN, KTGSWAP, BOND, SENDER])

; --------------------------------------------------------------------------
; Utilities

(defun enforce-unit:bool (amount:decimal)
@doc "Enforce minimum precision allowed for coin transactions"
(enforce
  (= (floor amount MINIMUM_PRECISION)
      amount)
  (format "Amount violates minimum precision: {}" [amount]))
)

(defun validate-account (account:string)
  @doc "Enforce that an account name conforms to the coin contract minimum and maximum length requirements, as well as the latin-1 character set."

  (enforce
    (is-charset COIN_CHARSET account)
    (format
      "Account does not conform to the coin contract charset: {}"
      [account]))

  (let ((account-length (length account)))

    (enforce
      (>= account-length MINIMUM_ACCOUNT_LENGTH)
      (format
        "Account name does not conform to the min length requirement: {}"
        [account]))

    (enforce
      (<= account-length MAXIMUM_ACCOUNT_LENGTH)
      (format
        "Account name does not conform to the max length requirement: {}"
        [account]))
    )
)

; --------------------------------------------------------------------------
; Coin Implementation

(defun create-account:string (account:string guard:guard)
  @model [ (property (valid-account account)) ]

  (validate-account account)
  (enforce-reserved account guard)

  (insert coin-table account
    { "balance" : 0.0
    , "guard"   : guard
    })
  )

(defun get-balance:decimal (account:string)
  (with-read coin-table account
    { "balance" := balance }
    balance
    )
  )

(defun details:object{fungible-v2.account-details}
  ( account:string )
  (with-read coin-table account
    { "balance" := bal
    , "guard" := g }
    { "account" : account
    , "balance" : bal
    , "guard": g })
  )

(defun rotate:string (account:string new-guard:guard)
  (with-capability (ROTATE account)
    (with-read coin-table account
      { "guard" := old-guard }

      (enforce-guard old-guard)

      (update coin-table account
        { "guard" : new-guard }
        )))
  )


(defun precision:integer
  ()
  MINIMUM_PRECISION)

(defun transfer:string (sender:string receiver:string amount:decimal)
  @model [ (property conserves-mass)
            (property (> amount 0.0))
            (property (valid-account sender))
            (property (valid-account receiver))
            (property (!= sender receiver)) ]

  (enforce (!= sender receiver)
    "sender cannot be the receiver of a transfer")

  (validate-account sender)
  (validate-account receiver)

  (enforce (> amount 0.0)
    "transfer amount must be positive")

  (enforce-unit amount)

  (with-capability (TRANSFER sender receiver amount)
    (debit sender receiver amount)
    (with-read coin-table receiver
      { "guard" := g }

      (credit sender receiver g amount))
  )
)

(defun transfer-create:string
  ( sender:string
    receiver:string
    receiver-guard:guard
    amount:decimal )

  @model [ (property conserves-mass) ]

  (enforce (!= sender receiver)
    "sender cannot be the receiver of a transfer")

  (validate-account sender)
  (validate-account receiver)

  (enforce (> amount 0.0)
    "transfer amount must be positive")

  (enforce-unit amount)

  (with-capability (TRANSFER sender receiver amount)
    (debit sender receiver amount)
    (credit sender receiver receiver-guard amount))
)

(defun debit:string (account:string receiver:string amount:decimal)
  @doc "Debit AMOUNT from ACCOUNT balance"

  @model [ (property (> amount 0.0))
            (property (valid-account account))
          ]

  (validate-account account)

  (enforce (> amount 0.0)
    "debit amount must be positive")

  (enforce-unit amount)
  
  ;; Burn fee is calculated and added to the amount
  ;; (let (
  ;;   (new-amount (round (+ (* (compute-burn-fee account receiver) amount) amount)12))
  ;;   )

  ;; (enforce-unit new-amount)
  ;; (enforce (>= new-amount amount)
  ;; "debit amount plus Burn must be greater than amount")
  
  (require-capability (DEBIT account))
  (with-read coin-table account
    { "balance" := balance }

    (enforce (<= amount balance) "Insufficient funds")

    (update coin-table account
      { "balance" : (- balance amount) }
      ))
  ;; )
)

(defun burn-data:decimal ()
  @doc "Returns the burn fee amount"
    TX_BURN      
)
    
(defun compute-burn-fee:decimal (account:string receiver:string)
  @doc "Computes the burn fee for a transaction"
    (cond
      ((= account receiver) 0.0)
      ((= account ESWAP) 0.0)
      ((or (contains account NOBURNSERVICES) (contains receiver NOBURNSERVICES)) 0.0)
      ((try false (require-capability (dex-liq-wrapper.ALLOW-NO-BURN heron))) 0.0)
      ((try false (require-capability (heron.GOV))) 0.0)
      ((try false (require-capability (dex-liq-wrapper.BURN-ADMIN))) 0.0)
      TX_BURN
    )
)

(defun credit:string (sender:string account:string guard:guard amount:decimal)
  @doc "Credit AMOUNT to ACCOUNT balance"

  @model [ (property (> amount 0.0))
          (property (valid-account account))
        ]
  (validate-account sender)
  (validate-account account)
  (enforce (> amount 0.0) "credit amount must be positive")
  (enforce-unit amount)

  (require-capability (CREDIT account))

  (with-default-read coin-table account
    { "balance" : -1.0, "guard" : guard }
    { "balance" := balance, "guard" := retg }
    ; we don't want to overwrite an existing guard with the user-supplied one
    (enforce (= retg guard)
      "account guards do not match")

      (let ((is-new
        (if (= balance -1.0)
            (enforce-reserved account guard)
          false)))
  
      (write coin-table account
      {'balance: (if is-new amount (+ balance amount)),
      'guard:retg}))
    )
  ;; (if (= 0.0 (compute-burn-fee account sender)) ""
  ;;   (write-table-data amount account BURN TX_BURN)
  ;; )
)

;; (defun write-table-data:string (amount:decimal account:string fee-account:string fee:decimal)
;; (enforce (> fee 0.0) "Fee must be positive")
;; (require-capability (CREDIT account))

;;   (with-default-read coin-table fee-account
;;       { "balance" : 0.0
;;       , "guard"   : (create-null-guard)
;;       }
;;       { "balance" := balance
;;       , "guard"   := currentGuard
;;       }
;;       (enforce (!= currentGuard (create-null-guard)) (format "Please create {} first." [fee-account]))
;;       (write coin-table fee-account
;;           { "balance" : (round (+ balance (* fee amount))12)
;;           , "guard"   : currentGuard
;;         }
;;       )
;;     )
;; ) 

(defun enforce-null:bool ()
  false
)

(defun create-null-guard:guard ()
  (create-user-guard (enforce-null))
)

(defun enforce-reserved:bool (account:string guard:guard)
  "Enforce that a principal account matches to it's guard"
  (if (is-principal account)
      (enforce (validate-principal guard account)
                (format "Reserved protocol guard violation: {}" [(typeof-principal account)]))
      true)
)  
  
(defschema crosschain-schema
  @doc "Schema for yielded value in cross-chain transfers"
  receiver:string
  receiver-guard:guard
  amount:decimal
  source-chain:string)
    
(defpact transfer-crosschain:string (sender:string receiver:string receiver-guard:guard
                              target-chain:string amount:decimal)

(step
  (with-capability (TRANSFER_XCHAIN sender receiver amount target-chain)
    (enforce-valid-transfer-xchain sender receiver (precision) amount)
    (enforce-not-same-chain target-chain)
    (debit sender receiver amount)
    (emit-event (TRANSFER sender "" amount))

    (let ((crosschain-details:object{fungible-xchain-sch}
            {'receiver: receiver,
            'receiver-guard: receiver-guard,
            'amount: amount,
            'source-chain: (chain-id)}))
        (yield crosschain-details target-chain))))
(step
  (resume {'receiver:= receiver,
            'receiver-guard:= receiver-guard,
            'amount:= amount,
            'source-chain:= source-chain}

    (emit-event (TRANSFER "" receiver amount))
    (emit-event (TRANSFER_XCHAIN_RECD "" receiver amount source-chain))
    (with-capability (CREDIT receiver)
      (credit sender receiver receiver-guard amount))
    ))
)

)
            
  