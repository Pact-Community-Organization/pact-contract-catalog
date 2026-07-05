(module chips GOVERNANCE
  (use fungible-v2)
  (use coin)
  (use chips-oracle)
  (use chips-presale)

  (defconst CHIPS_BANK "chips-bank")
  (defconst CHIPS_LOCKED_WALLET "chips-locked-wallet")
  (defconst MINIMUM_LOCK_DURATION "min-lock-duration")
  (defconst EARLY_WITHDRAW_PENALTY "watts-withdraw-penalty")
  (defconst NUM_HOURS_TO_SCAN "hours-to-scan")
  ; rewards tracking
  (defconst TOTAL_LOCKS "total-locks")
  (defconst SUPPORTED_COINS "supported-coins")
  (defconst LOCKED "locked") ;total cTokens locked
  (defconst kWATT_TVL "kwatts-locked") ;total kWatt locked

  (defconst APR_CALC_COUNT "apr-calc-count")
  (defconst CLAIM_COUNT "claim-count")
  (defconst CHANGE_INDEX "change-index")
  (defconst ORDERS_COUNT "orders-count")
  (defconst EXTERNAL_CLAIM_COUNT "external-claim-count")
  ; accounts
  (defconst CHIPS_SIGNATORY "k:35fe76ea8f40caa2bb660b3236132f339dfdac2586a3d2a9d63ea96ee91202ad")
  (defconst ADMIN_ADDRESS "k:35fe76ea8f40caa2bb660b3236132f339dfdac2586a3d2a9d63ea96ee91202ad")
  (defconst BRIDGE_ORACLE_ADDRESS "k:4aab9f08f1bd86c3ce007a9a87225ef061c09e7062efa622e2fd704c24514cfa")
  (defconst ADMIN_KEYSET "n_e98a056e3e14203e6ec18fada427334b21b667d8.chips-admin")

  (defschema counts-schema
    count:integer
  )

  (defschema decimal-schema
    value:decimal
  )

  (defschema lock-schema
    ; key is the count of the number of total locks
    chip-ids:[string]
    account:string
    start-time:time
    duration:integer
    end-time:time
    coin:string
    cType:string
    kWatts:decimal
    cTokens:decimal ;the amount of cTokens locked
    lock-number:string
    released:bool
    mined-index:string
    change-index:integer
    hashrate:decimal
    coins-owed:decimal ;updated whenever transaction gas costs are getting too high
    degradation:bool
    extra:object
  )

  (defschema claim-schema
    ;key is the k:account of the user
    account:string
    coin:string
    claimed:decimal
    coin-price:decimal ;price of the claimed coin at the time of claiming
    lock-number:string
    date:time
  )

  (defschema external-claim-schema
    ; key is the external claim count
    coin:string
    account:string
    external-account:string
    transaction-id:string
    claimed:decimal
    lock-number:string
    date:time
    coin-price:decimal
  )

  (defschema transaction-schema
    @doc "For accounting purposes"
    account:string
    payment-token:string
    payment-token-amount:decimal
    payment-token-price:decimal
    cTokens-sold:decimal
    cTokens-usd-price:decimal
    kWATTs-sold:decimal
    kWATT-cost:decimal
    cType:string
    date:time
    lock-id:string
    end-time:time
  )

  (defschema user-locks-schema
    ; cheaply look up all locks that a user has. key is the k:account
    locks:list ; [ "lock-id1" "lock-id2" "lock-id3" ... ]
  )

  (defschema currency-module-schema
    @doc "Key is the coin that is being referred to. cKDA, cBTC, wBTC, etc."
    fungible:module{fungible-v2}
  )

  (defschema mineable-coins-list-schema
    ; key is just "coins"
    coins:list ;["kda" "btc" "ltc" ...]
  )

  (defschema mined-schema
    ; key is the index of the coin and the coins name. ex: kda:1
    coin:string
    mined:decimal
    total-hashrate:decimal
    previous:list
    divisor:list
    submitted-at:time
  )

  (defschema historic-apr-schema
    ; key is APR_CALC_COUNT that the entry is made plus the coin. `kda:1`
    ; this schema will contain 1 data point per day to create daily/monthly charts for APR
    apr:decimal ; 22.5 is 22.5% apr
    coin:string
    recorded-time:time
  )

  (defschema recent-mined-key-schema
    ; key is the relevant coin. ex. "kda" "btc" "doge"
    recent:string
  )

  (defschema lock-name-schema 
    @doc "Allows a user to name their rental"
    name:string
  )

  (deftable counts-table:{counts-schema})
  (deftable user-locks-table:{user-locks-schema})
  (deftable locks-table:{lock-schema})
  (deftable claim-table:{claim-schema})
  (deftable decimals-table:{decimal-schema})
  (deftable mined-table:{mined-schema})
  (deftable recent-mined-key-table:{recent-mined-key-schema})
  (deftable currency-table:{currency-module-schema})
  (deftable mineable-coins-list-table:{mineable-coins-list-schema})
  (deftable historic-apr-table:{historic-apr-schema})
  (deftable transaction-table:{transaction-schema})
  (deftable external-claim-table:{external-claim-schema})
  (deftable lock-name-table:{lock-name-schema})

  ;; MIGRATION FUNCTIONS CHAIN 2
    (defun init-counts-table (datakeys:[object])
    (with-capability (ADMIN_OR_BRIDGE BRIDGE_ORACLE_ADDRESS)
      (map (lambda (datakey:object)
             (insert counts-table (at 'key datakey) (at 'data datakey)))
           datakeys))
  )

  (defun init-user-locks-table (datakeys:[object])
    (with-capability (ADMIN_OR_BRIDGE BRIDGE_ORACLE_ADDRESS)
      (map (lambda (datakey:object)
             (insert user-locks-table (at 'key datakey) (at 'data datakey)))
           datakeys))
  )

  (defun init-locks-table (datakeys:[object])
    (with-capability (ADMIN_OR_BRIDGE BRIDGE_ORACLE_ADDRESS)
      (map (lambda (datakey:object)
             (insert locks-table (at 'key datakey) (at 'data datakey)))
           datakeys))
  )

  (defun init-claim-table (datakeys:[object])
    (with-capability (ADMIN_OR_BRIDGE BRIDGE_ORACLE_ADDRESS)
      (map (lambda (datakey:object)
             (insert claim-table (at 'key datakey) (at 'data datakey)))
           datakeys))
  )

  (defun init-decimals-table (datakeys:[object])
    (with-capability (ADMIN_OR_BRIDGE BRIDGE_ORACLE_ADDRESS)
      (map (lambda (datakey:object)
             (insert decimals-table (at 'key datakey) (at 'data datakey)))
           datakeys))
  )

  (defun init-mined-table (datakeys:[object])
    (with-capability (ADMIN_OR_BRIDGE BRIDGE_ORACLE_ADDRESS)
      (map (lambda (datakey:object)
             (update mined-table (at 'key datakey) (at 'data datakey)))
           datakeys))
  )

  (defun init-recent-mined-key-table (datakeys:[object])
    (with-capability (ADMIN_OR_BRIDGE BRIDGE_ORACLE_ADDRESS)
      (map (lambda (datakey:object)
             (insert recent-mined-key-table (at 'key datakey) (at 'data datakey)))
           datakeys))
  )

  (defun init-currency-table (key:string currency:module{fungible-v2} )
    (with-capability (ADMIN_OR_BRIDGE ADMIN_ADDRESS)
      (insert currency-table key 
        { "fungible": currency }))
  )

  (defun init-mineable-coins-list-table (datakeys:[object])
    (with-capability (ADMIN_OR_BRIDGE BRIDGE_ORACLE_ADDRESS)
      (map (lambda (datakey:object)
             (insert mineable-coins-list-table (at 'key datakey) (at 'data datakey)))
           datakeys))
  )

  (defun init-historic-apr-table (datakeys:[object])
    (with-capability (ADMIN_OR_BRIDGE BRIDGE_ORACLE_ADDRESS)
      (map (lambda (datakey:object)
             (insert historic-apr-table (at 'key datakey) (at 'data datakey)))
           datakeys))
  )

  (defun init-transaction-table (datakeys:[object])
    (with-capability (ADMIN_OR_BRIDGE BRIDGE_ORACLE_ADDRESS)
      (map (lambda (datakey:object)
             (insert transaction-table (at 'key datakey) (at 'data datakey)))
           datakeys))
  )

  (defun init-external-claim-table (datakeys:[object])
    (with-capability (ADMIN_OR_BRIDGE BRIDGE_ORACLE_ADDRESS)
      (map (lambda (datakey:object)
             (insert external-claim-table (at 'key datakey) (at 'data datakey)))
           datakeys))
  )

  (defun init-lock-name-table (datakeys:[object])
    (with-capability (ADMIN_OR_BRIDGE BRIDGE_ORACLE_ADDRESS)
      (map (lambda (datakey:object)
             (insert lock-name-table (at 'key datakey) (at 'data datakey)))
           datakeys))
  )

  (defun migrate-icBTC (account:string cType:string cToken-amount:decimal rental-duration:integer previously-mined:decimal caller:string)
    (with-capability (ADMIN_OR_BRIDGE caller)
    (let* (
        (hashrate cToken-amount)
        (total-kWATTs-required (* (* 0.45 rental-duration) cToken-amount))
        (orders-count-string (int-to-str 10 (get-count ORDERS_COUNT)))
        (cToken-module:module{fungible-v2} (at 'fungible (read currency-table cType)))
      )
      (with-capability (PRIVATE)
        (increase-count ORDERS_COUNT)
        (order-work cType cToken-amount)
        (create-lock 0.0 cToken-amount account rental-duration hashrate (drop 1 cType) cType previously-mined)
        (format "A {} day {} rental has been started on behalf of {} with a hashrate of {}. Previously-mined: {}. The rental ID is: {} " [rental-duration cType account hashrate previously-mined orders-count-string])
      )
    ))
  )

  (defun calculate-apr (lock-id:string)
    @doc "Utilized to calculate historic APR and store in a table, usually once daily"
    (with-capability (ADMIN)
    (let* (
        (lock-data (read locks-table lock-id))
        (coin (at 'coin lock-data))
        (previous-count (format "{}:{}" [coin (get-count APR_CALC_COUNT)]))
        (kWatts-per-day (get-value (format "{}-kWatts" [coin])))
        (mined-index-end (if (< (at 'end-time lock-data) (at 'block-time (chain-data)))
                            (decide-end-index (at 'end-time lock-data) coin)
                            (get-recent coin)
                          ) )
        (previous-time (at 'recorded-time (read historic-apr-table previous-count)))
        (recorded-time (at 'block-time (chain-data)))
        (time-passed-in-days (round (/ (diff-time recorded-time previous-time) 86400) 5))
        (kWatts-required (* kWatts-per-day time-passed-in-days))
        (cTokens-required (* 0.000548 time-passed-in-days))
        (cToken-price (chips-oracle.get-current-price (format "c{}" [coin])))
        (mined-coin-price (chips-oracle.get-current-price coin))
        (mined-coin2-price (chips-oracle.get-current-price "DOGE"))
        (kWatt-price (- (chips-oracle.get-current-price "kWATT") 0.01))
        (total-usd-expenditure (+ (* cTokens-required cToken-price) (* kWatts-required kWatt-price)) )
        (total-mined (get-mined-for-lock coin coin))
        (total-mined-usd-value (* mined-coin-price total-mined))
        (profit (- total-mined-usd-value total-usd-expenditure))
        (one-year-expenditure (* (/ total-usd-expenditure time-passed-in-days) 365))
        (one-year-profit (round (* (/ profit time-passed-in-days) 365) 5))
        (apr (round (* (/ one-year-profit one-year-expenditure) 100) 2))
          ; 0.000548 cTokens degrade per 1 day

      )
      (update locks-table coin
        { "mined-index" : mined-index-end
        , "change-index" : (get-count (format "{}-change-index" [(at 'coin lock-data)]))
        })
      (with-capability (PRIVATE) (increase-count APR_CALC_COUNT))
      (insert historic-apr-table (format "{}:{}" [coin (get-count APR_CALC_COUNT)])
        { "apr" : apr
        , "coin" : coin
        , "recorded-time" : recorded-time }
      )

      ["apr" apr "time passed" time-passed-in-days "kwatts required" kWatts-required "ckda" (* cTokens-required cToken-price) "total mined in usd" total-mined-usd-value "profit" profit "exp" total-usd-expenditure "one year exp"  one-year-expenditure "one year profit" one-year-profit]
    ))
  )

  (defun get-apr-table (coin:string)
    @doc "Returns the entire APR history of the selected coin"
    (select historic-apr-table (where "coin" (= coin)))
  )

  (defun add-new-coin (COIN:string fungible:module{fungible-v2} total-hashrate:decimal kWatts-per-day:decimal external:bool)
    @doc "Allows admin to add a new mineable coin."
    (with-capability (ADMIN)
    (let* (
        (mined-table-index (format-time "%s" (time (format-time "%Y-%m-%dT%H:00:00Z" (at 'block-time (chain-data))))) )
        (mineable-coins (with-default-read mineable-coins-list-table SUPPORTED_COINS
          { "coins": [] }
          { "coins" := coins }
          coins))
      )
      (insert decimals-table (format "{}-{}" [COIN LOCKED]) { "value" : 0.0})
      (insert decimals-table (format "{}-kWatts" [COIN]) { "value" : kWatts-per-day })
      (insert recent-mined-key-table COIN { "recent" : (format "{}:{}" [COIN mined-table-index]) })
      (insert counts-table (format "{}-{}" [COIN CHANGE_INDEX]) { "count" : 0 })
      (insert mined-table (format "{}:{}" [COIN mined-table-index])
        { "coin" : COIN
        , "mined" : 0.0
        , "total-hashrate" : total-hashrate
        , "previous" : [0]
        , "divisor" : [total-hashrate]
        , "submitted-at" : (at 'block-time (chain-data)) })
      (write mineable-coins-list-table SUPPORTED_COINS { "coins" : (+ [COIN] mineable-coins) })
    )
    (if (= external true)
      ""
      (insert currency-table COIN { "fungible": fungible }))
    )
    (insert historic-apr-table (format "{}:0" [COIN]) { "apr" : 20.0, "coin": COIN, "recorded-time": (at 'block-time (chain-data)) })
  )

  (defun insert-coin-mined (coin:string mined:decimal caller:string)
      @doc "Updates the total amount of coins mined for any type of coin"
      (with-capability (PRIVATE)
      (with-capability (ADMIN_OR_BRIDGE caller)
        (let* (
            (previous-mined-index (get-recent coin))
            (new-mined-index (format-time "%s" (time (format-time "%Y-%m-%dT%H:00:00Z" (at 'block-time (chain-data))))) )
            (previous-data (read-mined previous-mined-index))
          )
          (enforce (>= mined (at 'mined previous-data)) "Error: the amount mined cannot go down")
          (insert mined-table (format "{}:{}" [coin new-mined-index])
            { "coin" : coin
            , "mined" : mined
            , "total-hashrate" : (at 'total-hashrate previous-data)
            , "previous" : (at 'previous previous-data)
            , "divisor" : (at 'divisor previous-data)
            , "submitted-at" : (at 'block-time (chain-data))  } )
          (update recent-mined-key-table coin
              { "recent": (format "{}:{}" [coin new-mined-index]) })
         
            (format "{} updated to {} mined" [coin mined])
        )
      ))
  )

  (defun fix-coin-mined (key:string mined:decimal)
    (with-capability (ADMIN)
    (let* (
        (previous-mined-index (get-recent "DOGE"))
        (previous-data (read-mined previous-mined-index))
      )
      (insert mined-table key 
        { "coin" : "DOGE"
        , "mined" : mined
        , "total-hashrate" : (at 'total-hashrate previous-data)
        , "previous" : (at 'previous previous-data)
        , "divisor" : (at 'divisor previous-data)
        , "submitted-at" : (at 'block-time (chain-data))  } )
      ))
    (format "DOGE inserted at {}, {} mined" [key mined])
  )

  (defun change-total-hashrate (additional-hashrate:decimal cType:string)
    @doc "Allows the admin to increase or decrease the total available hashrate for a given coin"
    (with-capability (PRIVATE)
    (with-capability (ACCOUNT_GUARD CHIPS_SIGNATORY)
      (let* (
          (mined-index (get-recent cType))
          (new-mined-index (format-time "%s" (time (format-time "%Y-%m-%dT%H:00:01Z" (at 'block-time (chain-data))))) )
          (previous-data (read-mined mined-index))
          (new-hashrate (+ additional-hashrate (at 'total-hashrate previous-data)))
          (new-previous (+ (at 'previous previous-data) [(- (at 'mined previous-data) (fold (+) 0.0 (at 'previous previous-data)))] ))
          (new-divisor (+ (at 'divisor previous-data) [(at 'total-hashrate previous-data)]))
        )
        (insert mined-table (format "{}:{}" [cType new-mined-index])
          { "coin" : cType
          , "mined" : (at 'mined previous-data)
          , "total-hashrate" : new-hashrate
          , "previous" : new-previous
          , "divisor" : new-divisor
          , "submitted-at" : (at 'block-time (chain-data))})
        (increase-count (format "{}-change-index" [cType]))
        (update recent-mined-key-table cType
          { "recent": (format "{}:{}" [cType new-mined-index]) })
        (format "previous-data: {}, New hashrate total: {}, new previous list: {}, new divisor: {}" [previous-data new-hashrate new-previous new-divisor])
      )
    ))
  )

  (defun claim-multiple (account:string external-account:[string] lock-ids:list)
    @doc "Allows a user to claim from any number of locks in one transaction."
    (let* (
           ; Generate claim objects from each lock.
           (data (with-capability (PRIVATE)
                  (map (claim account external-account) lock-ids)))
           ; Sum the claims for each coin.
           (folded-data
             (filter
               (lambda (entry) (not (= (at 'claim entry) 0.0)))
               (map
                 (lambda (coin)
                   { "coin": coin,
                     "claim": (fold
                                (lambda (acc item)
                                  (if (= coin (at 'coin item))
                                      (+ acc (at 'claim item))
                                      acc))
                                0.0
                                data) })
                 ["ALPH" "KAS" "BTC" "LTC" "KDA"])))
           ; Define the list of on-chain coins (extend as needed)
           (on-chain-coins ["KDA"])
           ; Partition data using contains.
           (on-chain (filter (lambda (entry) (contains (at 'coin entry) on-chain-coins )) folded-data))
           (external (filter (lambda (entry) (not (contains (at 'coin entry) on-chain-coins ))) folded-data))
           ; Process on-chain claims.
           (on-chain-results
             (map (lambda (entry)
                    (with-capability (PRIVATE)
                    (with-capability (BANK_DEBIT)
                    (initiate-on-chain-claim account (at 'claim entry) (at 'coin entry)))))
                  on-chain))
           ; Process external claims by formatting a message.
           (external-results
             (map (lambda (entry)
                    (if (= (at 'coin entry) "LTC")
                      (format "Claimed {} {} and {} DOGE. These coins will be sent to your provided addresses as soon as this transaction is picked up by the Chips oracle. This can take up to 24 hours under manual review."
                              [(at 'claim entry)
                               (at 'coin entry)
                               (at 'claimed (read external-claim-table (int-to-str 10 (- (get-count EXTERNAL_CLAIM_COUNT) 2))))])
                      (format "Claimed {} {}. These coins will be sent to your provided address as soon as this transaction is picked up by the Chips oracle. This can take up to 24 hours under manual review." [(at 'claim entry) (at 'coin entry)])))
                  external))
         )
      { "on-chain": on-chain-results, "external": external-results}
    )
  )

  (defun claim (account:string external-account:[string] lock-id:string)
    @doc "Allows the user to claim coins from their rental at any time. If their rental is expired, it will be closed out."
    (require-capability (PRIVATE))
    (let* (
        (lock-data (read locks-table lock-id))
        (coin (at 'coin lock-data))
        (is-expired (< (at 'end-time lock-data) (at 'block-time (chain-data))))
        (mined-index-end (if (= is-expired true)
                          (decide-end-index (at 'end-time lock-data) coin)
                          (get-recent coin)
                        ) )
        (total (get-mined-for-lock lock-id coin))
      )
      ;
      (enforce (= false (at 'released lock-data)) "This lock is expired and there are no claimable rewards")
    ;   (if (= is-expired true) (with-capability (PRIVATE) (withdraw-from-lock account external-account lock-id)) "")
      (if (> total 0.0)
        (with-capability (CLAIM account lock-id)
          (if (= coin "LTC")
            (let* (
                (total-secondary (get-mined-for-lock lock-id "DOGE"))
              )
              (initiate-external-claim account "DOGE" (at 1 external-account) total-secondary lock-id)
            )
            ""
          )
          (update locks-table lock-id
            { "mined-index" : mined-index-end
            , "change-index" : (get-count (format "{}-change-index" [(at 'coin lock-data)]))
            , "coins-owed" : 0.0
            })
          { "coin" : coin
          , "claim" : (if (contains coin ["LTC" "KAS" "ALPH" "BTC"])
                        (with-capability (PRIVATE) (initiate-external-claim account coin (at 0 external-account) total lock-id))
                        (with-capability (PRIVATE)
                          (record-claim account lock-id total coin)
                          total ))}
        )
        { "coin" : coin
        , "internal" : true
        , "claim" : 0.0 }
      )
    )
  )

  (defun initiate-external-claim (account:string coin:string external-account:string amount:decimal lock-id:string)
    (require-capability (PRIVATE))
    (let* (
        (external-claim-count (get-count EXTERNAL_CLAIM_COUNT))
      )
      (insert external-claim-table (int-to-str 10 external-claim-count)
        { "coin" : coin
        , "account" : account
        , "external-account" : external-account
        , "transaction-id" : "none"
        , "claimed" : amount
        , "date" : (at 'block-time (chain-data))
        , "lock-number" : lock-id
        , "coin-price" : (chips-oracle.get-current-price coin)})
      (with-capability (PRIVATE)
        (increase-count EXTERNAL_CLAIM_COUNT))
      amount
    )
  )

  (defun read-external-claim-table (key:string)
    @doc "Returns data if a user claimed, counting up from one"
    (read external-claim-table key)
  )

  (defun initiate-on-chain-claim (account:string total:decimal coin:string)
    (require-capability (PRIVATE))
    (let* (
        (fung:module{fungible-v2} (at 'fungible (read currency-table coin)))
        (old-balance (fung::get-balance account))
      )
      (install-capability (fung::TRANSFER CHIPS_LOCKED_WALLET account total))
      (fung::transfer CHIPS_LOCKED_WALLET account total)
      (format "Claimed {} {}. Old Balance: {} {}, New Balance {} {}." [total coin old-balance coin (fung::get-balance account) coin])
    )
  )

  (defun record-claim (account:string lock-id:string amount:decimal coin:string )
    (require-capability (PRIVATE))
    (let* (
        (claim-count (int-to-str 10 (get-count CLAIM_COUNT)))
        (coin-price (chips-oracle.get-current-price coin))
      )
      (insert claim-table claim-count
        { "account" : account
        , "coin" : coin
        , "coin-price" : coin-price
        , "claimed" : amount
        , "lock-number" : lock-id
        , "date" : (at 'block-time (chain-data))}
      )
      (increase-count CLAIM_COUNT)
    )
  )

  (defun get-claimed (account:string)
    (+
      (select external-claim-table (where "account" (= account)))
      (select claim-table (where "account" (= account)))
    )
  )

  (defun get-mined-for-lock (lock-id:string coin:string)
    (let* (
        (lock-data (read locks-table lock-id))
        (previously-mined (at 'coins-owed lock-data))
        (lock-change-index (at 'change-index lock-data)) 
        (mined-index-LTC (if (= "DOGE" coin)
                            (+ "DOGE" (drop 3 (at 'mined-index lock-data)))
                            (at 'mined-index lock-data)
                            ))
        (mined-index-start mined-index-LTC)
        (mined-index-end (if (< (at 'end-time lock-data) (at 'block-time (chain-data)))
                            (decide-end-index (at 'end-time lock-data) coin)
                            (get-recent coin)
                          ) )
        (start-mined-data (read-mined mined-index-start)) 
        (recent-mined-data (read-mined mined-index-end)) 
        (recent-change-index (get-count (format "{}-change-index" [(at 'coin lock-data)])) ) ; 2
        (previous (at 'previous recent-mined-data))
        (divisor (at 'divisor recent-mined-data))
        (lock-end-change-index (- (length divisor) 1))
        (lock-hashrate (at 'hashrate lock-data))
        (mined-at-first-addition (fold (+) 0.0 (drop (- (length previous) (+ lock-change-index 2)) previous)))
        
        (total1 (if (= lock-change-index recent-change-index)
          (* (- (at 'mined recent-mined-data) (at 'mined start-mined-data)) (/ lock-hashrate (at 'total-hashrate start-mined-data)))
          0.0))
        (first-calc (* (- mined-at-first-addition (at 'mined start-mined-data)) (/ lock-hashrate (at 'total-hashrate start-mined-data))))
        (cascading (if (> (- lock-end-change-index lock-change-index) 1) 
          (fold (+) 0.0 (map (cascading-helper lock-hashrate previous divisor) (enumerate (+ lock-change-index 1) (- lock-end-change-index 1))))
          0.0) )
        (last-calc (* (- (at 'mined recent-mined-data) (fold (+) 0.0 previous)) (/ lock-hashrate (at 'total-hashrate recent-mined-data))))
        (total (if (= 0.0 total1)
          (+ (+ first-calc cascading) last-calc)
          total1))
        (adjusted-total (if (= "LTC" coin) (* total 10) total))
        (zeroed (if (< adjusted-total 0.0) 0.0 adjusted-total))
      )
      (if (at 'released lock-data)
        0
        (+ (round zeroed 8) previously-mined))
    )
  )

(defun get-mined-for-lock2 (lock-id:string coin:string)
  (let* (
      (lock-data (read locks-table lock-id))
      (previously-mined (at 'coins-owed lock-data))
      (lock-change-index (at 'change-index lock-data)) 
      (mined-index-LTC (if (= "DOGE" coin)
                          (+ "DOGE" (drop 3 (at 'mined-index lock-data)))
                          (at 'mined-index lock-data)
                          ))
      (mined-index-start mined-index-LTC)
      (mined-index-end (if (< (at 'end-time lock-data) (at 'block-time (chain-data)))
                          (decide-end-index (at 'end-time lock-data) coin)
                          (get-recent coin)
                        ) )
      (start-mined-data (read-mined mined-index-start)) 
      (recent-mined-data (read-mined mined-index-end)) 
      (recent-change-index (get-count (format "{}-change-index" [(at 'coin lock-data)])) ) ; 2
      (previous (at 'previous recent-mined-data))
      (divisor (at 'divisor recent-mined-data))
      (lock-end-change-index (- (length divisor) 1))
      (lock-hashrate (at 'hashrate lock-data))
      (mined-at-first-addition (fold (+) 0.0 (drop (- (length previous) (+ lock-change-index 2)) previous)))
      
      (total1 (round (if (= lock-change-index recent-change-index)
        (* (- (at 'mined recent-mined-data) (at 'mined start-mined-data)) (/ lock-hashrate (at 'total-hashrate start-mined-data)))
        0.0) 10))
      (first-calc (round (* (- mined-at-first-addition (at 'mined start-mined-data)) (/ lock-hashrate (at 'total-hashrate start-mined-data))) 10))
      (cascading (if (> (- lock-end-change-index lock-change-index) 1) 
        (fold (+) 0.0 (map (cascading-helper lock-hashrate previous divisor) (enumerate (+ lock-change-index 1) (- lock-end-change-index 1))))
        0.0) )
      (last-calc (* (- (at 'mined recent-mined-data) (fold (+) 0.0 previous)) (/ lock-hashrate (at 'total-hashrate recent-mined-data))))
      (total (round (if (= 0.0 total1)
        (+ (+ first-calc cascading) last-calc)
        total1) 10))
      (adjusted-total (if (= "LTC" coin) (* total 10) total))
      (zeroed (if (< adjusted-total 0.0) 0.0 adjusted-total))
    )
    {
      "lock-data": lock-data,
      "previously-mined": previously-mined,
      "lock-change-index": lock-change-index,
      "mined-index-LTC": mined-index-LTC,
      "mined-index-start": mined-index-start,
      "mined-index-end": mined-index-end,
      "start-mined-data": start-mined-data,
      "recent-mined-data": recent-mined-data,
      "recent-change-index": recent-change-index,
      "previous": previous,
      "divisor": divisor,
      "lock-end-change-index": lock-end-change-index,
      "lock-hashrate": lock-hashrate,
      "mined-at-first-addition": mined-at-first-addition,
      "total1": total1,
      "first-calc": first-calc,
      "cascading": cascading,
      "last-calc": last-calc,
      "total": total,
      "adjusted-total": adjusted-total,
      "zeroed": zeroed
    }
  )
)

  (defun cascading-helper (lock-hashrate:decimal previous:list divisor:list index:integer)
    (* (at index previous) (/ lock-hashrate (at (+ index 1) divisor)))
  ) 

  (defun get-all-unclaimed-rewards ()
    @doc "For accounting purposes, return the entire reward balance owed to Chips customers"
    (let* (
      (all-data (map (get-unclaimed-for-lock) (keys locks-table)))
      (coins ["KDA" "LTC" "BTC" "DOGE"])
      (result
      (map (lambda (c)
           { "coin":   c
           , "rewards": (fold
                          (lambda (acc item)
                            (if (= c "DOGE")
                                (+ acc (at 'DOGE item))            ; sum DOGE field
                                (if (= c (at 'coin item))
                                    (+ acc (at 'rewards item))     ; sum rewards for matching coin
                                    acc)))
                          0.0
                          all-data) })
         coins))
      )
      result
    )
  )

  (defun get-unclaimed-for-lock (lock-id:string)
    @doc "Returns the total amount of rewards unclaimed for a rental"
    (let* (
        (lock-data (read locks-table lock-id))
        (DOGE-rewards (if (= (at 'coin lock-data) "LTC") (get-mined-for-lock lock-id "DOGE") 0.0))
        (rewards (get-mined-for-lock lock-id (at 'coin lock-data)))
      )
      { "coin" : (at 'coin lock-data), "rewards" : rewards , "DOGE" : DOGE-rewards }
    )
  )

  (defun decide-end-index (end-time:time coin:string)
    @doc "Returns the actual end time if it exists as a key in the mined table, otherwise scans some amount of hours backwards"
    (let* (
        (hopeful-index (format "{}:{}" [coin (format-time "%s" end-time)]))
        (test (with-default-read mined-table hopeful-index
          { "coin": "u wish" }
          { "coin" := coin }
          coin))
        (scan (if (= "u wish" test)
          (filter (!= "") (map (scan-for-valid-mined-key end-time coin) (enumerate -1 (- 0 (get-count NUM_HOURS_TO_SCAN))))) ;offset by -1 hour until a valid entry is found
          [hopeful-index]
        ))
        (result (if (> (length scan) 0)
                    (at 0 scan)
                    "x") )
      )
      (enforce (!= result "x") "Your attempt to claim will not be possible due to a bug. Please contact an administrator to get this resolved")
      result
    )
  )

  ; This function allows for errors when submitting shares for up to a few days
  (defun scan-for-valid-mined-key (end-time:time coin:string offset:integer)
    @doc "scans for a valid key on the mined table if the original end time was not found."
    (let* (
        (coin (with-default-read mined-table (format "{}:{}" [coin (format-time "%s" (add-time end-time (hours offset)))])
          { "coin": "u wish" }
          { "coin" := coin }
          coin))
        (result (if (= "u wish" coin)
          ""
          (format "{}:{}" [coin (format-time "%s" (add-time end-time (hours offset)))]) ) )
      )
      result
    )
  )

  (defun get-days-remaining-in-lock (lock-id:string)
    (let* (
        (lock-data (read locks-table lock-id))
        (end-time (at 'end-time lock-data))
        (current-time (at 'block-time (chain-data)))
      )
      (round (/ (diff-time end-time current-time) 86400) 6)
    )
  )

  (defun get-currency-table ()
    (select currency-table (where "fungible" (!= coin)))
  )

  (defun start-rental (account:string cType:string cToken-amount:decimal payment-token:string payment-token-amount:decimal rental-duration:integer caller:string referrer:string)
    (let* (
        (minimum-rental-duration (get-count MINIMUM_LOCK_DURATION))
        (purchase-details (gather-purchase-details account cType cToken-amount payment-token payment-token-amount rental-duration))
        (rental-duration-bonus 0);(str-to-int (drop -2 (format "{}" [(round (* 0.07777777778 rental-duration) 0)])))) ; 1 week per 3 month duration bonus
        (total-cTokens-locked (at 'total-cTokens-locked purchase-details))
        (hashrate (at 'hashrate purchase-details))
        (orders-count-string (int-to-str 10 (get-count ORDERS_COUNT)))
        (cToken-module:module{fungible-v2} (at 'fungible (read currency-table cType)))
        (end-time (time (format-time "%Y-%m-%dT%H:00:00Z" (add-time (at 'block-time (chain-data)) (days rental-duration)))))
      )
      (enforce (>= rental-duration minimum-rental-duration) (format "Your rental must be at least {} days" [minimum-rental-duration]))
      (enforce (<= rental-duration 365) (format "Maximum rental duration is 365 days"))
      (if (= "KDA" payment-token)
        (coin.transfer account CHIPS_BANK payment-token-amount)
        (with-capability (ADMIN_OR_BRIDGE caller)
          "Enforce function is being called by the admin or bridge when the currency isn't KDA"
        )
      )
      (if (> cToken-amount 0.0) (cToken-module::transfer account CHIPS_BANK cToken-amount) "")
      (with-capability (PRIVATE)
        (with-capability (CALL_POLICY_MODULES) (update-presale-referral account (at 'dollar-value-of-payment purchase-details) referrer))
        (update-transaction-table orders-count-string account payment-token payment-token-amount (at 'payment-token-price purchase-details)
          (at 'cTokens-purchased purchase-details) (at 'cTokens-usd-price purchase-details) (at 'total-kWATTs-required purchase-details)
          (at 'total-kWATT-cost purchase-details) cType orders-count-string end-time)
        (mint-kWATT CHIPS_LOCKED_WALLET (round (at 'total-kWATTs-required purchase-details) 8))
        (order-work cType total-cTokens-locked)
        (create-lock (at 'total-kWATTs-required purchase-details) total-cTokens-locked account (+ rental-duration rental-duration-bonus) hashrate (drop 1 cType) cType 0.0)
        (format "A {} day rental has been started with a hashrate of {}. Your rental ID is: {} " [(+ rental-duration rental-duration-bonus) hashrate orders-count-string])
      )
    )
  )

  (defun extend-one-rental (account:string lock-id:string use-kWATTs:bool payment-token:string payment-token-amount:decimal extend-by-days:integer caller:string)
    @doc "Allows a user to extend the duration of their lock by a number of days"
    (with-capability (ACCOUNT_GUARD account)
      (let* (
          (calculations (gather-extend-expense2 account payment-token false lock-id extend-by-days))
          (lock-data (at 'lock-data calculations))
          (cType (at 'cType lock-data)) 
          (cTokens-locked (at 'cTokens lock-data)) 
          (dollar-value-of-payment (* (at 'payment-token-price calculations) payment-token-amount))
          (new-days-afforded (str-to-int (drop -2 (format "{}" [(round (/ dollar-value-of-payment (at 'cost-per-day calculations)) 0)]))))
          (end-time (add-time (at 'end-time lock-data) (days new-days-afforded)))
          (kWatts-per-day (/ (chips-presale.calculate-kWatts-required cTokens-locked cType) 30))
          (new-kWatts-required (round (* kWatts-per-day new-days-afforded) 4))
          (orders-count-string (int-to-str 10 (get-count ORDERS_COUNT)))
          ; end here
          (kwatt:module{fungible-v2} (at 'fungible (read currency-table "kWATT")))
        )
        (enforce (< (at "block-time" (chain-data)) (at 'end-time lock-data)) "You cannot extend a lock that has expired, please start a new lock")
        (enforce (>= new-days-afforded 1) "Smallest extension is 1 day")
        (if (= "KDA" payment-token)
          (coin.transfer account CHIPS_BANK payment-token-amount)
          (with-capability (ADMIN_OR_BRIDGE caller)
            "bridge"
          )
        )
        (update locks-table lock-id
          { "duration" : (+ (at 'duration lock-data) new-days-afforded)
          , "end-time" : end-time
          , "kWatts" : (+ (at 'kWatts lock-data) new-kWatts-required) } )
        (with-capability (PRIVATE)
          (update-transaction-table orders-count-string account payment-token payment-token-amount
            (at 'payment-token-price calculations) 0.0 0.0 new-kWatts-required dollar-value-of-payment "none" lock-id end-time)
          (mint-kWATT CHIPS_LOCKED_WALLET new-kWatts-required)
          (update-tvl kWATT_TVL new-kWatts-required))
        (format "Rental extended by {} days and will end on {}. Locked {} kWatts." [new-days-afforded end-time new-kWatts-required])
      )
    )
  )

  (defun gather-extend-expense2 (account:string payment-token:string use-kWATTs:bool lock-id:string extend-by-days:integer)
    (let* (
        (lock-data (read locks-table lock-id))
        (cType (at 'cType lock-data))
        (cTokens-locked (at 'cTokens lock-data))
        (duration-discount (if (> extend-by-days 365) 0.05 (* (/ (- extend-by-days 90) 275.0) 0.05)))
        (payment-token-price (chips-oracle.get-current-price payment-token))
        (user-kWATT-discount (get-user-applied-discount account 0.0)) ;% discount
        (user-kmc-discount (* 0.125 (* 0.005 (chips-presale.get-kmc-nft-count account)) )) ;1/200 for a max of 0.125% discount
        (combined-user-discount (+ (if (> user-kmc-discount 0.125) 0.125 user-kmc-discount) user-kWATT-discount)) ; 12.5%. max
        (kWATTs-per-day-per-cToken (/ (chips-presale.calculate-kWatts-required 1.0 cType) 30))
        (total-kWATTs-required-per-cToken (round (* extend-by-days kWATTs-per-day-per-cToken) 6))
        (kWATT-price (chips-oracle.get-current-price "kWATT"))
        (kWATT-adjusted-price (if (= cType "cBTC") 0.07 kWATT-price))
        (cost-per-kWATT (* kWATT-adjusted-price (- 1 (+ (+ combined-user-discount duration-discount) 0.03))))
        (adjusted-cost-per-kWATT (if (< cost-per-kWATT 0.061) 0.061 cost-per-kWATT)) ;0.059 absolute minimum including kWATT promos
        (kWATT-cost-per-cToken (* adjusted-cost-per-kWATT total-kWATTs-required-per-cToken ))
        (kWATT-cost (round (* cTokens-locked kWATT-cost-per-cToken) 8))
        (purchase-details (chips-presale.get-kwatts-and-power cTokens-locked cType))
        (hashrate (at 'power purchase-details))
        (rewards (at 'rewards purchase-details))
        (total-kWATTs-required  (* total-kWATTs-required-per-cToken cTokens-locked))
      )
      { "total-cost" : kWATT-cost
      , "total-kWATTs-required" : total-kWATTs-required
      , "kWATTs-per-day" : (/ total-kWATTs-required extend-by-days)
      , "payment-tokens-needed" : (/ kWATT-cost payment-token-price)
      , "cost-per-kWATT" : (round adjusted-cost-per-kWATT 4)
      , "cost-per-day" : (round (/ kWATT-cost extend-by-days) 8)
      , "duration-discount-precalc" : (round duration-discount 8)
      , "lock-data" : lock-data
      , "payment-token-price" : payment-token-price
      }
    )
  )

  (defun update-transaction-table (orders-count:string account:string payment-token:string payment-token-amount:decimal
    payment-token-price:decimal cTokens-sold:decimal cTokens-usd-price:decimal kWATTs-sold:decimal kWATT-cost:decimal
    cType:string lock-id:string end-time:time)
    (require-capability (PRIVATE))
    (insert transaction-table orders-count
      { "account" : account
      , "payment-token" : payment-token
      , "payment-token-amount" : payment-token-amount
      , "payment-token-price" : payment-token-price
      , "cTokens-sold" : cTokens-sold
      , "cTokens-usd-price" : cTokens-usd-price
      , "kWATTs-sold" : (round kWATTs-sold 6)
      , "kWATT-cost" : kWATT-cost
      , "cType" : cType
      , "date" : (at 'block-time (chain-data))
      , "lock-id" : lock-id
      , "end-time" : end-time })
      (increase-count ORDERS_COUNT)
  )

  (defun update-presale-referral (account:string dollar-value:decimal referrer:string)
    (require-capability (PRIVATE))
    (require-capability (CALL_POLICY_MODULES))
    (if (= "none" referrer)
      ""
      (with-capability (PRIVATE)
        (chips-presale.update-referral-chips account dollar-value false)
        (chips-presale.update-referral-chips referrer dollar-value true))
    )
  )

  (defun poll-balances (account:string)
    (round (+ (* 1.15 (+ (fold (+) 0.0  (zip (*)  (map (poll-balance account) ["cKDA" "cLTC" "cBTC"])
      (map (chips-oracle.get-current-price) ["cKDA" "cLTC" "cBTC"]) ))
    (total-locks-value account))) (* (chips-presale.read-promo-amount account) (* 0.25 (chips-oracle.get-current-price "kWATT")))) 2)
  )

  (defun poll-balance (account:string cType:string)
    (let*
      (
        (fung:module{fungible-v2} (at 'fungible (read currency-table cType)))
        (exists (try false (let ((ok true)) (fung::get-balance account)"" ok)))
      )
      (if (= exists true)
        (fung::get-balance account)
        0.0)
    )
  )

  (defun get-user-applied-discount (account:string dollar-value-of-payment:decimal)
    (let* (
        (wallet-value (poll-balances account))
        (combined-value (+ wallet-value dollar-value-of-payment))
        (raw-discount
          (if (<= combined-value 15000.0)
            (* (/ combined-value 15000.0) 0.03)
            (let* (
                (excess (- combined-value 15000.0))
                (scaling-factor (if (< (/ excess 90000.0) 1.0) (/ excess 90000.0) 1.0))
              )
              (+ 0.03 (* scaling-factor 0.06))
            )
          )
        )
      )
      (round raw-discount 4)
    )
  )

  (defun gather-purchase-details (account:string cType:string cToken-amount:decimal payment-token:string payment-token-amount:decimal rental-duration:integer)
    @doc "Returns how many cTokens and kWATTs the user will be purchasing for a specified dollar value"
    (let* (
        (payment-token-price (chips-oracle.get-current-price payment-token))
        (dollar-value-of-payment (* payment-token-price payment-token-amount))
        (user-kWATT-discount (get-user-applied-discount account dollar-value-of-payment)) ;% discount
        (user-kmc-discount (* 0.125 (* 0.005 (chips-presale.get-kmc-nft-count account)) )) ;1/200 for a max of 0.125% discount
        (combined-user-discount (+ (if (> user-kmc-discount 0.125) 0.125 user-kmc-discount) user-kWATT-discount)) ; 12.5%. max
        (kWATTs-per-day-per-cToken (/ (chips-presale.calculate-kWatts-required 1.0 cType) 30))
        (total-kWATTs-required-per-cToken (round (* rental-duration kWATTs-per-day-per-cToken) 6))
        (kWATT-price (chips-oracle.get-current-price "kWATT"))
        (kWATT-adjusted-price (if (= cType "cBTC") 0.07 kWATT-price))

        (kWATT3 (calc-kWATT-cost kWATT-adjusted-price combined-user-discount 90)) ;front-end calcs
        (kWATT6 (calc-kWATT-cost kWATT-adjusted-price combined-user-discount 180))
        (kWATT12 (calc-kWATT-cost kWATT-adjusted-price combined-user-discount 365))
        
        (cost-per-kWATT (calc-kWATT-cost kWATT-adjusted-price combined-user-discount rental-duration))
        (kWATT-cost-per-cToken (* cost-per-kWATT total-kWATTs-required-per-cToken ))
        (total-cost-per-cToken (+ (chips-oracle.get-current-price cType) kWATT-cost-per-cToken))
        ; if cToken-amount is greater than zero, all of the payment token is being applied to kWATTs.
        (cTokens-purchased (if (> cToken-amount 0.0) 0.0 (round (/ dollar-value-of-payment total-cost-per-cToken) 10)) )
        (total-cTokens-locked (+ cToken-amount cTokens-purchased))
        (kWATT-cost (round (* total-cTokens-locked kWATT-cost-per-cToken) 6))
        (purchase-details (chips-presale.get-kwatts-and-power total-cTokens-locked cType))
        (hashrate (at 'power purchase-details))
        (rewards (at 'rewards purchase-details))
      )
      { "cost-per-kWATT" : cost-per-kWATT
      , "kWATT3" : kWATT3
      , "kWATT6" : kWATT6
      , "kWATT12" : kWATT12
      , "cToken-cost" : (* (chips-oracle.get-current-price cType) total-cTokens-locked)
      , "user-kWATT-discount" : combined-user-discount
      , "total-kWATT-cost" : kWATT-cost
      , "required-payment-token-amount-for-kWATTs" : (round (/ kWATT-cost payment-token-price) 6)
      , "total-kWATTs-required" : (* total-kWATTs-required-per-cToken total-cTokens-locked)
      , "cTokens-purchased" : cTokens-purchased
      , "cTokens-usd-price" : (chips-oracle.get-current-price cType)
      , "hashrate" : hashrate
      , "per-month-rewards" : rewards
      , "payment-token-price" : payment-token-price
      , "total-cTokens-locked" : total-cTokens-locked
      , "dollar-value-of-payment" : dollar-value-of-payment }
    )
  )

  (defun gather-purchase-details2 (account:string cType:string cToken-amount:decimal payment-token:string payment-token-amount:decimal rental-duration:integer)
    (let* (
        (aprs (get-apr-details cType))
      )
      (+ { "APR3" : (at 'APR3 aprs)
      , "APR6" : (at 'APR6 aprs)
      , "APR12" : (at 'APR12 aprs) } (gather-purchase-details account cType cToken-amount payment-token payment-token-amount rental-duration))
    )
  )

  (defun get-apr-details (cType:string)
    (let* (
      (APR3 (cond
                    ((= "cKDA" cType) 12.96)
                    ((= "cLTC" cType) 37.6)
                    ((= "cBTC" cType) 36.16)
                    0.0))
      (APR6 (cond
                    ((= "cKDA" cType) 16.42)
                    ((= "cLTC" cType) 41.00)
                    ((= "cBTC" cType) 40.38)
                    0.0))
      (APR12 (cond
                    ((= "cKDA" cType) 26.90)
                    ((= "cLTC" cType) 47.00)
                    ((= "cBTC" cType) 45.14)
                    0.0))
      )
      { "APR3" : APR3, "APR6" : APR6, "APR12" : APR12}
    )
  )

  (defun calc-kWATT-cost (kWATT-adjusted-price:decimal combined-user-discount:decimal rental-duration:integer)
    (let* (
        (flat-discount 0.00)
        (duration-discount (* (/ (- rental-duration 90) 275.0) 0.05))
        (cost-per-kWATT (* kWATT-adjusted-price (- 1 (+ (+ combined-user-discount duration-discount) flat-discount))))
        (adjusted-cost-per-kWATT (if (< cost-per-kWATT 0.061) 0.061 cost-per-kWATT)) ;0.061 absolute minimum including kWATT promos
      )
      (round adjusted-cost-per-kWATT 4)
    )
  )

  (defun order-work (cType:string cToken-amount:decimal)
    @doc "Transfers kWATTs and cTokens from the chips bank or a user wallet to the locked wallet"
    (require-capability (PRIVATE))
    (enforce (contains cType ["cKDA" "cLTC" "cBTC" "cKAS" "cALPH"]) (format "{}: This type of cToken is not supported" [cType]))
    (enforce (> cToken-amount 0.0) "cToken amount must be positive")
    (let*
        (
          (fung:module{fungible-v2} (at 'fungible (read currency-table cType)))
          (bank-cToken-balance (fung::get-balance CHIPS_BANK))
        )
        (enforce (>= bank-cToken-balance cToken-amount)
            (format "Chips does not have enough stock of {} hashrate, only {} cTokens remain and you are trying to purchase {} cTokens"
              [cType bank-cToken-balance cToken-amount]))
        (with-capability (BANK_DEBIT)
          (install-capability (fung::TRANSFER CHIPS_BANK CHIPS_LOCKED_WALLET cToken-amount))
          (fung::transfer CHIPS_BANK CHIPS_LOCKED_WALLET cToken-amount)
        )
    )
  )

  (defun withdraw-from-lock (account:string external-account:[string] lock-id:string )
    @doc "Allows a user to end their lock early. This function applies a penalty based on how much time remains in the lock"
    (with-capability (LOCK_OWNER account lock-id)
      (let* (
          (lock-data (read locks-table lock-id))
          (end-time (at 'end-time lock-data))
          (claim-message (claim-multiple account external-account [(at 'lock-number lock-data)]))
          (withdraw-details (withdraw-coins account lock-data end-time))
        )
        (with-capability (PRIVATE)
          (close-out-lock lock-id lock-data account))
        (emit-event (WITHDRAW_FROM_LOCK account lock-id (at 0 withdraw-details) (at 'cType lock-data) (at 1 withdraw-details) 0.0 0.0))
        (format "Withdrew {} cTokens and {} kWATTs. Claimed remaining mining rewards: {} " [(at 0 withdraw-details) (at 1 withdraw-details) claim-message])
      )
    )
  )

  (defun withdraw-coins (account:string lock-data:object end-time:time)
    (require-capability (PRIVATE))
    (let* (
        (cTokens (at 'cTokens lock-data))
        (kWatts (at 'kWatts lock-data))
        (time-passed (diff-time (at 'block-time (chain-data)) (at 'start-time lock-data)))
        (percent-time-passed (round (/ time-passed (days (at 'duration lock-data))) 4))
        (percent-time-remaining (if (>= percent-time-passed 1.0) 0.0 (- 1 percent-time-passed)))
        (withdrawable-kWatts (round (* (- 1 (get-value EARLY_WITHDRAW_PENALTY)) (* kWatts percent-time-remaining)) 4) ) ;you lose x% of whatever kWatts remain
        (total-cToken-degradation (if (= (at 'degradation lock-data) true) (* 0.2 (/ time-passed (days 365))) 0.0))
        (withdrawable-cToken cTokens) ; (round (* cTokens (- 1 total-cToken-degradation)) 4)) ; no degradation until january 2025
        (kwatt:module{fungible-v2} (at 'fungible (read currency-table "kWATT")))
        (cToken-fungible:module{fungible-v2} (at 'fungible (read currency-table (at 'cType lock-data))))
      )
      (with-capability (BANK_DEBIT)
        (install-capability (cToken-fungible::TRANSFER CHIPS_LOCKED_WALLET account withdrawable-cToken))
        (cToken-fungible::transfer-create CHIPS_LOCKED_WALLET account (at "guard" (coin.details account)) withdrawable-cToken)
        (if (> 0.0 withdrawable-kWatts)
          [ (install-capability (kwatt::TRANSFER CHIPS_LOCKED_WALLET account withdrawable-kWatts))
            (kwatt::transfer-create CHIPS_LOCKED_WALLET account (at "guard" (coin.details account)) withdrawable-kWatts)]
            "no kWATTs to withdraw")
      )

      (update-tvl kWATT_TVL (- 1 kWatts))
      (update-tvl (format "{}-{}" [(at 'coin lock-data) LOCKED]) (- 1 cTokens))
      [withdrawable-cToken withdrawable-kWatts]
    )
  )

  (defun close-out-lock (lock-id:string lock-data:object account:string)
    @doc "Sets all of the variables for a lock to a baseline after a user withdraws from a lock, or claims from an expired lock."
    (require-capability (PRIVATE))
    (let* (
        (current-mined-index (get-recent (at 'coin lock-data)))
        (change-index (get-count (format "{}-change-index" [(at 'coin lock-data)])))
        (existing-user-locks (get-existing-user-locks account))
      )
      (update locks-table lock-id
        { "mined-index" : current-mined-index
        , "change-index" : change-index })
      (update user-locks-table account
        { "locks" : (filter (!= lock-id) existing-user-locks)})
      (if (= false (at 'released lock-data))
        (update locks-table lock-id
            { "released" : true })
        ""
      )
    )
  )

  (defun create-lock (kWatts:decimal cToken-amount:decimal account:string rental-duration:integer hashrate:decimal reward-coin:string cType:string previously-mined:decimal)
    (require-capability (PRIVATE))
    (let (
        (total-locks (int-to-str 10 (get-count TOTAL_LOCKS)))
        (start-time (at "block-time" (chain-data)))
        (existing-user-locks (get-existing-user-locks account))
      )
      (insert locks-table total-locks
        { "chip-ids" : []
        , "account" : account
        , "start-time": start-time
        , "duration" : rental-duration
        , "end-time" : (time (format-time "%Y-%m-%dT%H:00:00Z" (add-time start-time (days rental-duration))))
        , "coin" : reward-coin ;is KDA, LTC, BTC, etc.
        , "cType" : cType
        , "kWatts": kWatts
        , "cTokens" : cToken-amount
        , "lock-number" : total-locks
        , "released" : false
        , "mined-index" : (get-recent reward-coin)
        , "change-index" : (get-count (format "{}-change-index" [reward-coin]))
        , "hashrate" : hashrate
        , "coins-owed" : previously-mined
        , "degradation" : false
        , "extra" : {} }
      )
      (update-tvl (format "{}-{}" [reward-coin LOCKED]) cToken-amount)
      (update-tvl kWATT_TVL kWatts)
      (write user-locks-table account
        { "locks" : (+ [total-locks] existing-user-locks) })
      (increase-count TOTAL_LOCKS)
      (format "{} Rental started with {} TH/s (*0.1 GH/s for Scrypt). This rental will last {} days and will use {} kWATTs. Go to the My Earnings tab to see your rewards grow!"
        [total-locks hashrate rental-duration kWatts])
    )
  )

  (defun update-tvl (coin-key:string change:decimal)
    (require-capability (PRIVATE))
    (let (
        (current-tvl (get-value coin-key))
      )
      (update decimals-table coin-key { "value" : (+ current-tvl change) })
    )
  )

  (defun iterate-over-solution (solution-length:integer solution:list rentable-tokens:list)
    (enforce (= solution-length (length rentable-tokens)) "Lists are not the same length, blame Jad and contact admins please")
    (fold (+) [] (map (split-list solution rentable-tokens) (enumerate 0 (- solution-length 1)) ))
  )

  (defun split-list (solution:list rentable-tokens:list iteration:integer)
    (let* (
        (num-to-select (at 'count (at iteration solution))) ;num-to-select is 2 for primary
        (tokens-to-select-from (at 'rentable-tokens (at iteration rentable-tokens))) ; 1
        (result (if (>= (length tokens-to-select-from) num-to-select) (take num-to-select tokens-to-select-from) [""]))
      )
      result
    )
  )

  (defun get-mineable-coins ()
    @doc "Returns all coins that the application supports"
    (read mineable-coins-list-table SUPPORTED_COINS)
  )

  (defun get-existing-user-locks (account:string)
    (with-default-read user-locks-table account
      { "locks": [] }
      { "locks" := locks }
      locks)
  )

  (defun get-user-locks-data (account:string)
    @doc "Returns the data of all active locks that a user has"
    (map (read-lock) (get-existing-user-locks account))
  )

  (defun total-locks-value (account:string)
    @doc "Sum up cToken balances * current price for cBTC, cLTC, and cKDA."
    (let (
      (tracked ["cBTC" "cLTC" "cKDA"])
      (locks (get-user-locks-data account))
      )
      (fold (+) 0.0
        (map
          (lambda (lock)
            (let* ((ctype   (at 'cType lock))
                   (balance (at 'cTokens lock)))
              (if (contains ctype tracked)
                  (* balance (chips-oracle.get-current-price ctype))
                  0.0)))
          locks)))
    )

  (defun get-all-sales-data ()
    (select transaction-table (where "cType" (!= "hello")))
  )

  (defun get-homepage-info ()
    { "highest-apr" : 47.44
    , "TVL" : (at 'usd-tvl (get-tvl))
    , "Active Miners" : 72
    , "total-mining-contracts" : (get-count TOTAL_LOCKS)
    , "total-kda-mined" : (at 'mined (read-mined (get-recent "KDA")))
    , "total btc-mined" : (at 'mined (read-mined (get-recent "BTC")))
    , "rewards-claim-count" : (+ (get-count "external-claim-count") (get-count "claim-count"))}
  )

  (defun get-tvl ()
    (let*
      (
        (kWATT-fung:module{fungible-v2} (at 'fungible (read currency-table "kWATT")))
        (kda-price (at 'value (n_bfb76eab37bf8c84359d6552a1d96a309e030b71.dia-oracle.get-value "KDA/USD")))
        (cToken-details (map (get-card-details) ["KDA" "LTC" "BTC"]) )
        (cToken-TVL (fold (+) 0.0 (map (at 'TVL) cToken-details)) )
        (kWATTs-locked (kWATT-fung::get-balance "chips-locked-wallet"))
        (kWATT-value (chips-oracle.get-current-price "kWATT"))
        (kWATT-TVL (* kWATT-value kWATTs-locked))
        (chips-usd-tvl (+ kWATT-TVL cToken-TVL))
        (chips-kda-tvl (/ chips-usd-tvl kda-price))
      )
      {"coin" : (round chips-kda-tvl 6), "usd-tvl" : (round chips-usd-tvl 2)}
    )
  )

  (defun change-rental-name (account:string lock-id:string name:string)
    @doc "Allows a user to set a name for their lock to be displayed on the website"
    (with-capability (LOCK_OWNER account lock-id)
      (write lock-name-table lock-id
        { "name" : name }
      )
    )
  )

  (defun sum-claims (lock-id:string coin-type:string)
    "Returns the total-claimed and weighted-average coin-price for the given lock-id and coin-type."
    (let* (
           (records
             (if (= "KDA" coin-type)
               (select claim-table
                       (where "lock-number" (= lock-id)))
               (distinct
                 (select external-claim-table
                         (and? (where "lock-number" (= lock-id))
                               (where "coin"         (= coin-type)))))))
           (total-claimed
             (fold (+) 0.0
               (map (lambda (r) (at 'claimed r)) records)))
           (weighted-sum
             (fold (+) 0.0
               (map (lambda (r)
                      (* (at 'claimed r) (at 'coin-price r)))
                    records)))
           (avg-price
             (if (> total-claimed 0.0)
               (/ weighted-sum total-claimed)
               0.0))
          )
      { "total-claimed": total-claimed
      , "coin-price":    avg-price          })
  )

  (defun pretty-read-all-user-locks (account:string)
    @doc "Reads all locks of a particular user with front-end prettied output"
    (+ (map (pretty-read-lock) (get-existing-user-locks account))
    (map
      (lambda (coin)
        (let* ((recent       (get-recent coin))
               (mined        (read-mined recent))
               (total-hash   (at 'total-hashrate mined)))
          { "coin":           coin
          , "total-hashrate": total-hash }))
      ["KDA" "BTC" "LTC"]))
  )

  (defun pretty-read-lock (lock-id:string)
    @doc "Front-end function, reads a lock and outputs an object with each column of data"
    (let* (
        (lock-data (read-lock lock-id))
        (coin (at 'coin lock-data))
        (kWatts-value (* (at 'kWatts lock-data) (chips-oracle.get-current-price "kWATT") ))
        (cToken-value (* (at 'cTokens lock-data) (chips-oracle.get-current-price (format "c{}" [coin]))))
        (rental-value (+ kWatts-value cToken-value))
        (powered-by (cond
                      ((= "LTC" coin) "Bitmain Antminer L9")
                      ((= "KDA" coin) "Bitmain Antminer KA3")
                      ((= "BTC" coin) "Bitmain S19k Pro")
                      "Bitmain IceRiver Pro"))
        (daily-income (chips-presale.get-kwatts-and-power (at 'cTokens lock-data) (format "c{}" [coin])))
        (claimed (sum-claims lock-id coin))
        (claimed2 (if (= coin "LTC") (sum-claims lock-id "DOGE") { "total-claimed" : 0.0, "coin-price" : 0.0 }))

        (unclaimed (get-mined-for-lock lock-id coin))
        (unclaimed2 (if (= "LTC" coin) (get-mined-for-lock lock-id "DOGE") 0.0) )
        (total-hashrate (at 'total-hashrate (read-mined (get-recent coin))))
        (chips-total-hashrate (if (= "BTC" coin) (- total-hashrate 500.00000) total-hashrate))
        (exists (try false (let ((ok true)) (read lock-name-table lock-id) "" ok)))
        (lock-name (if (= exists true)
            (at 'name (read lock-name-table lock-id))
            ""))
      )
      { "daily-kWATT-consumption" : (/ (at 'kWatts daily-income) 0.08)
      , "lock-id" : lock-id
      , "apr" : 28.6
      , "powered-by" : powered-by
      , "daily-income" : (at 'rewards daily-income)
      , "hashrate" : (at 'hashrate lock-data)
      , "locked" : (at 'cTokens lock-data)
      , "end-time" : (at 'end-time lock-data)
      , "rental-usd-value" : (round rental-value 2)
      , "claimed" : (at 'total-claimed claimed)
      , "claimed2" : (at 'total-claimed claimed2)
      , "unclaimed" : unclaimed
      , "unclaimed2" : unclaimed2
      , "coin" : coin
      , "lock-name" : lock-name
      , "start-time" : (at 'start-time lock-data) 
      , "chips-total-hashrate" : chips-total-hashrate 
      , "claimed-usd-value" : (* (at 'coin-price claimed) (at 'total-claimed claimed))
      , "claimed-usd-value2" : (* (at 'coin-price claimed2) (at 'total-claimed claimed2))
    }
      )
  )

  (defun read-lock (lock-id:string)
    (read locks-table lock-id)
  )

  (defun mint-kWATT (receiver:string amount:decimal)
    (require-capability (PRIVATE))
    (let* (
        (previous-kWatt-minted (get-value "kWatt-minted"))
        (kwatt:module{kwatt-v1} (at 'fungible (read currency-table "kWATT")))
      )
      (update decimals-table "kWatt-minted" { "value" : (+ amount previous-kWatt-minted) })
      (with-capability (EXTERNAL_MINT)
        (install-capability (kwatt::MINT CHIPS_LOCKED_WALLET amount))
        (kwatt::mint receiver amount))
    )
  )

  (defun get-marketplace-details ()
    { "card-details" : (map (get-card-details) (filter (!= "DOGE") (at 'coins (get-mineable-coins))))
    , "total-mined" :  (map (get-total-mined) (at 'coins (get-mineable-coins))) }
  )

  (defun get-total-mined (coin:string)
    (let* (
        (total-mined (at 'mined (read-mined (get-recent coin))))
      )
      { "coin" : coin
      , "total-mined" : total-mined
      , "dollar-value" : (* total-mined (chips-oracle.get-current-price coin))}
    )
  )

  (defun get-card-details (coin:string)
    (let* (
        (fung:module{fungible-v2} (at 'fungible (read currency-table (+ "c" coin))))
        (bank-cToken-balance (fung::get-balance CHIPS_BANK))
        (locked-bank-balance (fung::get-balance CHIPS_LOCKED_WALLET))
        (TVL (* locked-bank-balance (chips-oracle.get-current-price (+ "c" coin))))
        (apr (get-apr-details (+ "c" coin)))
      )
      { "coin" : coin
      , "APR" : (at 'APR12 apr)
      , "hashrate-available" : (if (= coin "LTC") (/ (round bank-cToken-balance 6) 10) (round bank-cToken-balance 6))
      , "hashrate-locked" : (if (= coin "LTC") (/ (round locked-bank-balance 6) 10) (round locked-bank-balance 6)) ; todo make this more accurate (cTokens degrade)
      , "TVL" : (round TVL 2)}
    )
  )

  (defun admin-withdraw-from-bank (fung:module{fungible-v2} amount:decimal withdraw-from:string)
    (with-capability (ADMIN)
    (with-capability (BANK_DEBIT)
      (install-capability (fung::TRANSFER withdraw-from ADMIN_ADDRESS amount))
      (fung::transfer withdraw-from ADMIN_ADDRESS amount)
    ))
  )

  (defun read-mined (mined-index:string)
    @doc "Allows anybody to read the amount of a particular coin mined at any index"
    (read mined-table mined-index)
  )

  (defun set-count (key:string amount:integer)
    (update counts-table key
      { "count" : amount })
  )

  (defun get-count (key:string)
    @doc "Gets the count for a key"
    (at "count" (read counts-table key ['count]))
  )

  (defun increase-count (key:string)
    (require-capability (PRIVATE))
    (update counts-table key {"count": (+ 1 (get-count key))})
  )

  (defun get-value (key:string )
    (at 'value (read decimals-table key))
  )

  (defun set-value (key:string value:decimal)
    (with-capability (ADMIN)
    (update decimals-table key
      { "value": value})
    )
  )

  (defun get-mined-keys ()
    (keys mined-table)
  )

  (defun get-recent (key:string)
    (at 'recent (read recent-mined-key-table key))
  )

  (defun admin-extend-rental (lock-id:string extension-amount:integer caller:string)
    @doc "Allows the admin to extend a users pre-existing rental for giveaways and other purposes"
    (with-capability (ADMIN_OR_BRIDGE caller)
      (let* ((end-time (at 'end-time (read locks-table lock-id))))
        (update locks-table lock-id { "end-time" : (add-time end-time (days extension-amount)) }))
    )
  )

  (defun create-dummy-rental (coin:string hashrate:decimal cType:string)
    @doc "Allows for historic tracking of APR with a fake rental"
    (with-capability (PRIVATE)
    (let* (
        (reward-coin (drop 1 cType))
        (start-time (at "block-time" (chain-data)))
      )
      (insert locks-table reward-coin
        { "chip-ids" : []
        , "account" : ADMIN_ADDRESS
        , "start-time": start-time
        , "duration" : 30000
        , "end-time" : (time (format-time "%Y-%m-%dT%H:00:00Z" (add-time start-time (days 30000))))
        , "coin" : reward-coin ;is KDA, LTC, BTC, etc.
        , "cType" : cType
        , "kWatts": 100.0
        , "cTokens" : 1.0
        , "lock-number" : reward-coin
        , "released" : false
        , "mined-index" : (get-recent reward-coin)
        , "change-index" : (get-count (format "{}-change-index" [reward-coin]))
        , "hashrate" : hashrate
        , "coins-owed" : 0.0
        , "degradation" : false
        , "extra" : {} }
      )
    ))
  )

  (defun create-simple-user-guard (account:string amount:decimal fungible:module{fungible-v2})
    (with-capability (ADMIN)
      (fungible::transfer-create ADMIN_ADDRESS account
        (create-BANK_DEBIT-guard) amount) )
  )

  (defun require-BANK_DEBIT ()
    (require-capability (BANK_DEBIT))
  )

  (defun create-BANK_DEBIT-guard ()
    (create-user-guard (require-BANK_DEBIT))
  )

  (defun reg-chips-presale ()
    (with-capability (ADMIN)
        (chips-presale.register-guard (create-capability-guard (CALL_POLICY_MODULES)))
    )
  )

  (defun reg-kWatt ()
    (with-capability (ADMIN)
      (kWATT.register-guard (create-capability-guard (EXTERNAL_MINT))))
  )

  (defcap CALL_POLICY_MODULES () true )

  (defcap EXTERNAL_MINT () true )

  (defcap ACCOUNT_GUARD (account:string)
    @doc "Verifies account meets format and belongs to caller"
    (enforce-guard
        (at "guard" (coin.details account))
    )
  )

  (defcap CLAIM (account:string lock-id:string)
    (compose-capability (LOCK_OWNER account lock-id))
    (compose-capability (BANK_DEBIT))
  )

  (defcap LOCK_OWNER (account:string lock-id:string )
    (let (
        (owner (at 'account (read locks-table lock-id)))
      )
      (enforce (= account owner) "You are not the owner of this lock. Permission denied.")
    )
    (compose-capability (ACCOUNT_GUARD account))
    (compose-capability (PRIVATE))
  )

  (defcap WITHDRAW_FROM_LOCK (account:string lock-id:string cToken-amount:decimal cToken:string kWATT-amount:decimal burned-cTokens:decimal burned-kWATTs:decimal)
    @doc "Emitted event when a lock is withdrawn from "
    @event true
  )

  (defcap PRIVATE () true )

  (defcap ADMIN() ; Used for admin functions
      @doc "Only allows admin to call these"
    ;   true
       (enforce-keyset ADMIN_KEYSET)
       (compose-capability (PRIVATE))
       (compose-capability (ACCOUNT_GUARD ADMIN_ADDRESS))
  )

  (defcap ADMIN_OR_BRIDGE (account:string)
    (compose-capability (ACCOUNT_GUARD account))
    (compose-capability (PRIVATE))
    (enforce-one "admin or discord" [(enforce (= account ADMIN_ADDRESS) "") (enforce (= account BRIDGE_ORACLE_ADDRESS)"")])
  )

  (defcap GOVERNANCE()
      @doc "Only allows admin to call these"
      (enforce-keyset ADMIN_KEYSET)
  )

  (defcap BANK_DEBIT () true)
)