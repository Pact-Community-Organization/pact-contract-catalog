(module cyberfly_token GOVERNANCE

  (implements fungible-v2)
  (implements fungible-xchain-v1)
  (use free.util-fungible)
  (use free.util-chain-data)

 (bless "SMR9HQAJWDrXkzJ1bC5aRk0977SDiO2XaOVOGP5hzkk")
 (bless "ojv5xZdLrYERa7Pm_fuqSbC7q8AJiVNz2zXklugUnI0")
 (bless "nU4Il_0CYQBBVI6lPZ8JQgPn3b4jNvGgfL1zL624jA0")
 (bless "SovGDqT35Z65jbrJGqB4Ikp9s09QeIaJ8i3yVdNVSEM")

  (defun enforce-valid-amount
    ( precision:integer
      amount:decimal
    )
    (enforce (> amount 0.0) "Positive non-zero amount")
    (enforce-precision precision amount)
  )

  (defun enforce-valid-account (account:string)
    (enforce (> (length account) 2) "minimum account length")
  )

  (defun enforce-precision
    ( precision:integer
      amount:decimal
    )
    (enforce
      (= (floor amount precision) amount)
      "precision violation")
  )

  (defun enforce-valid-transfer
    ( sender:string
      receiver:string
      precision:integer
      amount:decimal)
    (enforce (!= sender receiver)
      "sender cannot be the receiver of a transfer")
    (enforce-valid-amount precision amount)
    (enforce-valid-account sender)
    (enforce-valid-account receiver)
  )

  (defschema entry
    balance:decimal
    guard:guard)

  (deftable ledger:{entry})

  (defcap GOVERNANCE ()
    (enforce-guard
      (keyset-ref-guard "free.cyberfly_team")))

  (defcap DEBIT (sender:string)
    (enforce-guard (at 'guard (read ledger sender))))

  (defcap CREDIT (receiver:string) true)

  (defcap TRANSFER:bool
    ( sender:string
      receiver:string
      amount:decimal
    )
    @managed amount TRANSFER-mgr
    (enforce-valid-transfer sender receiver (precision) amount)
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

  (defconst MINIMUM_PRECISION 12)

  (defun enforce-unit:bool (amount:decimal)
    (enforce-precision (precision) amount))

  (defun create-account:string
    ( account:string
      guard:guard
    )
    (enforce-valid-account account)
    (enforce-reserved account guard)
    (insert ledger account
      { "balance" : 0.0
      , "guard"   : guard
      })
    )

  (defun get-balance:decimal (account:string)
    (at 'balance (read ledger account))
  )

  (defun details:object{fungible-v2.account-details}
    ( account:string )
    (with-read ledger account
      { "balance" := bal
      , "guard" := g }
      { "account" : account
      , "balance" : bal
      , "guard": g })
    )

  (defun rotate:string (account:string new-guard:guard)
    (with-read ledger account
      { "guard" := old-guard }

      (enforce-guard old-guard)

      (update ledger account
        { "guard" : new-guard }))
    )


  (defun precision:integer ()
      MINIMUM_PRECISION)

  (defun transfer:string (sender:string receiver:string amount:decimal)

    (enforce (!= sender receiver)
      "sender cannot be the receiver of a transfer")
    (enforce-valid-transfer sender receiver (precision) amount)

    (with-capability (TRANSFER sender receiver amount)
      (debit sender amount)
      (with-read ledger receiver
        { "guard" := g }
        (credit receiver g amount))
      )
    )

  (defun transfer-create:string
    ( sender:string
      receiver:string
      receiver-guard:guard
      amount:decimal )

    (enforce (!= sender receiver)
      "sender cannot be the receiver of a transfer")
    (enforce-valid-transfer sender receiver (precision) amount)

    (with-capability (TRANSFER sender receiver amount)
      (debit sender amount)
      (credit receiver receiver-guard amount))
    )

  (defun debit:string (account:string amount:decimal)

    (require-capability (DEBIT account))
    (with-read ledger account
      { "balance" := balance }

      (enforce (<= amount balance) "Insufficient funds")

      (update ledger account
        { "balance" : (- balance amount) }
        ))
    )


    (defun credit:string (account:string guard:guard amount:decimal)

    (require-capability (CREDIT account))
    (with-default-read ledger account
      { "balance" : -1.0, "guard" : guard }
      { "balance" := balance, "guard" := retg }
      ; we don't want to overwrite an existing guard with the user-supplied one
      (enforce (= retg guard)
        "account guards do not match")

      (let ((is-new
             (if (= balance -1.0)
                 (enforce-reserved account guard)
               false)))

        (write ledger account
          { "balance" : (if is-new amount (+ balance amount))
          , "guard"   : retg
          }))
      ))


        (defun check-reserved:string (account:string)
    " Checks ACCOUNT for reserved name and returns type if \
    \ found or empty string. Reserved names start with a \
    \ single char and colon, e.g. 'c:foo', which would return 'c' as type."
    (let ((pfx (take 2 account)))
      (if (= ":" (take -1 pfx)) (take 1 pfx) "")))

  (defun enforce-reserved:bool (account:string guard:guard)
    @doc "Enforce reserved account name protocols."
    (if (validate-principal guard account)
      true
      (let ((r (check-reserved account)))
        (if (= r "")
          true
          (if (= r "k")
            (enforce false "Single-key account protocol violation")
            (enforce false
              (format "Reserved protocol guard violation: {}" [r]))
            )))))


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
    (debit sender amount)
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
      (credit receiver receiver-guard amount))
    ))
)
  
  (defun snapshot:string (minbal:decimal)
    "Return table where balance is bigger or equal than chosen  minbal balance"
    (select ledger (where "balance" (<= minbal)))
  )

  (defun createsnapshot ()
    "Creates Snapshot of balance, receiver guard. Only single keys-all guards are eligible"
    (select ledger (where "balance" (< 0.0)))
  )
  (defun read-all()
  (map (details) (keys ledger))
)
)