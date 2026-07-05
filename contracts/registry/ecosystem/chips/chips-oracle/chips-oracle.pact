(module chips-oracle GOVERNANCE
  @doc "Chips oracle contract."
  (use coin)
; ============================================
; ==               CONSTANTS                ==
; ============================================
    (defconst ADMIN_KEYSET "n_e98a056e3e14203e6ec18fada427334b21b667d8.chips-admin" )
    (defconst ADMIN_ADDRESS "k:35fe76ea8f40caa2bb660b3236132f339dfdac2586a3d2a9d63ea96ee91202ad")
    (defconst DISCORD_ADDRESS "k:4aab9f08f1bd86c3ce007a9a87225ef061c09e7062efa622e2fd704c24514cfa")

; ============================================
; ==                  FUNCTIONS             ==
; ============================================

    (defschema price-schema
        @doc "Stores the price of each type of NFT or upgrade"
        price:decimal
    )

    (defschema counts-schema
        count:integer
    )

    (defschema price-history-schema
        @doc "key is the coin and the count"
        coin:string
        price:decimal
        date:time
    )

    (deftable price-history-table:{price-history-schema})
    (deftable counts-table:{counts-schema})

    (defun get-counts-data ()
      (map (lambda (k)
             { "key":  k
             , "data": (read counts-table k) })
           (keys counts-table))
    )

    (defun get-price-history-data ()
      (map (lambda (k)
             { "key":  k
             , "data": (read price-history-table k) })
           (keys price-history-table))
    )

    (defun add-new-coin (coin:string caller:string price:decimal)
        (with-capability (ADMIN_OR_DISCORD caller)
            (insert counts-table coin {"count": 1})
            (set-new-price caller price coin)
        )
    )

    (defun get-price-history (coin:string)
        @doc "Returns the entire price history of a coin"
        (select price-history-table (where "coin" (= coin)))
    )

    (defun get-current-price (coin:string)
        (let* (
                (count (get-count coin)) 
                (key (format "{}-{}" [coin (- count 1)]))
            )
            (at 'price (read price-history-table key))
        )
    )

    (defun set-new-price (account:string price:decimal coin:string)
        (with-capability (ADMIN_OR_DISCORD account)
        (let* (
                (count (get-count coin)) 
                (key (format "{}-{}" [coin count]))
            )
            (insert price-history-table key
              { "coin" : coin
              , "price" : price
              , "date" : (at 'block-time (chain-data)) }
            )
            (increase-count coin)
        ))
    )

  (defun increase-count (key:string)
    ;increase the count of a key in a table by 1
    (require-capability (PRIVATE))
    (update counts-table key {"count": (+ 1 (get-count key))})
  )

  (defun get-count (key:string)
    @doc "Gets the count for a key"
    (at "count" (read counts-table key ['count]))
  )

; ============================================
; ==             CAPABILITIES               ==
; ============================================

    (defcap ADMIN_OR_DISCORD (account:string)
        (compose-capability (ACCOUNT_GUARD account))
        (compose-capability (PRIVATE))
        (enforce-one "admin or discord" [(enforce (= account ADMIN_ADDRESS) "") (enforce (= account DISCORD_ADDRESS)"")])
    )

    (defcap ADMIN() ; Used for admin functions
        @doc "Only allows admin to call these"
        (enforce-keyset ADMIN_KEYSET)
        (compose-capability (PRIVATE))
        (compose-capability (ACCOUNT_GUARD ADMIN_ADDRESS))
    )

    (defcap ACCOUNT_GUARD (account:string)
        @doc "Verifies account meets format and belongs to caller"
        (enforce-guard
            (at "guard" (coin.details account))
        )
    )

 (defcap GOVERNANCE ()
    (enforce-guard (keyset-ref-guard "n_e98a056e3e14203e6ec18fada427334b21b667d8.chips-admin")))
    
    (defcap PRIVATE ()
        true
    )

)