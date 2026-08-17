;; fixed-supply-token-gov.pact — fixed-supply fungible token with chain-local
;; advisory ranked-choice governance.
;;
;; PCO library template. Set every `EDIT-BEFORE-DEPLOY` literal, define the
;; `<ns>.token-gov` keyset in your namespace, then deploy on every chain with
;; tx data { "ns": "<namespace>", "upgrade": false }.
(namespace (read-msg 'ns))

(module fixed-supply-token-gov GOVERNANCE

  @doc "Fixed-supply fungible-v2 + fungible-xchain-v1 token with ADVISORY      \
  \chain-local ranked-choice governance: admin-authored questions, ballots     \
  \weighted by the voter's CURRENT balance on the chain the vote is cast from, \
  \every balance decrease releasing the moved weight from open ballots,        \
  \credits arriving unvoted, and the reserve plus every registered escrow      \
  \barred BY NAME. Votes execute nothing; the head-to-head pairwise matrix is  \
  \the authoritative result and the Borda scores are a truncation diagnostic."

  (implements fungible-v2)
  (implements fungible-xchain-v1)

  ;; -----------------------------
  ;; Governance: the admin keyset (rotatable; freezable by upgrade)
  ;; -----------------------------

  (defconst NS:string (read-msg 'ns)
    "Deploy namespace, fixed at deploy (no source edit between networks).")

  (defconst ADMIN-KS:string (format "{}.token-gov" [NS])
    "The governance keyset; rotating its definition rotates every right this \
    \module grants it.")

  ;; A fresh deploy has no history to bless. Every UPGRADE to a deployed
  ;; instance must carry a (bless "<hash>") line for each previously deployed
  ;; hash, and those lines are APPEND-ONLY: in-flight cross-chain transfers
  ;; resolve against the hash that debited them.

  (defconst FROZEN-MODULE:bool false
    "Set true and redeploy to permanently freeze upgrades.")

  (defcap GOVERNANCE ()
    @doc "Upgrade/admin gate: the governance keyset, unless frozen."
    (enforce (not FROZEN-MODULE) "Module is frozen - no further upgrades")
    (enforce-keyset ADMIN-KS))

  ;; -----------------------------
  ;; Deploy-time constants
  ;; -----------------------------

  ;; SYMBOL, PRECISION, TOTAL-SUPPLY and MINT-CHAIN are LITERALS, never read
  ;; from tx data: a defconst is re-evaluated on every module load, an upgrade
  ;; (including the freeze) is a module load, so a data-block value could be
  ;; silently restated by any upgrade. NS stays a deploy parameter
  ;; deliberately - it is the one value that genuinely differs between
  ;; networks.

  (defconst SYMBOL "TKN"                      ;; EDIT-BEFORE-DEPLOY
    "Display symbol.")

  (defconst PRECISION:integer 12              ;; EDIT-BEFORE-DEPLOY
    "Decimal precision (12 matches coin). An upgrade carrying a smaller value \
    \would make finer-grained balances permanently unspendable.")

  (defconst TOTAL-SUPPLY:decimal 1000000.0    ;; EDIT-BEFORE-DEPLOY
    "The fixed supply: minted exactly once, on MINT-CHAIN, never changed after.")

  (defconst MINT-CHAIN:string "0"             ;; EDIT-BEFORE-DEPLOY
    "The chain carrying the one-shot mint. It does NOT gate questions or \
    \ballots, which are chain-local.")

  (defconst OPS-KEY:string "ops"
    "Singleton row key for the ops-authority table.")

  (defconst EMPTY-KEYSET-PREFIX:string
    "w:DldRwCblQ7Loqy6wYJnaodHl30d3j3eH-qtFzfEv46g"
    "Principal prefix shared by EVERY keyset with an empty key list (the     \
    \key-list hash is a constant). `keys-all` over zero keys is vacuously    \
    \TRUE, so such a keyset is satisfied by a caller signing nothing;        \
    \set-ops-guard refuses the whole shape.")

  (defconst MAX-OPTIONS 5
    "Most options a ranked-choice question may carry (bounds ballot and     \
    \release work; 2 options = a plain either/or question).")

  (defconst RESERVE-ACCOUNT:string
    (create-principal (keyset-ref-guard ADMIN-KS))
    "The reserve account (r: principal of the governance keyset); rotating \
    \the keyset re-points its control automatically. Barred from voting BY \
    \NAME.")
  ;; The reserve bar is a name check, not a lock on admin voting power:
  ;; governance can move the reserve to an ordinary account and vote it
  ;; (publicly evented), and while the module is unfrozen module admin can
  ;; write scores and balances directly, emitting nothing. The FROZEN-MODULE
  ;; flip closes only that silent route - it buys detectability, not
  ;; governance neutrality.

  (defconst MIN-VOTE-HOURS 24
    "Shortest allowed voting window: ends-at at least this far after \
    \starts-at.")
  ;; Every chain's copy closes at ONE absolute instant, so a short window can
  ;; shut out a holder on a chain with slow block production.

  (defconst MAX-VOTE-HOURS 720
    "Longest a question may run: 30 days from starts-at to ends-at.")
  ;; Also the longest a mistyped ends-at can hold one of the
  ;; MAX-ACTIVE-PROPOSALS slots: cancellation is refused once voting opens,
  ;; so there is no close path.

  (defconst MIN-ANNOUNCE-HOURS 12
    "Least notice between authoring a question and voting opening on it.")
  ;; The floor buys two things: every chain's copy can be landed and verified
  ;; before the first ballot, and pre-start cancellation has a real window to
  ;; act in. It does NOT make the copies start together; only the absolute
  ;; starts-at does that.

  (defconst CREATED-SKEW-SECONDS 3600
    "How far the caller-supplied created-at may sit from this chain's own \
    \block time, in either direction.")
  ;; Too far forward fabricates the announce window; too far back dodges the
  ;; floor by backdating. One hour covers the cross-chain clock spread plus a
  ;; retried transaction, leaving an effective floor of 11 hours worst case.

  (defconst MAX-ACTIVE-PROPOSALS 3
    "Open-question cap: bounds the release work on every balance decrease.")

  (defconst MINIMUM_ACCOUNT_LENGTH 3
    "Minimum account name length")

  (defconst MAXIMUM_ACCOUNT_LENGTH 256
    "Maximum account name length")

  (defconst SUPPLY-KEY "supply")
  (defconst ACTIVE-KEY "active")

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
    @doc "Singleton per-chain supply ledger, seeded {minted: 0.0} at deploy \
         \on every chain. The one-shot mint flips minted from 0.0 exactly   \
         \once, on MINT-CHAIN; there is no burn path."
    minted:decimal)

  (deftable supply:{supply-row})

  (defschema recipient
    @doc "One initial-distribution entry for init-mint."
    account:string
    guard:guard
    amount:decimal)

  (defschema rcv-proposal
    @doc "One ADMIN-authored ranked-choice question: 2..MAX-OPTIONS named    \
         \options; scores[i] = live Borda points of options[i] (diagnostic); \
         \m = the authoritative K x K head-to-head matrix, flattened         \
         \row-major, where m[i*K + j] is the total ballot weight preferring  \
         \option i to option j (the diagonal stays 0.0 forever)."
    title:string
    body:string
    options:[string]
    ;; Three ABSOLUTE instants, identical on every chain: supplied by the
    ;; caller, never derived from local block time - a deadline computed from
    ;; "now" gives every chain a different deadline, which is a double-vote
    ;; hole.
    created:time                      ; when the operator says it was authored
    starts-at:time                    ; voting opens - >= created + MIN-ANNOUNCE-HOURS
    ends-at:time                      ; voting closes - [MIN-VOTE-HOURS, MAX-VOTE-HOURS] after starts-at
    cancelled:bool                    ; voided before it started; never re-opened
    scores:[decimal]
    turnout:decimal
    ;; The pairwise cells are depth-neutral - a partial ballot credits the
    ;; same i-vs-j cells as a full one - which the Borda scores are not.
    ;; READ THE CELLS, NOT A SUMMARY: every scalar reduction (row sums, net
    ;; margins) reintroduces a ballot-length bonus and throws the property
    ;; away.
    m:[decimal])

  (deftable rcv-proposals:{rcv-proposal})   ; key = operator-supplied question id

  (defschema rcv-ballot
    @doc "One voter's live ballot on one question: the ranking (ordered,     \
         \distinct option indices, best first - partial rankings allowed)    \
         \and the weight it currently carries (shrunk by releases)."
    ranking:[integer]
    weight:decimal)

  (deftable rcv-ballots:{rcv-ballot})       ; key = "<pid>:<account>"

  (defschema gov-active
    ids:[string])

  (deftable rcv-actives:{gov-active})       ; singleton: open-question index

  (defschema vote-delegate
    @doc "An OPTIONAL dedicated voting key for one account: a hot key that   \
         \can ONLY vote, so the main (cold) key never has to come out for    \
         \routine governance. Registered/cleared exclusively under the MAIN  \
         \account guard; consumed ONLY by the VOTE capability."
    guard:guard
    active:bool)

  (deftable vote-delegates:{vote-delegate}) ; key = account

  (defschema ops-authority
    @doc "The routine-operations authority, held as module STATE rather than \
         \a named keyset: a named keyset can only be redefined by satisfying \
         \ITSELF, so a compromised ops device could re-point it and a lost   \
         \one could never be replaced. Held here it is governance-owned: ops \
         \can never change it, and governance can always replace it."
    guard:guard)

  (deftable ops-auth:{ops-authority})       ; singleton, key = OPS-KEY

  (defschema non-voting-row
    @doc "An account registered as OUTSIDE THE FLOAT: an escrow holding tokens \
         \that are not yet anybody's, so they carry no voice. Registered BY     \
         \NAME, never inferred from the guard type - what disqualifies an       \
         \escrow is what it HOLDS, and a type rule would disenfranchise         \
         \legitimate contract-held balances while missing an escrow under an    \
         \ordinary name. The register is public and auditable against supply."
    reason:string)

  (deftable non-voting:{non-voting-row})

  ;; -----------------------------
  ;; Capabilities
  ;; -----------------------------

  (defcap DEBIT (sender:string)
    @doc "Internal debit permission: enforces the sender's account guard."
    (enforce-guard (at 'guard (read accounts sender))))

  ;; Deliberately NO `CREDIT` capability: a trivially satisfiable cap body
  ;; gates nothing and reads like protection. THE INVARIANT protecting supply:
  ;; a balance may rise ONLY inside `transfer-create` (fused with a real
  ;; DEBIT), `init-mint` (MINT keyset, one-shot), or the cross-chain receive
  ;; resume (real SPV continuation). Never add a standalone credit path.

  (defcap MINT ()
    @doc "The one-shot initial mint, authorized by the governance keyset.  \
         \Powerless after the mint (one-shot by construction)."
    (enforce-keyset ADMIN-KS))

  (defcap VOTE-KEY-ADMIN (account:string vote-authority:string)
    @doc "Owner gate for vote-key registration/clearing: the account's MAIN  \
         \guard, nobody else's - the hot key can never re-point itself.      \
         \VOTE-AUTHORITY (the new key's principal, or \"\" when clearing) is \
         \in the capability because the registered guard travels in tx DATA, \
         \which no wallet displays: with it, a substituted key changes what  \
         \the wallet shows."
    (enforce-guard (at 'guard (read accounts account))))

  ;; EVENT CAPABILITIES. Each carries a real body: an @event cap authorizes
  ;; nothing, so each requires the capability that authorized the underlying
  ;; action. That binds the AUTHORITY, not the PAYLOAD - reconcile anything
  ;; published from this log against table state.

  (defcap VOTE-KEY-SET (account:string key:string)
    @event
    (require-capability (VOTE-KEY-ADMIN account key)))

  (defcap VOTE-KEY-CLEARED (account:string)
    @event
    ;; Emitted from BOTH clear-vote-key (under VOTE-KEY-ADMIN) and rotate
    ;; (under ROTATE, which deactivates the hot key). Both hold the account's
    ;; own guard, so that is the common, real requirement.
    (enforce-guard (at 'guard (read accounts account))))

  (defcap ROTATE (account:string new-authority:string)
    @doc "Guard-rotation authorization: the account's CURRENT guard, scoped  \
         \to the account AND to the principal of the guard it is rotating    \
         \TO. The new guard travels in tx DATA, which no wallet displays;    \
         \with NEW-AUTHORITY in the capability, a substituted key changes    \
         \what the wallet shows."
    (enforce-guard (at 'guard (read accounts account))))

  (defun ops-guard:guard ()
    @doc "The current ops authority. Defaults to the governance keyset      \
         \guard until governance sets one, so a fresh deploy is operable    \
         \immediately and there is never an undefined-keyset abort."
    (with-default-read ops-auth OPS-KEY
      { "guard": (keyset-ref-guard ADMIN-KS) }
      { "guard" := g }
      g))

  (defcap OPS-ADMIN ()
    @doc "Governance re-points the ops authority. Gated on the governance   \
         \keyset ALONE - deliberately NOT on FROZEN-MODULE - so that WHO    \
         \OPERATES stays recoverable even after code is frozen forever.     \
         \This is a disclosed governance power that survives a freeze; it   \
         \moves no funds and grants nothing beyond naming the ops tier."
    (enforce-keyset ADMIN-KS))

  (defcap OPS-GUARD-SET (authority:string)
    @event
    (require-capability (OPS-ADMIN)))

  (defcap NON-VOTING-SET (account:string reason:string)
    @event
    (require-capability (NON-VOTING-ADMIN)))

  (defcap NON-VOTING-CLEARED (account:string)
    @event
    (require-capability (NON-VOTING-ADMIN)))

  (defcap PROPOSAL-OPS ()
    @doc "Question administration gate: questions are ADMIN-AUTHORED - the   \
         \ops authority creates and cancels them. The governance keyset      \
         \ALWAYS satisfies this too, and is tried FIRST, so a broken or      \
         \hostile ops authority can never lock governance out."
    ;; BRANCH ORDER IS LOAD-BEARING - governance first, do not "tidy" it back.
    ;; The ops branch reads `ops-auth` (inside ops-guard); on a chain missing
    ;; that table the read raises a DATABASE error, which neither `try` nor
    ;; `enforce-one` contains. Keyset first means a satisfied governance
    ;; keyset returns before the read is ever reached.
    (enforce-one "governance or ops authority required"
      [ (enforce-keyset ADMIN-KS)
        (enforce-guard (ops-guard)) ]))

  (defcap VOTE (pid:string account:string)
    @doc "Vote authorization: the voter's MAIN account guard OR their ACTIVE \
         \registered vote key, scoped to one question so wallets never need  \
         \an unscoped signature to vote. The MAIN guard is tried FIRST, so   \
         \neither a hostile registration NOR a missing vote-delegates table  \
         \can lock an owner out of voting."
    ;; BRANCH ORDER IS LOAD-BEARING - main guard first, do not "tidy" it back.
    ;; The vote-key branch reads `vote-delegates`; on a chain missing that
    ;; table the read raises a DATABASE error, which neither `try` nor
    ;; `enforce-one` contains - never hoist the read above the enforce-one.
    ;; (A read inside an enforce-one BRANCH is fine on both node lineages;
    ;; the let-bind house rule covers reads inside an `enforce` CONDITION.)
    ;; `active` is enforced BEFORE the guard, so the default guard below is
    ;; unreachable and exists only to satisfy with-default-read's binding.
    (enforce-one "neither account guard nor registered vote key satisfied"
      [ (enforce-guard (at 'guard (read accounts account)))
        (with-default-read vote-delegates account
          { "guard": (keyset-ref-guard ADMIN-KS), "active": false }
          { "guard" := g, "active" := a }
          (enforce a "no active vote key")
          (enforce-guard g)) ]))

  (defcap GOV-PROPOSED (id:string title:string options:[string] starts-at:time ends-at:time)
    @event
    (require-capability (PROPOSAL-OPS)))

  (defcap GOV-VOTED (id:string account:string ranking:[integer] weight:decimal)
    @event
    (require-capability (VOTE id account)))

  (defcap GOV-CANCELLED (id:string reason:string)
    @event
    (require-capability (PROPOSAL-OPS)))

  (defcap TRANSFER:bool (sender:string receiver:string amount:decimal)
    @managed amount TRANSFER-mgr
    (enforce (!= sender receiver) "same sender and receiver")
    (enforce (> amount 0.0) "amount must be positive")
    (enforce-unit amount)
    (compose-capability (DEBIT sender)))

  (defun TRANSFER-mgr:decimal (managed:decimal requested:decimal)
    (let ((newbal (- managed requested)))
      (enforce (>= newbal 0.0) "TRANSFER exceeded for balance")
      newbal))

  (defcap TRANSFER_XCHAIN:bool
      (sender:string receiver:string amount:decimal target-chain:string)
    @managed amount TRANSFER_XCHAIN-mgr
    (enforce (> amount 0.0) "cross-chain amount must be positive")
    (enforce-unit amount)
    ;; A yield to a nonexistent chain would destroy the debited tokens with no
    ;; burn accounting, so only real chains may be targeted. coin.VALID_CHAIN_IDS
    ;; is a foreign defconst, INLINED at this module's compile time - a copy
    ;; frozen at deploy: a later `coin` upgrade cannot break the check, and new
    ;; chains need a redeploy (fail-safe: over-restrictive, never permissive).
    (enforce (contains target-chain coin.VALID_CHAIN_IDS)
      "target chain is not a valid chain id")
    (enforce (!= (at 'chain-id (chain-data)) target-chain)
      "cannot cross-chain transfer to the same chain")
    (compose-capability (DEBIT sender)))

  (defun TRANSFER_XCHAIN-mgr:decimal (managed:decimal requested:decimal)
    (enforce (>= managed requested) "cross-chain transfer exceeds installed amount")
    0.0) ; one-shot: a cross-chain signature covers exactly one send

  (defcap TRANSFER_XCHAIN_RECD:bool
      (sender:string receiver:string amount:decimal source-chain:string)
    @event
    ;; Required by fungible-xchain-v1 and emitted from the cross-chain RESUME,
    ;; where no capability is held - the continuation's authority IS the SPV
    ;; proof - so this is the ONE irreducible exception to the house rule above.
    ;; Every check below is satisfiable by an uninvolved caller, so a third
    ;; party can fabricate this event from nothing: NEVER read it as evidence
    ;; of an arrival - reconcile against balances instead.
    (enforce (> amount 0.0) "amount must be positive")
    (enforce (!= receiver "") "receiver must be named")
    (enforce (contains source-chain coin.VALID_CHAIN_IDS) "invalid source chain"))

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
    ;; Delegate to transfer-create with the receiver's EXISTING guard, so there is
    ;; exactly ONE credit code path (transfer-create), fused with a real debit.
    ;; with-read requires the receiver to already exist, preserving fungible-v2
    ;; `transfer` semantics (receiver must exist; use transfer-create otherwise).
    (with-read accounts receiver { "guard" := g }
      (transfer-create sender receiver g amount)))

  (defun transfer-create:string
      (sender:string receiver:string receiver-guard:guard amount:decimal)
    (with-capability (TRANSFER sender receiver amount)
      ;; DEBIT IS INLINED, not called: a standalone public `debit` is a BURN
      ;; path, and Pact has no private functions, so the debit gets no name.
      ;; Both checks below are load-bearing - `(<= amount b)` alone admits a
      ;; NEGATIVE amount, and `(- b amount)` would then RAISE the balance.
      (require-capability (DEBIT sender))
      (enforce (> amount 0.0) "debit amount must be positive")
      (enforce-unit amount)
      (with-read accounts sender { "balance" := sb }
        (enforce (<= amount sb) "insufficient funds")
        (update accounts sender { "balance": (- sb amount) }))
      (release-votes sender)
      ;; The receiver credit is INLINED, lexically fused with the debit above,
      ;; and deliberately NOT exposed as a standalone function: the matching
      ;; debit is what conserves supply. Any change here MUST keep every
      ;; balance increase unreachable except behind a real debit, the MINT
      ;; keyset, or the cross-chain receive resume.
      (validate-account receiver)
      (enforce-reserved receiver receiver-guard)
      (with-default-read accounts receiver
        { "balance": 0.0, "guard": receiver-guard }
        { "balance" := b, "guard" := g }
        (enforce (= g receiver-guard) "account guard mismatch")
        (write accounts receiver { "balance": (+ b amount), "guard": g }))))

  ;; Deliberately NO public `debit` (a standalone debit is a BURN, and this
  ;; token has no burn path) and NO public `credit` (checks that live in a
  ;; caller are a wrapper-trust hole). The decrease is inlined into
  ;; transfer-create and the cross-chain step-0, each fused with its matching
  ;; credit; the mint write is inlined into init-mint behind its one-shot gate.

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
    (with-capability (ROTATE account (create-principal new-guard))
      (update accounts account { "guard": new-guard })
      ;; a guard hand-over must not leave the PREVIOUS owner's vote key live:
      ;; deactivate any active registration so the new owner starts clean
      (with-default-read vote-delegates account
        { "active": false } { "active" := a }
        (if a
            (let ((_ (update vote-delegates account { "active": false })))
              (emit-event (VOTE-KEY-CLEARED account)))
            true)))
    (format "rotated {}" [account]))

  ;; -----------------------------
  ;; fungible-xchain-v1 — transfer-crosschain (2-step SPV defpact)
  ;; -----------------------------

  (defpact transfer-crosschain:string
      (sender:string receiver:string receiver-guard:guard
       target-chain:string amount:decimal)
    (step
      (with-capability (TRANSFER_XCHAIN sender receiver amount target-chain)
        (validate-account sender)
        (validate-account receiver)
        ;; CROSS-CHAIN RECEIVERS MUST BE PRINCIPALS, checked on the source
        ;; chain before anything is debited: step 1 has NO rollback, so a pair
        ;; the credit step refuses destroys the debited tokens outright. A
        ;; vanity (non-principal) name is squattable on the target chain - any
        ;; observer of the public yield can pre-create it under their own guard
        ;; - while a principal's guard IS its name. Vanity names remain fully
        ;; usable for same-chain transfers.
        (enforce (validate-principal receiver-guard receiver)
          "cross-chain receiver must be the principal of its guard")
        ;; Inlined debit (there is no standalone one - see transfer-create).
        ;; It releases the moved weight from every open vote on THIS chain
        ;; before the tokens leave it, and it is fused with the yield below, so
        ;; the decrease is always paired with a credit on the target chain.
        (require-capability (DEBIT sender))
        (enforce (> amount 0.0) "debit amount must be positive")
        (enforce-unit amount)
        (with-read accounts sender { "balance" := sb }
          (enforce (<= amount sb) "insufficient funds")
          (update accounts sender { "balance": (- sb amount) }))
        (release-votes sender)
        (emit-event (TRANSFER sender "" amount))
        (yield
          { "receiver": receiver, "receiver-guard": receiver-guard
          , "amount": amount, "source-chain": (at 'chain-id (chain-data)) }
          target-chain)))
    (step
      (resume
        { "receiver" := receiver, "receiver-guard" := rg
        , "amount" := amount, "source-chain" := source-chain }
        (emit-event (TRANSFER "" receiver amount))
        ;; Inlined credit (no standalone balance-increasing writer - see
        ;; transfer-create). Safe: this step only runs as the SPV/defpact
        ;; resume of a real cross-chain send whose source-chain step already
        ;; debited `amount`. receiver was validate-principal'd above.
        (enforce (> amount 0.0) "credit amount must be positive")
        (enforce-unit amount)
        (validate-account receiver)
        (enforce-reserved receiver rg)
        (with-default-read accounts receiver
          { "balance": 0.0, "guard": rg }
          { "balance" := b, "guard" := g }
          (enforce (= g rg) "account guard mismatch")
          (write accounts receiver { "balance": (+ b amount), "guard": g }))
        (emit-event (TRANSFER_XCHAIN_RECD "" receiver amount source-chain))
        "cross-chain credit ok")))

  ;; -----------------------------
  ;; One-shot mint + supply view
  ;; -----------------------------

  (defun init-mint:string (recipients:[object{recipient}])
    @doc "One-shot: mint EXACTLY TOTAL-SUPPLY across the recipients, on       \
         \MINT-CHAIN only - the supply row requires minted = 0.0, so a second \
         \call through this path is impossible. Distribute to principal       \
         \accounts: a pre-created vanity name under a foreign guard aborts    \
         \the mint (griefing, not theft)."
    ;; The one-shot gate binds the FUNCTION, not the keyset: while the module
    ;; is unfrozen module admin can reset the row, so fixed supply is enforced
    ;; against governance itself only at the FROZEN-MODULE flip.
    (with-capability (MINT)
      (let ((chain (at 'chain-id (chain-data))))
        (enforce (= chain MINT-CHAIN) "mint happens on MINT-CHAIN only"))
      (let ((already (at 'minted (read supply SUPPLY-KEY))))
        (enforce (= already 0.0) "already minted"))
      (update supply SUPPLY-KEY { "minted": TOTAL-SUPPLY })
      (let ((total (fold (lambda (acc:decimal r:object{recipient})
                           (+ acc (at 'amount r)))
                         0.0 recipients)))
        (enforce (= total TOTAL-SUPPLY) "mint must distribute exactly TOTAL-SUPPLY"))
      (map (lambda (r:object{recipient})
             (let ((amt:decimal (at 'amount r))
                   (acct:string (at 'account r))
                   (g0:guard (at 'guard r)))
               (enforce (> amt 0.0) "recipient amount must be positive")
               (enforce-unit amt)
               ;; Inlined credit: the only balance increase behind the MINT
               ;; keyset, unreachable except through this function's one-shot
               ;; supply-row gate and the exact-TOTAL-SUPPLY check above.
               (validate-account acct)
               (enforce-reserved acct g0)
               (with-default-read accounts acct
                 { "balance": 0.0, "guard": g0 }
                 { "balance" := b, "guard" := g }
                 (enforce (= g g0) "account guard mismatch")
                 (write accounts acct { "balance": (+ b amt), "guard": g }))))
           recipients)
      "minted"))

  (defun chain-minted:decimal ()
    @doc "Amount minted on THIS chain (TOTAL-SUPPLY on MINT-CHAIN after the \
         \mint; 0.0 everywhere else). While the module is unfrozen this is  \
         \a lower bound on issuance, not a supply audit - treat it as       \
         \authoritative only once FROZEN-MODULE is set."
    (with-default-read supply SUPPLY-KEY { "minted": 0.0 } { "minted" := m } m))

  ;; -----------------------------
  ;; Advisory governance (chain-local: a holder votes where their tokens are)
  ;; -----------------------------

  (defun curr-time:time ()
    (at 'block-time (chain-data)))

  (defun reserve-account:string ()
    @doc "The reserve account name (cannot vote)."
    RESERVE-ACCOUNT)

  ;; -----------------------------
  ;; Accounts outside the float (non-voting register)
  ;; -----------------------------

  (defun non-voting?:bool (account:string)
    @doc "True if ACCOUNT is registered as an escrow outside the float. The \
         \reserve is excluded separately, by name, since this module derives \
         \it itself."
    (with-default-read non-voting account
      { "reason": "" } { "reason" := r }
      (!= r "")))

  (defun non-voting-reason:string (account:string)
    @doc "Why an account is excluded, for anyone auditing the register."
    (with-default-read non-voting account
      { "reason": "" } { "reason" := r }
      r))

  (defcap NON-VOTING-ADMIN ()
    @doc "Register or release an account as outside the float: the governance \
         \keyset, deliberately NOT gated on FROZEN-MODULE - the register must  \
         \stay correctable after the freeze, because getting it wrong in       \
         \either direction distorts a published tally."
    ;; It moves no funds but accepts ANY account name, so governance can bar a
    ;; named holder; what bounds it is disclosure - every change carries a
    ;; public reason and emits an event, so the register is auditable from
    ;; chain history.
    (enforce-keyset ADMIN-KS))

  (defun register-non-voting:string (account:string reason:string)
    @doc "Record ACCOUNT as an escrow whose holdings are outside the float \
         \and carry no vote. REASON is mandatory and public. Registration gates FUTURE ballots only - a ballot cast before it persists, so register every escrow BEFORE its first question opens."
    (with-capability (NON-VOTING-ADMIN)
      (validate-account account)
      (enforce (!= "" reason) "a public reason is required")
      (write non-voting account { "reason": reason })
      (emit-event (NON-VOTING-SET account reason))
      (format "{} registered as non-voting" [account])))

  (defun release-non-voting:string (account:string)
    @doc "Remove an account from the register - the correction path for an   \
         \account excluded in error. Evented: distributed holdings must never \
         \be silently disenfranchised."
    (with-capability (NON-VOTING-ADMIN)
      (with-read non-voting account { "reason" := r }
        (enforce (!= r "") "account is not registered"))
      (write non-voting account { "reason": "" })
      (emit-event (NON-VOTING-CLEARED account))
      (format "{} released" [account])))

  (defun set-ops-guard:string (g:guard)
    @doc "Governance names the ops authority (the routine tier). ALWAYS      \
         \available to the governance keyset, including after FROZEN-MODULE, \
         \so a lost or compromised ops device is replaced here with no code  \
         \upgrade, on any chain, forever; ops itself can never call this."
    (with-capability (OPS-ADMIN)
      ;; A guard is not introspectable, but its PRINCIPAL is a faithful, total
      ;; encoding of it - so validate the principal. Three checks, each closing
      ;; a shape governance could store by mistake.
      (let ((p (create-principal g)))

        ;; 1. TYPE: only literal keysets (k:/w:) are inert, always-evaluable
        ;; data. r: re-opens the redefinition hijack this table exists to
        ;; remove and dies on an undefined name; u: runs module code at
        ;; authorization time; c:/p: no signer can satisfy.
        (enforce (or (= "k:" (take 2 p)) (= "w:" (take 2 p)))
          (format "ops authority must be a plain keyset guard, not {}" [(take 2 p)]))

        ;; 2. PREDICATE: a w: principal carries its predicate as the suffix,
        ;; and a CUSTOM predicate runs module code at authorization time - the
        ;; same hazard user guards are refused for. Only the three builtins.
        ;; KNOWN GAP: a principal encodes the key-list HASH, not the count, so
        ;; an unsatisfiable keyset (e.g. keys-2 over one key) passes; that
        ;; bricks only the ops tier and governance simply calls this again -
        ;; verify the key count off-chain before signing.
        (enforce (or (= "k:" (take 2 p))
                 (or (= ":keys-all" (take -9 p))
                 (or (= ":keys-any" (take -9 p))
                     (= ":keys-2"   (take -7 p)))))
          "ops keyset must use a builtin predicate (keys-all, keys-any, keys-2)")

        ;; 3. NON-EMPTY: `keys-all` over ZERO keys is VACUOUSLY TRUE - it
        ;; would hand the routine tier to anyone signing nothing. Every empty
        ;; keyset shares one principal prefix (the key-list hash is a
        ;; constant); reject all of them.
        (enforce (!= EMPTY-KEYSET-PREFIX (take 45 p))
          "ops keyset must not be empty")

        (write ops-auth OPS-KEY { "guard": g })
        (emit-event (OPS-GUARD-SET p))))
    "ops guard set")

  (defun validate-proposal-id:bool (pid:string)
    @doc "Question ids are short ASCII slugs, chosen by the operator so that \
         \the same question carries the SAME id on every chain."
    ;; THE COLON BAN IS LOAD-BEARING, not neatness. Ballot rows are keyed
    ;; '<pid>:<account>', and account names may legally contain a colon
    ;; (every k: account does). Without this, question '1' and question
    ;; '1:alice' address overlapping ballot rows and one question can read
    ;; or overwrite the other's votes.
    (let ((len (length pid)))
      (enforce (and (>= len 1) (<= len 64)) "proposal id must be 1-64 characters"))
    (enforce (is-charset CHARSET_ASCII pid) "proposal id must be ASCII")
    (enforce (not (contains ":" pid)) "proposal id must not contain ':'")
    true)

  (defun open-ids:[string] ()
    @doc "Ids a ballot may be cast on RIGHT NOW: started, not ended, not      \
         \cancelled. Also the set `release-votes` walks - deliberately the    \
         \same horizon: a question that has not started carries no ballots,   \
         \so releasing against it would be a no-op."
    (let ((now (curr-time)))
      (with-default-read rcv-actives ACTIVE-KEY { "ids": [] } { "ids" := ids }
        (filter (lambda (pid:string)
                  (with-read rcv-proposals pid
                    { "starts-at" := sa, "ends-at" := ea, "cancelled" := cx }
                    (and (not cx) (and (>= now sa) (< now ea)))))
                ids))))

  (defun live-ids:[string] ()
    @doc "Ids still OCCUPYING A SLOT: not ended and not cancelled - which \
         \includes questions that have not started yet."
    ;; Distinct from open-ids and it must be: once a question can be authored
    ;; in advance, counting only the VOTABLE ones against MAX-ACTIVE-PROPOSALS
    ;; would let an unlimited number of pending questions be queued, and each
    ;; of them lands on every chain. The cap is on outstanding questions, not
    ;; on simultaneously-votable ones.
    (let ((now (curr-time)))
      (with-default-read rcv-actives ACTIVE-KEY { "ids": [] } { "ids" := ids }
        (filter (lambda (pid:string)
                  (with-read rcv-proposals pid
                    { "ends-at" := ea, "cancelled" := cx }
                    (and (not cx) (< now ea))))
                ids))))

  (defun create-proposal:string
      (pid:string title:string body:string options:[string]
       created-at:time starts-at:time ends-at:time)
    @doc "Open an ADMIN-AUTHORED ranked-choice question (ops tier; the       \
         \governance keyset always works too): 2..MAX-OPTIONS distinct named \
         \options, at most MAX-ACTIVE-PROPOSALS outstanding. Publish the     \
         \same question to every chain with IDENTICAL arguments - the id and \
         \all three instants are supplied rather than derived, because a     \
         \deadline computed from local block time gives every chain a        \
         \different deadline, which is a double-vote hole."
    (validate-proposal-id pid)
    (let ((now (curr-time)))
      ;; created-at is caller-supplied so that every chain computes the same
      ;; announce floor. Bounded both ways so it cannot be fabricated forward
      ;; nor backdated to dodge the floor.
      (enforce (<= (abs (diff-time created-at now)) (dec CREATED-SKEW-SECONDS))
        "created-at is too far from this chain's clock"))
    (enforce (>= (diff-time starts-at created-at) (dec (* MIN-ANNOUNCE-HOURS 3600)))
      "voting must open at least 12h after the question is authored")
    (enforce (> ends-at starts-at) "voting must close after it opens")
    (enforce (>= (diff-time ends-at starts-at) (dec (* MIN-VOTE-HOURS 3600)))
      "voting must run at least 24h")
    (enforce (<= (diff-time ends-at starts-at) (dec (* MAX-VOTE-HOURS 3600)))
      "a question may not run longer than 30 days")
    (enforce (and (> (length title) 0) (<= (length title) 120)) "title 1..120 chars")
    (enforce (<= (length body) 2000) "body <= 2000 chars")
    (let ((k (length options)))
      (enforce (and (>= k 2) (<= k MAX-OPTIONS))
        "2..5 options required")
      (enforce (= k (length (distinct options))) "options must be distinct")
      (map (lambda (o:string)
             (enforce (and (> (length o) 0) (<= (length o) 60))
               "each option 1..60 chars"))
           options))
    (with-capability (PROPOSAL-OPS)
      (let ((live (live-ids))
            (k (length options)))
        ;; The cap counts OUTSTANDING questions, not simultaneously-votable
        ;; ones - see live-ids. `insert` is what makes the id one-shot: a
        ;; second create under the same id aborts rather than overwriting a
        ;; live tally. The pairwise matrix is created HERE, K x K zeros, so
        ;; every question has a complete head-to-head record from its first
        ;; ballot.
        (enforce (< (length live) MAX-ACTIVE-PROPOSALS) "too many active proposals")
        (insert rcv-proposals pid
          { "title": title, "body": body, "options": options
          , "created": created-at, "starts-at": starts-at, "ends-at": ends-at
          , "cancelled": false
          , "scores": (make-list k 0.0)
          , "turnout": 0.0
          , "m": (make-list (* k k) 0.0) })
        (write rcv-actives ACTIVE-KEY { "ids": (+ live [pid]) })
        (emit-event (GOV-PROPOSED pid title options starts-at ends-at))
        pid)))

  (defun admin-cancel-proposal:string (pid:string reason:string)
    @doc "Close PID immediately (ops tier): tallies freeze where they stand  \
         \and the slot frees. A public REASON is mandatory and emitted -     \
         \cancellations are accountable, on-chain, forever."
    (enforce (and (> (length reason) 0) (<= (length reason) 2000))
      "a public reason is required (1..2000 chars)")
    (with-capability (PROPOSAL-OPS)
      (let ((now (curr-time)))
        (with-read rcv-proposals pid { "starts-at" := sa, "cancelled" := cx }
          ;; ONLY BEFORE VOTING OPENS: unbounded cancellation across every
          ;; chain is a selective veto - tallies are readable throughout, so
          ;; an operator could void the chains going the wrong way. Before the
          ;; start no ballot exists anywhere.
          (enforce (not cx) "proposal is already cancelled")
          (enforce (< now sa) "voting has already opened - a question cannot be cancelled once it is running"))
        ;; Recorded as a FLAG, not by moving a deadline, so a voided copy reads
        ;; back distinct from a normally-closed one and is never summed.
        (update rcv-proposals pid { "cancelled": true })
        (emit-event (GOV-CANCELLED pid reason))))
    "cancelled")

  (defun rank-pos:integer (ranking:[integer] opt:integer)
    @doc "Position of OPT in RANKING (0 = first choice), or -1 if unranked.  \
         \Total on the empty ranking (callers never store one with weight)."
    (if (= 0 (length ranking))
        -1
        (fold (lambda (acc:integer j:integer)
                (if (= (at j ranking) opt) j acc))
              -1
              (enumerate 0 (- (length ranking) 1)))))

  (defun borda-apply:[decimal]
      (scores:[decimal] options:[string] ranking:[integer] delta:decimal)
    @doc "SCORES with DELTA-weighted Borda points of RANKING applied: an     \
         \option ranked at position p (0-based) gains delta*(K-p) points;    \
         \unranked options are untouched, and negative delta removes a prior \
         \contribution exactly. THIS IS NOT THE RESULT - Borda scores reward \
         \ballot truncation, so they are published as a truncation           \
         \DIAGNOSTIC only; the authoritative result is the head-to-head      \
         \matrix (see get-head-to-head)."
    (let ((k (length options)))
      (map (lambda (i:integer)
             (let ((p (rank-pos ranking i)))
               (if (= p -1)
                   (at i scores)
                   (+ (at i scores) (* delta (- k p))))))
           (enumerate 0 (- k 1)))))

  (defun margins-apply:[decimal]
      (m:[decimal] k:integer ranking:[integer] delta:decimal)
    @doc "M with DELTA applied to every ordered pair RANKING expresses: a    \
         \ballot expresses i > j exactly when i is ranked AND j is either    \
         \unranked or ranked later, so ranked options beat unranked ones and \
         \two unranked options say nothing about each other. Negative delta  \
         \removes a prior contribution exactly (coefficients are only 0 or   \
         \1, so no rounding is possible at any precision)."
    ;; That single convention is what makes the cells depth-neutral: whether
    ;; or not j appears, a ballot ranking i first always credits m[i][j].
    ;; Index n is row-major: i = n / k, j = n mod k. The diagonal (i = j) is
    ;; never written.
    (let ((pos (map (lambda (i:integer) (rank-pos ranking i))
                    (enumerate 0 (- k 1)))))
      (map (lambda (n:integer)
             (let ((i (/ n k))
                   (j (mod n k)))
               (if (= i j)
                   (at n m)
                   (let ((pi (at i pos))
                         (pj (at j pos)))
                     (if (and (!= pi -1) (or (= pj -1) (< pi pj)))
                         (+ (at n m) delta)
                         (at n m))))))
           (enumerate 0 (- (* k k) 1)))))

  (defun apply-ballot-swap:[decimal]
      (m:[decimal] k:integer old-r:[integer] old-w:decimal
       new-r:[integer] new-w:decimal)
    @doc "PURE math: M with one ballot's pairwise contribution swapped -     \
         \remove OLD-R at OLD-W, then add NEW-R at NEW-W. NO write, NO       \
         \capability, NO state read: safe to be public because it cannot     \
         \mutate anything."
    ;; The authoritative matrix write is INLINED at the two real callers
    ;; (cast-vote-internal, release-votes) rather than exposed as its own
    ;; function, so the tally can only be written from a genuine vote or
    ;; release. K is passed by the in-module caller as the real option count
    ;; (never a smaller value, which would truncate the stored row).
    (let ((cleared (if (> old-w 0.0) (margins-apply m k old-r (- old-w)) m)))
      (if (> new-w 0.0) (margins-apply cleared k new-r new-w) cleared)))

  (defun cast-vote:string (pid:string account:string ranking:[integer])
    @doc "Rank the options (ordered indices, best first; partial rankings    \
         \allowed). Weight is the caller's balance on THIS chain at the      \
         \moment of voting; re-voting replaces the ballot; the reserve and   \
         \registered escrows are barred."
    (with-capability (VOTE pid account)
      (cast-vote-internal pid account ranking)))

  (defun cast-vote-internal:string (pid:string account:string ranking:[integer])
    @doc "The ballot write. EVERY precondition is enforced HERE, behind the  \
         \VOTE capability - never only in the cast-vote wrapper: Pact has no \
         \private functions, so this is publicly callable, and a public      \
         \function must never trust its wrapper."
    (require-capability (VOTE pid account))
    (enforce (!= account RESERVE-ACCOUNT) "the community reserve cannot vote")
    ;; Registered escrows do not vote: an explicit register of NAMES, not a
    ;; rule about account types (see non-voting-row).
    ;; `barred` is LET-BOUND before its enforce, never read inside the
    ;; condition: a table read inside an enforce condition is
    ;; lineage-dependent (accepted on KDA-CE nodes, rejected on upstream
    ;; lineages, invisible to the REPL).
    (let ((barred (non-voting? account)))
      (enforce (not barred)
        "this account is registered as non-voting (an escrow outside the float)"))
    (with-read rcv-proposals pid
      { "starts-at" := sa, "ends-at" := ea, "cancelled" := cx
      , "options" := opts, "scores" := ss, "turnout" := tn, "m" := mm }
      ;; The window is [starts-at, ends-at) against THIS chain's block time;
      ;; both instants are absolute and identical on every chain, so every
      ;; copy opens and closes together up to the chains' own clock spread.
      (enforce (not cx) "this question was cancelled")
      (enforce (>= (curr-time) sa) "voting has not opened yet")
      (enforce (< (curr-time) ea) "voting closed")
      (let ((k (length opts))
            (r (length ranking)))
        (enforce (and (>= r 1) (<= r k)) "ranking: 1..K entries")
        (enforce (= r (length (distinct ranking))) "ranking entries must be distinct")
        (map (lambda (o:integer)
               (enforce (and (>= o 0) (< o k)) "ranking entry out of range"))
             ranking))
      (let ((weight (at 'balance (read accounts account)))
            (vkey (format "{}:{}" [pid account])))
        (enforce (> weight 0.0) "no voting weight")
        (with-default-read rcv-ballots vkey { "ranking": [], "weight": 0.0 }
          { "ranking" := old-r, "weight" := old-w }
          ;; Remove the previous ballot's contribution, then add the new one.
          ;; Borda scores and the pairwise matrix swap from the SAME
          ;; (ranking, weight) pairs in ONE row update, so the two records
          ;; can never drift apart. INLINED - no standalone tally writer.
          (let* ((k (length opts))
                 (cleared (if (> old-w 0.0)
                              (borda-apply ss opts old-r (- old-w))
                              ss))
                 (applied (borda-apply cleared opts ranking weight)))
            (update rcv-proposals pid
              { "scores": applied
              , "turnout": (+ (- tn old-w) weight)
              , "m": (apply-ballot-swap mm k old-r old-w ranking weight) })
            (write rcv-ballots vkey { "ranking": ranking, "weight": weight })))
        (emit-event (GOV-VOTED pid account ranking weight))
        "vote recorded")))

  (defun release-votes:string (account:string)
    @doc "Permissionless vote-weight sync: shrink the account's recorded    \
         \ballot weight on every OPEN question down to its CURRENT balance  \
         \(the live-vote release rule). Derives everything from real state, \
         \so a public call can only correct stale weights, never forge      \
         \ballots; called automatically after every balance decrease."
    ;; The walk is bounded by MAX-ACTIVE-PROPOSALS (open-ids can never return
    ;; more), so the release work a debit carries is small and constant.
    (let ((bal (with-default-read accounts account { "balance": 0.0 } { "balance" := b } b)))
      (map (lambda (pid:string)
             (let ((vkey (format "{}:{}" [pid account])))
               (with-default-read rcv-ballots vkey { "ranking": [], "weight": 0.0 }
                 { "ranking" := r, "weight" := w }
                 (if (> w bal)
                   (let ((excess (- w bal)))
                     (with-read rcv-proposals pid
                       { "options" := opts, "scores" := ss, "turnout" := tn, "m" := mm }
                       ;; Shrink Borda and the pairwise record by the same
                       ;; excess in one update: an EMPTY new ranking removes
                       ;; and adds nothing back. INLINED - no standalone tally
                       ;; writer.
                       (update rcv-proposals pid
                         { "scores": (borda-apply ss opts r (- excess))
                         , "turnout": (- tn excess)
                         , "m": (apply-ballot-swap mm (length opts) r excess [] 0.0) }))
                     (update rcv-ballots vkey { "weight": bal })
                     "released")
                   "unchanged"))))
           (open-ids))
      "synced"))

  (defun get-proposal:object{rcv-proposal} (pid:string)
    (read rcv-proposals pid))

  (defun get-ballot:object{rcv-ballot} (pid:string account:string)
    (read rcv-ballots (format "{}:{}" [pid account])))

  (defun get-results:object (pid:string)
    @doc "Options + Borda scores + turnout + closed flag. The SCORES here are \
         \a truncation DIAGNOSTIC, not the result - see borda-apply; for the  \
         \authoritative outcome call get-head-to-head. ADVISORY either way:   \
         \no quorum, nothing executes."
    (with-read rcv-proposals pid
      { "title" := t, "starts-at" := sa, "ends-at" := ea, "cancelled" := cx
      , "options" := o, "scores" := s, "turnout" := tn }
      { "title": t, "options": o, "scores": s, "turnout": tn
      , "starts-at": sa, "ends-at": ea, "cancelled": cx
      ;; `closed` means "no longer taking votes", which a cancelled question is
      ;; too. `cancelled` is reported SEPARATELY and must never be folded into
      ;; it: a combining program has to be able to tell a question that ran and
      ;; ended from one that was voided, because the second must never be
      ;; summed.
      , "closed": (or cx (>= (curr-time) ea))
      , "started": (>= (curr-time) sa) }))

  (defun h2h-wins:[decimal] (m:[decimal] k:integer)
    @doc "Copeland win-count per option: how many of the other K-1 options it \
         \beats head to head. A strict majority is required to count a win,   \
         \so an exact pairwise tie credits neither side."
    (map (lambda (i:integer)
           (fold (lambda (acc:decimal j:integer)
                   (if (or (= i j)
                           (<= (at (+ (* i k) j) m) (at (+ (* j k) i) m)))
                       acc
                       (+ acc 1.0)))
                 0.0
                 (enumerate 0 (- k 1))))
         (enumerate 0 (- k 1))))

  (defun get-head-to-head:object (pid:string)
    @doc "THE AUTHORITATIVE ADVISORY RESULT for PID: pairs (the K x K matrix, \
         \row-major - pairs[i*K + j] is the ballot weight preferring option i \
         \to option j), wins (Copeland count per option) and condorcet (the   \
         \option that beats EVERY other head to head, or \"\" when none       \
         \does). Still advisory: nothing executes, there is no quorum, and a  \
         \cycle is a real possible outcome that should be reported as one     \
         \rather than broken by an arbitrary rule."
    (with-read rcv-proposals pid
      { "title" := t, "starts-at" := sa, "ends-at" := ea, "cancelled" := cx
      , "options" := o, "turnout" := tn, "m" := m }
      (let* ((k (length o))
             (wins (h2h-wins m k))
             (top (- (dec k) 1.0))
             (cw (fold (lambda (acc:string i:integer)
                         (if (= (at i wins) top) (at i o) acc))
                       "" (enumerate 0 (- k 1)))))
        { "title": t, "options": o, "turnout": tn
        , "starts-at": sa, "ends-at": ea, "cancelled": cx
        , "closed": (or cx (>= (curr-time) ea))
        , "pairs": m, "wins": wins
        , "condorcet": cw })))

  ;; ---- dedicated voting key (hot key votes; the main key stays cold) ----

  (defun set-vote-key:string (account:string guard:guard)
    @doc "Register/replace the account's dedicated voting guard: MAIN account \
         \guard only (via VOTE-KEY-ADMIN), so the hot key can never re-point  \
         \itself, and the vote key can ONLY vote. Use a PLAIN keyset (a user  \
         \guard or undefined keyset-ref can abort the vote); register it on   \
         \every chain you intend to vote from - module tables are chain-local \
         \- though an unregistered chain still votes with the main guard."
    (let ((vk (create-principal guard)))
      (with-capability (VOTE-KEY-ADMIN account vk)
        (write vote-delegates account { "guard": guard, "active": true })
        (emit-event (VOTE-KEY-SET account vk))))
    "vote key set")

  (defun clear-vote-key:string (account:string)
    @doc "Deactivate the account's voting key (MAIN guard via                 \
         \VOTE-KEY-ADMIN). Requires a prior registration; voting falls back   \
         \to the main guard alone."
    (with-capability (VOTE-KEY-ADMIN account "")
      (update vote-delegates account { "active": false })
      (emit-event (VOTE-KEY-CLEARED account)))
    "vote key cleared")

  (defun get-vote-key:object{vote-delegate} (account:string)
    @doc "Read-only: the account's vote-key registration ({guard, active});  \
         \an inactive main-guard default when never registered."
    (with-default-read vote-delegates account
      { "guard": (at 'guard (read accounts account)), "active": false }
      { "guard" := g, "active" := a }
      { "guard": g, "active": a }))
)

;; Deploy footer — two modes via tx data:
;;   upgrade:false  FRESH deploy: create tables + seed the per-chain supply row.
;;   upgrade:true   touch nothing (create-table re-runs abort upgrades). A NEW
;;                  table on an already-deployed chain is a separate one-off
;;                  admin tx per table:
;;                  ((acquire-module-admin <ns>.fixed-supply-token-gov)
;;                   (create-table <ns>.fixed-supply-token-gov.<table>))
;; A chain missing rcv-actives BRICKS every debit (the release walk reads it).
;; Verify every table exists on every chain BEFORE flipping FROZEN-MODULE:
;; after the flip create-table is impossible forever and there is no on-chain
;; recovery.
(if (read-msg 'upgrade)
  [ "upgrade" ]
  [ (create-table accounts)
    (create-table supply)
    (create-table rcv-proposals)
    (create-table rcv-ballots)
    (create-table rcv-actives)
    (create-table vote-delegates)
    (create-table ops-auth)
    (create-table non-voting)
    (insert supply SUPPLY-KEY { "minted": 0.0 }) ])
