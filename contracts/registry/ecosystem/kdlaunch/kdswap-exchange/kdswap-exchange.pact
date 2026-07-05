(module kdswap-exchange GOVERNANCE

  @model
  [
   ;; TODO: update the FV code and make it work with latest pact

   ;; prop-pairs-write-guard
   ;; guard is never enforced, but this allows enumeration of
   ;; every write, and forward security for newly-added functions.
   (property
    (forall (k:string)
     (when (row-written pairs k)
       (row-enforced pairs 'guard k)))
    { 'except:
      [ create-pair      ;; unguarded (insert semantics)
        add-liquidity    ;; prop-increase-liquidity
        remove-liquidity ;; prop-decrease-liquidity
        swap-exact-in    ;; prop-increase-liquidity
        swap-exact-out   ;; prop-increase-liquidity
        swap             ;; prop-increase-liquidity
        swap-pair        ;; PRIVATE
        swap-alloc       ;; PRIVATE
        update-reserves  ;; PRIVATE
      ] } )


   ;;prop-increase-liquidity
   ;;computes constant-product variance
   (defproperty increase-liquidity
     ( amount0:decimal
       amount1:decimal )
    (forall (k:string)
     (when (row-written pairs k)
      (<= (* (at 'reserve (at 'leg0 (read k)))
             (at 'reserve (at 'leg1 (read k))))
          (* (+ amount0
               (at 'reserve (at 'leg0 (read k))))
             (+ amount1
               (at 'reserve (at 'leg1 (read k)))))))))

   ;;prop-decrease-liquidity
   ;;computes constant-product variance
   (defproperty decrease-liquidity
     ( amount0:decimal
       amount1:decimal )
    (forall (k:string)
     (when (row-written pairs k)
      (>= (* (at 'reserve (at 'leg0 (read k)))
             (at 'reserve (at 'leg1 (read k))))
          (* (+ amount0
               (at 'reserve (at 'leg0 (read k))))
             (+ amount1
               (at 'reserve (at 'leg1 (read k)))))))))

  ]

  (defconst ADMIN-KS:string "n_e20f61f0aa3b384abde5c1be9503009df1747050.kdswap-contract-admin")

  (defcap GOVERNANCE ()
    (enforce-guard ADMIN-KS))

  (defcap CREATE_PAIR
    ( token0:module{fungible-v2}
      token1:module{fungible-v2}
      key:string
      account:string )
    " Pair-created event for TOKEN0 and TOKEN1 pairs with KEY liquidity token \
    \ and ACCOUNT on leg tokens."
    @event
    ;; dupes checked in 'get-pair-create'
    true)

  (defcap LIQUIDITY_RESERVE
      (pair-key:string)
    true)

  (defcap SWAP-OPEN:bool (pair:string)
    (with-default-read pair-locks-table pair {"open-date": (at 'block-time (chain-data))} {"open-date":= openDate}
      (let
        (
          (secondsToOpen (diff-time (at 'block-time (chain-data)) openDate ))
        )

      (enforce (>= secondsToOpen 0.0) "SWAP IS NOT OPEN YET"))
    )
  )

  ; This capability is used for being safe and trying to prevent reentrancy issues
  ;; by locking each pair inside a swap/add-liquidity/remove-liquidity function.
  ;; Because pact is Turing incomplete, and recursion is disallowed and detected,
  ;; we have not been able to produce a PoC of what a reetrancy exploit would look
  ;; like, since pact detects the recursion attempt (even if it's not infinite) and
  ;; prevents the code from running.
  (defcap MUTEX ()
    "Private defcap for obtaining pair mutex."
    true)

  (defun set-pair-open-date (pair:string new-open-date:time)
    (with-capability (GOVERNANCE)
    (write pair-locks-table pair {"pair":pair,  "open-date":new-open-date})
    )
  )

  (defun get-pair-open-date:time
    (pair:string)
    (at 'open-date (read pair-locks-table pair))
  )

  (defun enforce-liquidity-reserve:bool
      (key:string)
    (require-capability (LIQUIDITY_RESERVE key)))

  (defun create-liquidity-guard:guard
      (key:string)
    (create-user-guard (enforce-liquidity-reserve key)))

  (defcap PRIVATE_RESERVE
      (pair-key:string token:string)
    true)

  (defun enforce-private-reserve:bool
      (pair-key:string token:module{fungible-v2})
    (require-capability (PRIVATE_RESERVE pair-key (format-token token))))

  (defun create-reserve-guard:guard
      (pair-key:string token:module{fungible-v2})
    (create-user-guard (enforce-private-reserve pair-key token)))

  (defun enforce-issuing:bool
      ()
    (require-capability (ISSUING)))

  (defun create-issuing-guard:guard
      ()
    (create-user-guard (enforce-issuing)))

  ;; this guard always fails, we only use it for create-pair to store in the guard field of the pairs table
  ;; that field is now unused, and should not be used going forward
  (defun enforce-null:bool
      ()
    false)
  (defun create-null-guard:guard
      ()
    (create-user-guard (enforce-null)))

  (defcap ISSUING ()
    "Private defcap for issuing operations."
    true)

  (defcap SWAPPING ()
    "Private defcap for swapping operations."
    true)

  (defcap SWAP
    ( sender:string
      receiver:string
      in:decimal
      token-in:module{fungible-v2}
      out:decimal
      token-out:module{fungible-v2}
    )
    " Swap event debiting IN of TOKEN-IN from SENDER \
    \ for OUT of TOKEN-OUT on RECEIVER."
    @event
    true
  )

  (defcap UPDATE
    ( pair:string
      reserve0:decimal
      reserve1:decimal
    )
    "Private defcap updating reserves for PAIR to RESERVE0 and RESERVE1."
    @event
    true
  )

  (defschema leg
    token:module{fungible-v2}
    reserve:decimal
    )

  (defschema pair
    leg0:object{leg}
    leg1:object{leg}
    account:string
    guard:guard ;; NOTE: this is UNUSUED and OUTDATED
    mutex-locked:bool ;; whether the pair is currently locked or not (to prevent reentrancy)
    )

  (defschema pair-locks
    pair:string
    open-date:time
  )

  (deftable pairs:{pair})

  (deftable pair-locks-table:{pair-locks})

  (defconst MINIMUM_LIQUIDITY 0.1)

  (defun init ()
    (with-capability (ISSUING)
      (kdswap-exchange-tokens.init-issuer (create-issuing-guard)))
  )

  (defun get-lock-account-principal (key: string)
    (create-principal (create-liquidity-guard key))
  )

  (defun obtain-pair-mutex-lock:bool (pair:string)
    "Obtain reentrancy mutex for the given pair."
    (require-capability (MUTEX))
    (with-read pairs pair { 'mutex-locked := locked }
      (enforce (not locked) (format "Pair {} is locked" [pair]))
      (update pairs pair { 'mutex-locked: true })
      true))

  (defun release-pair-mutex-lock:bool (pair:string)
    "Release reentrancy mutex for the given pair."
    (require-capability (MUTEX))
    (with-read pairs pair { 'mutex-locked := locked }
      (enforce locked (format "Pair {} is unlocked" [pair]))
      (update pairs pair { 'mutex-locked: false })
      true))

  (defun get-pair:object{pair}
    ( tokenA:module{fungible-v2}
      tokenB:module{fungible-v2}
    )
    (read pairs (get-pair-key tokenA tokenB)))

  (defun pair-exists:bool
    ( tokenA:module{fungible-v2}
      tokenB:module{fungible-v2}
    )
    (with-default-read pairs
      (get-pair-key tokenA tokenB)
      { 'account: "" }
      { 'account := a }
      (> (length a) 0))
  )

  (defun update-reserves
    ( p:object{pair}
      pair-key:string
      reserve0:decimal
      reserve1:decimal
    )
    (require-capability (UPDATE pair-key reserve0 reserve1))
    (update pairs pair-key
      { 'leg0: { 'token: (at 'token (at 'leg0 p))
               , 'reserve: reserve0 }
      , 'leg1: { 'token: (at 'token (at 'leg1 p))
               , 'reserve: reserve1 }})
  )

  (defun add-liquidity:object
    ( tokenA:module{fungible-v2}
      tokenB:module{fungible-v2}
      amountADesired:decimal
      amountBDesired:decimal
      amountAMin:decimal
      amountBMin:decimal
      sender:string
      to:string
      to-guard:guard
    )
    (enforce (try false (tokenA::enforce-unit amountADesired)) "amountADesired precision mismatch")
    (enforce (try false (tokenB::enforce-unit amountBDesired)) "amountBDesired precision mismatch")
    (with-capability (MUTEX) ;; obtain the mutex lock
      (obtain-pair-mutex-lock (get-pair-key tokenA tokenB)))
    (let*
      ( (p (get-pair tokenA tokenB))
        (reserveA (reserve-for p tokenA))
        (reserveB (reserve-for p tokenB))
        (amounts
          (if (and (= reserveA 0.0) (= reserveB 0.0))
            [amountADesired amountBDesired]
            (let ((amountBOptimal (quote amountADesired reserveA reserveB)))
              (if (<= amountBOptimal amountBDesired)
                (let ((x (enforce (>= amountBOptimal amountBMin)
                           "add-liquidity: insufficient B amount")))
                  [amountADesired amountBOptimal])
                (let ((amountAOptimal (quote amountBDesired reserveB reserveA)))
                  (enforce (<= amountAOptimal amountADesired)
                    "add-liquidity: optimal A less than desired")
                  (enforce (>= amountAOptimal amountAMin)
                    "add-liquidity: insufficient A amount")
                  [amountAOptimal amountBDesired])))))
        (amountA (truncate tokenA (at 0 amounts)))
        (amountB (truncate tokenB (at 1 amounts)))
        (pair-account (at 'account p))
      )
      ;; transfer
      (tokenA::transfer sender pair-account amountA)
      (tokenB::transfer sender pair-account amountB)
      ;; mint
      (let*
        ( (token0:module{fungible-v2} (at 'token (at 'leg0 p)))
          (token1:module{fungible-v2} (at 'token (at 'leg1 p)))
          (balance0 (token0::get-balance pair-account))
          (balance1 (token1::get-balance pair-account))
          (reserve0 (at 'reserve (at 'leg0 p)))
          (reserve1 (at 'reserve (at 'leg1 p)))
          (amount0 (- balance0 reserve0))
          (amount1 (- balance1 reserve1))
          (key (get-pair-key tokenA tokenB))
          (totalSupply (kdswap-exchange-tokens.total-supply key))
          (liquidity (kdswap-exchange-tokens.truncate key
            (if (= totalSupply 0.0)
              (with-capability (ISSUING)
                (mint key (get-lock-account-principal key) (create-liquidity-guard key) MINIMUM_LIQUIDITY)
                (- (sqrt (* amount0 amount1)) MINIMUM_LIQUIDITY))
              (let ((l0 (/ (* amount0 totalSupply) reserve0))
                    (l1 (/ (* amount1 totalSupply) reserve1))
                   )
                ;; need min, max
                (if (<= l0 l1) l0 l1)))))
        )
        (enforce (> liquidity 0.0) "mint: insufficient liquidity minted")
        (with-capability (ISSUING)
          (mint key to to-guard liquidity))
        (with-capability (UPDATE key balance0 balance1)
          (update-reserves p key balance0 balance1))
        ;; release the pair lock
        (with-capability (MUTEX)
          (release-pair-mutex-lock (get-pair-key tokenA tokenB)))
        ;; return the information to the user
        { "liquidity": liquidity
        , "supply": (kdswap-exchange-tokens.total-supply key)
        , "amount0": amount0
        , "amount1": amount1
        }
      )
    )
  )

  (defun mint (token:string to:string guard:guard amount:decimal)
    (require-capability (ISSUING))
    (install-capability (kdswap-exchange-tokens.MINT token to amount))
    (kdswap-exchange-tokens.mint token to guard amount)
  )

  (defun quote
    ( amountA:decimal
      reserveA:decimal
      reserveB:decimal
    )
    (enforce (> amountA 0.0) "quote: insufficient amount")
    (enforce (and (> reserveA 0.0) (> reserveB 0.0)) "quote: insufficient liquidity")
    (/ (* amountA reserveB) reserveA)
  )


  (defun remove-liquidity:object
    ( tokenA:module{fungible-v2}
      tokenB:module{fungible-v2}
      liquidity:decimal
      amountAMin:decimal
      amountBMin:decimal
      sender:string
      to:string
      to-guard:guard
    )
    "Removes liquidity from an existing pair. The `to` account specified will receive the tokens."
    (with-capability (MUTEX) ;; obtain the pair lock
      (obtain-pair-mutex-lock (get-pair-key tokenA tokenB)))
    (let* ( (p (get-pair tokenA tokenB))
            (pair-account (at 'account p))
            (pair-key (get-pair-key tokenA tokenB))
          )
      (kdswap-exchange-tokens.transfer pair-key sender pair-account liquidity)
      (let*
        ( (token0:module{fungible-v2} (at 'token (at 'leg0 p)))
          (token1:module{fungible-v2} (at 'token (at 'leg1 p)))
          (balance0 (token0::get-balance pair-account))
          (balance1 (token1::get-balance pair-account))
          (liquidity_ (kdswap-exchange-tokens.get-balance pair-key pair-account))
          (total-supply (kdswap-exchange-tokens.total-supply pair-key))
          (amount0 (truncate token0 (/ (* liquidity_ balance0) total-supply)))
          (amount1 (truncate token1 (/ (* liquidity_ balance1) total-supply)))
          (canon (is-canonical tokenA tokenB))
        )
        (enforce (and (> amount0 0.0) (> amount1 0.0))
          "remove-liquidity: insufficient liquidity burned")
        (enforce (>= (if canon amount0 amount1) amountAMin)
          "remove-liquidity: insufficient A amount")
        (enforce (>= (if canon amount1 amount0) amountBMin)
          "remove-liquidity: insufficient B amount")
        (with-capability (ISSUING)
          (with-capability (LIQUIDITY_RESERVE pair-key)
            (burn pair-key pair-account liquidity)))
        (install-capability (token0::TRANSFER pair-account to amount0))
        (with-capability (PRIVATE_RESERVE pair-key (format-token token0))
          (token0::transfer-create pair-account to to-guard amount0)
        )
        (install-capability (token1::TRANSFER pair-account to amount1))
        (with-capability (PRIVATE_RESERVE pair-key (format-token token1))
          (token1::transfer-create pair-account to to-guard amount1)
        )
        (let
          ( (token0-balance (token0::get-balance pair-account))
            (token1-balance (token1::get-balance pair-account)))
          (with-capability (UPDATE pair-key token0-balance token1-balance)
            (update-reserves p pair-key token0-balance token1-balance)))
        ;; release the pair lock
        (with-capability (MUTEX)
          (release-pair-mutex-lock (get-pair-key tokenA tokenB)))
        ;; return the withdrawn amounts
        { 'amount0: amount0
        , 'amount1: amount1
        }
      )
    )
  )

  (defun burn (token:string to:string amount:decimal)
    (require-capability (ISSUING))
    (install-capability (kdswap-exchange-tokens.BURN token to amount))
    (kdswap-exchange-tokens.burn token to amount)
  )

  (defschema alloc
    token-out:module{fungible-v2}
    token-in:module{fungible-v2}
    out:decimal
    in:decimal
    idx:integer
    pair:object{pair}
    path:[module{fungible-v2}]
  )

  (defun swap-exact-in
    ( amountIn:decimal
      amountOutMin:decimal
      path:[module{fungible-v2}]
      sender:string
      to:string
      to-guard:guard
    )
    (enforce (>= (length path) 2) "swap-exact-in: invalid path")
    ;; fold over tail of path with dummy first value to compute outputs
    ;; assembles allocs in reverse
    (let*
      ( (p0 (get-pair (at 0 path) (at 1 path)))
        (allocs
          (fold (compute-out)
            [ { 'token-out: (at 0 path)
              , 'token-in: (at 1 path)
              , 'out: amountIn
              , 'in: 0.0
              , 'idx: 0
              , 'pair: p0
              , 'path: path
              }]
            (drop 1 path)))
      )
      (enforce (>= (at 'out (at 0 allocs)) amountOutMin)
        "swap-exact-in: insufficient output amount")
      ;; initial dummy is correct for initial transfer
      (with-capability (SWAPPING)
        (swap-pair sender to to-guard (reverse allocs)))
    )
  )

  (defconst FEE 0.003)

  (defun compute-out
    ( allocs:[object{alloc}]
      token-out:module{fungible-v2}
    )
    (let*
      ( (head:object{alloc} (at 0 allocs))
        (token-in:module{fungible-v2} (at 'token-out head))
        (amountIn:decimal (at 'out head))
        (p (get-pair token-in token-out))
        (reserveIn (reserve-for p token-in))
        (reserveOut (reserve-for p token-out))
        (amountInWithFee (* (- 1.0 FEE) amountIn))
        (numerator (* amountInWithFee reserveOut))
        (denominator (+ reserveIn amountInWithFee))
      )
      (+ [ { 'token-out: token-out
           , 'token-in: token-in
           , 'in: amountIn
           , 'out: (truncate token-out (/ numerator denominator))
           , 'idx: (+ 1 (at 'idx head))
           , 'pair: p
           , 'path: (drop 1 (at 'path head))
           } ]
         allocs)
    )
  )


  (defun swap-exact-out
    ( amountOut:decimal
      amountInMax:decimal
      path:[module{fungible-v2}]
      sender:string
      to:string
      to-guard:guard
    )
    (enforce (>= (length path) 2) "swap-exact-out: invalid path")
    ;; fold over tail of reverse path with dummy first value to compute inputs
    ;; assembles allocs in forward order
    (let*
      ( (rpath (reverse path))
        (path-len (length path))
        (pz (get-pair (at 0 rpath) (at 1 rpath)))
        (e:[module{fungible-v2}] [])
        (allocs
          (fold (compute-in)
            [ { 'token-out: (at 1 rpath)
              , 'token-in: (at 0 rpath)
              , 'out: 0.0
              , 'in: amountOut
              , 'idx: path-len
              , 'pair: pz
              , 'path: e
              }]
            (drop 1 rpath)))
        (allocs1 ;; drop dummy at end, prepend dummy for initial transfer
          (+ [  { 'token-out: (at 0 path)
                , 'token-in: (at 1 path)
                , 'out: (at 'in (at 0 allocs))
                , 'in: 0.0
                , 'idx: 0
                , 'pair: (at 'pair (at 0 allocs))
                , 'path: path
             } ]
             (take (- path-len 1) allocs)))
      )
      (enforce (<= (at 'out (at 0 allocs1)) amountInMax)
        (format "swap-exact-out: excessive input amount {}"
          [(at 'out (at 0 allocs1))]))
      (with-capability (SWAPPING)
        (swap-pair sender to to-guard allocs1))
    )
  )

  (defun compute-in
    ( allocs:[object{alloc}]
      token-in:module{fungible-v2}
    )
    (let*
      ( (head:object{alloc} (at 0 allocs))
        (token-out:module{fungible-v2} (at 'token-in head))
        (amountOut:decimal (at 'in head))
        (p (get-pair token-in token-out))
        (reserveIn (reserve-for p token-in))
        (reserveOut (reserve-for p token-out))
        (numerator (* reserveIn amountOut))
        (denominator (* (- reserveOut amountOut) (- 1.0 FEE)))
      )
      (+ [ { 'token-out: token-out
           , 'token-in: token-in
           , 'in: (ceiling (/ numerator denominator) (try 0.0 (token-in::precision)))
           , 'out: amountOut
           , 'idx: (- (at 'idx head) 1)
           , 'pair: p
           , 'path: (+ [token-out] (at 'path head))
           } ]
         allocs)
    )
  )



  (defun swap-pair
    ( sender:string
      to:string
      to-guard:guard
      allocs:[object{alloc}]
    )
    (require-capability (SWAPPING))
    (let*
      ( (head:object{alloc} (at 0 allocs))
        (head-token:module{fungible-v2} (at 'token-out head))
        (head-token-in:module{fungible-v2} (at 'token-in head))
        (account (at 'account (at 'pair head)))
        (out (at 'out head))
        (pair-key (get-pair-key head-token head-token-in))


      )
      (with-capability (SWAP-OPEN pair-key)
      (head-token::transfer sender account out)
      (+ [ { 'token: (format "{}" [head-token])
           , 'amount: out } ]
        (map
          (swap-alloc
            (- (length allocs) 1)
            to
            to-guard)
          (drop 1 allocs))))
    )
  )

  (defun swap-alloc
    ( last:integer
      to:string
      guard:guard
      alloc:object{alloc}
    )
    (require-capability (SWAPPING))
    (let*
      ( (path (at 'path alloc))
        (is-last (= last (at 'idx alloc)))
        (next-pair
          (if is-last (at 'pair alloc) (get-pair (at 0 path) (at 1 path))))
        (recipient
          (if is-last to (at 'account next-pair)))
        (next-pair-key (get-pair-key (at 'token (at 'leg0 next-pair)) (at 'token (at 'leg1 next-pair))))
        (recip-guard
          (if is-last guard (create-reserve-guard next-pair-key (at 'token-out alloc))))
      )
      (swap kdswap-noop-callable recipient recip-guard
        (at 'token-out alloc)
        (at 'out alloc)
        (at 'token-in alloc)))
  )

  (defun swap
    ( callable:module{kdswap-callable-v1}
      recipient:string
      recip-guard:guard
      token:module{fungible-v2}
      amount-out:decimal
      token-in:module{fungible-v2}
    )
    " Swap AMOUNT-OUT of TOKEN to RECIPIENT/RECIP-GUARD, \
    \ such that a corresponding transfer to TOKEN-IN, either \
    \ previously or during the execution of 'CALLABLE::swap-call', \
    \ will satisfy the constant-product invariant for the pair."
    (with-capability (MUTEX) ;; acquire the pair lock
      (obtain-pair-mutex-lock (get-pair-key token token-in)))
    (let*
      ( (p (get-pair token token-in))
        (pair-key (get-pair-key token token-in))
        (account (at 'account p))
        (reserve-out (reserve-for p token))
      )
      (enforce (> amount-out 0.0) "swap: insufficient output")
      (enforce (< amount-out reserve-out) "swap: insufficient liquidity")
      (enforce (!= recipient account) "swap: invalid TO")
      ;;fire swap event
      (install-capability (token::TRANSFER account recipient amount-out))
      (with-capability (PRIVATE_RESERVE pair-key (format-token token))
        (token::transfer-create account recipient recip-guard amount-out)
      )

      (callable::swap-call token-in token amount-out
        account recipient recip-guard)

      (let*
        ( (leg0 (at 'leg0 p))
          (leg1 (at 'leg1 p))
          (token0:module{fungible-v2} (at 'token leg0))
          (token1:module{fungible-v2} (at 'token leg1))
          (balance0 (token0::get-balance account))
          (balance1 (token1::get-balance account))
          (reserve0 (at 'reserve leg0))
          (reserve1 (at 'reserve leg1))
          (canon (is-leg0 p token))
          (amount0Out (if canon amount-out 0.0))
          (amount1Out (if canon 0.0 amount-out))
          (amount0In (if (> balance0 (- reserve0 amount0Out))
                        (- balance0 (- reserve0 amount0Out))
                        0.0))
          (amount1In (if (> balance1 (- reserve1 amount1Out))
                        (- balance1 (- reserve1 amount1Out))
                        0.0))
          (balance0adjusted (- balance0 (* amount0In 0.003)))
          (balance1adjusted (- balance1 (* amount1In 0.003)))
        )
        (enforce (or (> amount0In 0.0) (> amount1In 0.0))
          "swap: insufficient input amount")
        (enforce (>= (* balance0adjusted balance1adjusted)
                     (* reserve0 reserve1))
          (format "swap: K ({} < {})"
          [(* balance0adjusted balance1adjusted) (* reserve0 reserve1)]))
        (with-capability (UPDATE pair-key balance0 balance1)
          (with-capability
            (SWAP account recipient
              (if canon amount1In amount0In)
              token-in amount-out token)
            (update-reserves p
              (get-pair-key token0 token1) balance0 balance1)))
        ;; release the pair lock
        (with-capability (MUTEX)
          (release-pair-mutex-lock (get-pair-key token token-in)))
        ;; return the swap output information
        { 'token: (format "{}" [token])
        , 'amount: amount-out
        }
      )
    )
  )

  (defun create-pair
    ( token0:module{fungible-v2}
      token1:module{fungible-v2}
      hint:string
      )
    " Create new pair for legs TOKEN0 and TOKEN1. This creates a new \
    \ pair record, a liquidity token named after the canonical pair key \
    \ in 'kdswap-exchange-tokens' module, and new empty accounts in each leg token. \
    \ If account key value is already taken in leg tokens, transaction \
    \ will fail, which is why HINT exists (which should normally be \"\"), \
    \ to further seed the hash function creating the account id."

    (let* ((key (get-pair-key token0 token1))
            (canon (is-canonical token0 token1))
            (ctoken0:module{fungible-v2} (if canon token0 token1))
            (ctoken1:module{fungible-v2} (if canon token1 token0))
            (a (create-pair-account key hint))
            (t0g (create-reserve-guard key ctoken0))
            (t1g (create-reserve-guard key ctoken1))
            (lpg (create-liquidity-guard key))
            (p { 'leg0: { 'token: ctoken0, 'reserve: 0.0 }
              , 'leg1: { 'token: ctoken1, 'reserve: 0.0 }
              , 'account: a
              , 'guard: (create-null-guard)
              , 'mutex-locked: false
              })
            )
      (with-capability (CREATE_PAIR ctoken0 ctoken1 key a)
        (insert pairs key p)
        (ctoken0::create-account a t0g)
        (ctoken1::create-account a t1g)
        (kdswap-exchange-tokens.create-account key a lpg)
        { "key": key
        , "account": a
        }))
    )

  (defun get-pair-key:string
    ( tokenA:module{fungible-v2}
      tokenB:module{fungible-v2}
    )
    " Create canonical key for pair."
    (format "{}:{}" (canonicalize tokenA tokenB))
  )

  (defun canonicalize:[module{fungible-v2}]
    ( tokenA:module{fungible-v2}
      tokenB:module{fungible-v2}
    )
    (if (is-canonical tokenA tokenB) [tokenA tokenB] [tokenB tokenA])
  )

  (defun is-canonical
    ( tokenA:module{fungible-v2}
      tokenB:module{fungible-v2}
    )
    (< (format "{}" [tokenA]) (format "{}" [tokenB]))
  )

  (defun is-leg0:bool
    ( p:object{pair}
      token:module{fungible-v2}
    )
    (let ((token0 (at 'token (at 'leg0 p))))
      (= (format "{}" [token])
         (format "{}" [token0]))) ;; TODO modref equality
  )

  (defun leg-for:object{leg}
    ( p:object{pair}
      token:module{fungible-v2}
    )
    (if (is-leg0 p token)
      (at 'leg0 p)
      (at 'leg1 p))
  )

  (defun reserve-for:decimal
    ( p:object{pair}
      token:module{fungible-v2}
    )
    (at 'reserve (leg-for p token))
  )

  (defun format-token:string
    ( token:module{fungible-v2} )
    (format "{}" [token])
  )

  (defun create-pair-account:string
    ( key:string hint:string)
    (hash (+ hint (+ key (format "{}" [(at 'block-time (chain-data))]))))
  )

  (defun truncate:decimal (token:module{fungible-v2} amount:decimal)
    (floor amount (try 0.0 (token::precision)))
  )
)

