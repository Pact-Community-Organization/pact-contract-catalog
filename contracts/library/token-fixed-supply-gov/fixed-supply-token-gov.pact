(module fixed-supply-token-gov GOV

  @doc "PCO library template: the fixed-supply, non-upgradeable fungible-v2  \
  \token (see library/token-fixed-supply) extended with ADVISORY governance: \
  \proposals plus live balance-weighted yes/no/abstain voting with permanent \
  \on-chain tallies.                                                         \
  \                                                                          \
  \The live-vote discipline, in full:                                        \
  \  * A vote's weight is the voter's CURRENT balance; re-voting updates the \
  \    recorded vote in place.                                               \
  \  * Every balance DECREASE (transfer out, burn) automatically releases    \
  \    the moved weight from the account's votes on every OPEN proposal, so  \
  \    tokens that were sold or moved can never keep voting - the classic    \
  \    vote-then-transfer double-count is impossible by construction.        \
  \  * Received tokens arrive UNVOTED: credits never touch tallies.          \
  \  * release-votes is deliberately PUBLIC: it derives everything from the  \
  \    account's REAL balance, so calling it is a harmless permissionless    \
  \    vote-weight sync - it can only shrink stale weights, never forge or   \
  \    grow votes.                                                           \
  \  * At most MAX-ACTIVE-PROPOSALS are open at once, so the release work    \
  \    added to a transfer or burn is bounded (<= 3 proposal/vote row pairs).\
  \                                                                          \
  \Votes EXECUTE NOTHING. The token is frozen and the mint is one-shot, so   \
  \there is no governed surface in this module - tallies are the community's \
  \permanently recorded voice, and readers judge turnout themselves (no      \
  \quorum is enforced). If you attach off-chain or cross-module meaning to a \
  \result, disclose prominently that votes are advisory signals.             \
  \                                                                          \
  \Deploy-time parameterization: symbol, precision, total-supply and         \
  \token-minter as in the base template, PLUS gov-threshold - the fraction   \
  \of TOTAL-SUPPLY required to open a proposal, enforced into [0.001, 0.1].  \
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
  \Single-chain by design: transfer-crosschain is disabled, which also makes \
  \the voting chain-local by construction (no cross-chain double-vote        \
  \surface exists)."

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

  (defconst GOV-THRESHOLD-FRACTION:decimal
    (let ((f (read-decimal 'gov-threshold)))
      (enforce (and (>= f 0.001) (<= f 0.1)) "gov-threshold in [0.001, 0.1]")
      f)
    "Fraction of TOTAL-SUPPLY required to open a proposal, fixed at deploy.")

  (defconst PROPOSAL-THRESHOLD:decimal
    (let ((t (floor (* TOTAL-SUPPLY GOV-THRESHOLD-FRACTION) PRECISION)))
      (enforce (> t 0.0)
        "proposal threshold floors to zero at this precision/supply - refuse the deploy")
      t)
    "Minimum balance to open a proposal. Enforced positive at deploy so the \
    \spam gate can never silently vanish on low-precision/low-supply tokens.")

  (defconst MIN-VOTE-HOURS 24
    "Shortest allowed voting window.")

  (defconst MAX-VOTE-HOURS 720
    "Longest allowed voting window (30 days).")

  (defconst MAX-ACTIVE-PROPOSALS 3
    "Open-proposal cap: bounds the release work on every balance decrease.")

  (defconst MINIMUM_ACCOUNT_LENGTH 3
    "Minimum account name length")

  (defconst MAXIMUM_ACCOUNT_LENGTH 256
    "Maximum account name length")

  (defconst SUPPLY-KEY "supply")
  (defconst ACTIVE-KEY "active")
  (defconst COUNT-KEY "n")

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

  (defschema gov-proposal
    creator:string
    title:string
    body:string
    created:time
    close-at:time
    yes:decimal
    no:decimal
    abstain:decimal)

  (deftable gov-proposals:{gov-proposal})   ; key = proposal id (counter)

  (defschema gov-vote
    choice:string
    weight:decimal)

  (deftable gov-votes:{gov-vote})           ; key = "<pid>:<account>"

  (defschema gov-active
    ids:[string])

  (deftable gov-actives:{gov-active})       ; singleton: open-proposal index

  (defschema gov-count
    n:integer)

  (deftable gov-counts:{gov-count})         ; singleton: id counter

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

  (defcap BURNED (account:string amount:decimal)
    @event
    true)

  (defcap ROTATE (account:string)
    @doc "Guard-rotation authorization: the account's CURRENT guard. A       \
         \capability-scoped signature can target exactly this rotation."
    (enforce-guard (at 'guard (read accounts account))))

  (defcap PROPOSE (account:string)
    @doc "Proposal authorization: the proposer's own account guard, scoped   \
         \so wallets never need an unscoped signature to open a proposal."
    (enforce-guard (at 'guard (read accounts account))))

  (defcap VOTE (pid:string account:string)
    @doc "Vote authorization: the voter's own account guard, scoped to one   \
         \proposal so wallets never need an unscoped signature to vote."
    (enforce-guard (at 'guard (read accounts account))))

  (defcap GOV-PROPOSED (id:string creator:string title:string close-at:time)
    @event
    true)

  (defcap GOV-VOTED (id:string account:string choice:string weight:decimal)
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
  ;; fungible-v2 surface (identical to the base template except the
  ;; release-votes call sites after the two balance decreases)
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
      (update accounts account { "balance": (- b amount) }))
    (release-votes account))

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
    @doc "Self-burn under the account's own guard; decrements live supply \
         \and releases the burned weight from open votes."
    (enforce (> amount 0.0) "amount must be positive")
    (enforce-unit amount)
    (with-capability (BURN account)
      (with-read accounts account { "balance" := b }
        (enforce (<= amount b) "insufficient funds")
        (update accounts account { "balance": (- b amount) }))
      (with-read supply SUPPLY-KEY { "burned" := bu }
        (update supply SUPPLY-KEY { "burned": (+ bu amount) })))
    (release-votes account)
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

  ;; -----------------------------
  ;; Advisory governance
  ;; -----------------------------

  (defun curr-time:time ()
    (at 'block-time (chain-data)))

  (defun proposal-threshold:decimal ()
    @doc "Minimum balance required to open a proposal (deploy-enforced > 0)."
    PROPOSAL-THRESHOLD)

  (defun open-ids:[string] ()
    @doc "Currently OPEN proposal ids (pruned view of the active index)."
    (let ((now (curr-time)))
      (with-default-read gov-actives ACTIVE-KEY { "ids": [] } { "ids" := ids }
        (filter (lambda (pid:string)
                  (< now (at 'close-at (read gov-proposals pid))))
                ids))))

  (defun create-proposal:string
      (account:string title:string body:string duration-hours:integer)
    @doc "Open an advisory proposal. Caller must hold >= proposal-threshold. \
         \At most MAX-ACTIVE-PROPOSALS may be open (bounds transfer gas)."
    (enforce (and (>= duration-hours MIN-VOTE-HOURS) (<= duration-hours MAX-VOTE-HOURS))
      "duration outside [24h, 720h]")
    (enforce (and (> (length title) 0) (<= (length title) 120)) "title 1..120 chars")
    (enforce (<= (length body) 2000) "body <= 2000 chars")
    (with-capability (PROPOSE account)
      (let ((bal (at 'balance (read accounts account))))
        (enforce (>= bal PROPOSAL-THRESHOLD) "balance below proposal threshold"))
      (let* ((open (open-ids))
             (n (with-default-read gov-counts COUNT-KEY { "n": 0 } { "n" := c } c))
             (pid (int-to-str 10 (+ n 1)))
             (now (curr-time))
             (close (add-time now (hours duration-hours))))
        (enforce (< (length open) MAX-ACTIVE-PROPOSALS) "too many active proposals")
        (write gov-counts COUNT-KEY { "n": (+ n 1) })
        (insert gov-proposals pid
          { "creator": account, "title": title, "body": body
          , "created": now, "close-at": close
          , "yes": 0.0, "no": 0.0, "abstain": 0.0 })
        (write gov-actives ACTIVE-KEY { "ids": (+ open [pid]) })
        (emit-event (GOV-PROPOSED pid account title close))
        pid)))

  (defun cast-vote:string (pid:string account:string choice:string)
    @doc "Vote with weight = CURRENT balance; re-vote updates in place.     \
         \Authorized by the account's own guard."
    (enforce (contains choice ["yes" "no" "abstain"]) "choice: yes|no|abstain")
    (let ((close (at 'close-at (read gov-proposals pid)))
          (now (curr-time)))
      (enforce (< now close) "voting closed"))
    (with-capability (VOTE pid account)
      (cast-vote-internal pid account choice)))

  (defun cast-vote-internal:string (pid:string account:string choice:string)
    (require-capability (VOTE pid account))
    (let ((weight (at 'balance (read accounts account)))
          (vkey (format "{}:{}" [pid account])))
      (enforce (> weight 0.0) "no voting weight")
      (with-default-read gov-votes vkey { "choice": "", "weight": 0.0 }
        { "choice" := oc, "weight" := ow }
        ;; remove any previous vote from its tally column, then add the new one
        (if (> ow 0.0)
          (with-read gov-proposals pid { "yes" := y, "no" := nn, "abstain" := a }
            (update gov-proposals pid
              (if (= oc "yes") { "yes": (- y ow) }
                (if (= oc "no") { "no": (- nn ow) } { "abstain": (- a ow) }))))
          "no prior vote")
        (with-read gov-proposals pid { "yes" := y2, "no" := n2, "abstain" := a2 }
          (update gov-proposals pid
            (if (= choice "yes") { "yes": (+ y2 weight) }
              (if (= choice "no") { "no": (+ n2 weight) } { "abstain": (+ a2 weight) }))))
        (write gov-votes vkey { "choice": choice, "weight": weight }))
      (emit-event (GOV-VOTED pid account choice weight))
      "vote recorded"))

  (defun release-votes:string (account:string)
    @doc "Permissionless vote-weight sync: shrink the account's recorded    \
         \weight on every OPEN proposal down to its CURRENT balance (the    \
         \live-vote release rule). Derives everything from real state, so   \
         \a public call can only correct stale weights, never forge votes.  \
         \Called automatically after every balance decrease."
    (let ((bal (with-default-read accounts account { "balance": 0.0 } { "balance" := b } b)))
      (map (lambda (pid:string)
             (let ((vkey (format "{}:{}" [pid account])))
               (with-default-read gov-votes vkey { "choice": "", "weight": 0.0 }
                 { "choice" := c, "weight" := w }
                 (if (> w bal)
                   (let ((excess (- w bal)))
                     (with-read gov-proposals pid { "yes" := y, "no" := nn, "abstain" := a }
                       (update gov-proposals pid
                         (if (= c "yes") { "yes": (- y excess) }
                           (if (= c "no") { "no": (- nn excess) } { "abstain": (- a excess) }))))
                     (update gov-votes vkey { "weight": bal })
                     "released")
                   "unchanged"))))
           (open-ids))
      "synced"))

  (defun get-proposal:object{gov-proposal} (pid:string)
    (read gov-proposals pid))

  (defun get-vote:object{gov-vote} (pid:string account:string)
    (read gov-votes (format "{}:{}" [pid account])))

  (defun get-results:object (pid:string)
    @doc "Tallies + turnout + closed flag. ADVISORY: no quorum is enforced; \
         \readers judge the turnout themselves."
    (with-read gov-proposals pid
      { "title" := t, "close-at" := ca, "yes" := y, "no" := nn, "abstain" := a }
      { "title": t, "yes": y, "no": nn, "abstain": a
      , "turnout": (+ y (+ nn a)), "close-at": ca
      , "closed": (>= (curr-time) ca) }))
)

;; Frozen governance means module admin exists ONLY inside the deploy
;; transaction - tables MUST be created here, they can never be created later.
(create-table accounts)
(create-table supply)
(create-table gov-proposals)
(create-table gov-votes)
(create-table gov-actives)
(create-table gov-counts)
