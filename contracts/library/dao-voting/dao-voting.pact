(module dao-voting GOV

  @doc "PCO library template: membership-based on-chain voting.                  \
  \                                                                              \
  \A governed set of MEMBER accounts votes on proposals - one member, one       \
  \vote, immutable once cast. A proposal passes when, at close, participation   \
  \meets a QUORUM percentage of the CURRENT member set and yes-votes meet a     \
  \THRESHOLD percentage of the yes+no votes cast by CURRENT members. This      \
  \module custodies NO funds: it produces an auditable, replayable on-chain    \
  \decision record (pair it with the multisig-treasury template to act on      \
  \passed proposals).                                                           \
  \                                                                              \
  \Model:                                                                        \
  \  - Governance configures members (with their guards), quorum-pct and        \
  \    threshold-pct at init, and may rotate them or cancel proposals.          \
  \  - Any member may `propose` with a voting deadline. The quorum and          \
  \    threshold percentages are SNAPSHOTTED into the proposal at propose       \
  \    time - a later rotation cannot move the passage bar on an open           \
  \    proposal. Membership stays dynamic (see close).                          \
  \  - Members `vote` yes/no/abstain before the deadline; one immutable vote    \
  \    per member per proposal.                                                 \
  \  - After the deadline anyone may `close`, which counts ONLY votes from      \
  \    members current at close time (rotating a member out revokes their       \
  \    in-flight votes), checks quorum and threshold, and settles the           \
  \    proposal as passed or rejected.                                          \
  \                                                                              \
  \All percentage math is integer-only (vote counts scaled by 100) - no        \
  \decimal division anywhere.                                                   \
  \                                                                              \
  \Deployment checklist (see README.md):                                         \
  \  1. Wrap in your namespace; replace the 'dao-voting-gov' keyset.             \
  \  2. Deploy, then (init members guards quorum-pct threshold-pct) once.        \
  \  3. Validate on devnet before mainnet."

  ;; -----------------------------
  ;; Governance
  ;; -----------------------------

  (defconst GOV_KEYSET:string "dao-voting-gov"
    @doc "Governance keyset name. Replace with your deployed, namespace- \
         \qualified keyset (multi-sig recommended). Governance rotates the \
         \member set, cancels proposals, and upgrades the module. It cannot \
         \vote or change a cast vote, and each proposal's quorum/threshold \
         \are locked at propose time (rotating percentages affects only \
         \future proposals). Membership is deliberately NOT locked: rotation \
         \revokes in-flight votes (the compromise response), which also means \
         \governance retains influence over open proposals through the member \
         \list itself - every rotation emits MEMBERS_ROTATED for audit.")

  (defcap GOV ()
    @doc "Module governance: init/rotate members, cancel proposals, upgrade."
    (enforce-guard (keyset-ref-guard GOV_KEYSET)))

  ;; -----------------------------
  ;; Schemas & tables
  ;; -----------------------------

  (defschema config-row
    @doc "Singleton voting config. Percentages are integers in [1,100]."
    members:[string]        ;; enrolled member account names
    quorum-pct:integer      ;; min participation as % of current members
    threshold-pct:integer)  ;; min yes as % of (yes+no) valid votes

  (deftable config:{config-row})

  (defschema member-row
    @doc "Row-level guard for a member account, captured at enrollment."
    guard:guard)

  (deftable member-guards:{member-row})

  (defschema proposal-row
    @doc "A proposal and its recorded votes. quorum-pct/threshold-pct are \
         \snapshotted from config at propose time, so a later rotation cannot \
         \move the passage bar on an open proposal. Vote lists are bounded by \
         \the member count. Final counts are the CURRENT-member-filtered \
         \tallies recorded at close."
    proposer:string
    title:string
    deadline:time
    quorum-pct:integer
    threshold-pct:integer
    yes:[string]
    no:[string]
    abstain:[string]
    status:string           ;; "open" | "passed" | "rejected" | "cancelled"
    final-yes:integer
    final-no:integer
    final-abstain:integer)

  (deftable proposals:{proposal-row})

  (defconst CONFIG_KEY:string "config")

  (defconst STATUS_OPEN:string "open")
  (defconst STATUS_PASSED:string "passed")
  (defconst STATUS_REJECTED:string "rejected")
  (defconst STATUS_CANCELLED:string "cancelled")

  (defconst CHOICE_YES:string "yes")
  (defconst CHOICE_NO:string "no")
  (defconst CHOICE_ABSTAIN:string "abstain")

  (defconst MAX_MEMBERS:integer 200
    @doc "Upper bound on the member set. `close` filters the vote lists \
         \against the member list (O(members x voters)); measured at ~2.7k \
         \gas for 200 all-voting members (REPL table gas model) - generous \
         \headroom under the 150k per-tx ceiling while keeping settlement \
         \costs predictable.")

  ;; -----------------------------
  ;; Events
  ;; -----------------------------

  (defcap PROPOSED (id:string proposer:string title:string deadline:time)
    @event true)

  (defcap VOTED (id:string member:string choice:string)
    @event true)

  (defcap CLOSED (id:string status:string yes:integer no:integer abstain:integer)
    @event true)

  (defcap CANCELLED (id:string)
    @event true)

  (defcap MEMBERS_ROTATED (members:[string] quorum-pct:integer threshold-pct:integer)
    @event true)

  ;; -----------------------------
  ;; Internal helpers
  ;; -----------------------------

  (defun chain-time:time ()
    @doc "Current block time (the PARENT block's timestamp on Chainweb - about \
         \one block behind wall-clock; do not build second-granularity \
         \deadlines)."
    (at 'block-time (chain-data)))

  (defun get-config:object{config-row} ()
    (read config CONFIG_KEY))

  (defun is-member:bool (account:string)
    (contains account (at 'members (get-config))))

  (defcap MEMBER-AUTH (account:string)
    @doc "Authenticate ACCOUNT as a current member: it must be in the member \
         \set AND the caller must satisfy its enrolled guard. As a capability, \
         \a member scopes their signature to (dao-voting.MEMBER-AUTH \"alice\"), \
         \so a voting signature does NOT also authorize other operations the \
         \same key could satisfy in the transaction."
    ; NODE-SAFETY: `is-member` reads the config table. A table read inside an
    ; `enforce` condition passes in the REPL but FAILS on the KDA-CE node.
    ; Bind the read to a local FIRST, then enforce the local.
    (let ((member-ok (is-member account)))
      (enforce member-ok "not a member"))
    (with-read member-guards account { 'guard := g }
      (enforce-guard g)))

  (defun enforce-valid-config:bool (members:[string] guards:[guard]
                                    quorum-pct:integer threshold-pct:integer)
    @doc "Shared validation for the member set. Rejects an empty set, a \
         \members/guards length mismatch, duplicate members (each member \
         \votes at most once, so duplicates silently deflate quorum), and \
         \percentages outside [1,100]."
    (enforce (> (length members) 0) "at least one member required")
    (enforce (<= (length members) MAX_MEMBERS)
      (format "member count exceeds maximum of {}" [MAX_MEMBERS]))
    (enforce (= (length members) (length guards)) "members/guards length mismatch")
    (enforce (= (length (distinct members)) (length members)) "duplicate members")
    (enforce (and (>= quorum-pct 1) (<= quorum-pct 100))
      "quorum-pct must be in [1,100]")
    (enforce (and (>= threshold-pct 1) (<= threshold-pct 100))
      "threshold-pct must be in [1,100]"))

  ;; -----------------------------
  ;; Lifecycle & governance
  ;; -----------------------------

  (defun init:string (members:[string] guards:[guard]
                      quorum-pct:integer threshold-pct:integer)
    @doc "One-time setup: enroll the member set (guards align positionally) \
         \and set quorum/threshold percentages. The config insert enforces \
         \one-time setup."
    (with-capability (GOV)
      (enforce-valid-config members guards quorum-pct threshold-pct)
      (insert config CONFIG_KEY
        { 'members: members, 'quorum-pct: quorum-pct, 'threshold-pct: threshold-pct })
      (zip (lambda (m:string g:guard) (write member-guards m { 'guard: g }))
           members guards)
      (emit-event (MEMBERS_ROTATED members quorum-pct threshold-pct))
      "initialized"))

  (defun rotate-members:string (members:[string] guards:[guard]
                                quorum-pct:integer threshold-pct:integer)
    @doc "Governance: replace the member set and percentages. Open proposals \
         \are NOT cancelled, but `close` counts only votes from members \
         \current at close time - rotating a member out revokes their \
         \in-flight votes. Respond to a key compromise by REMOVING the \
         \member's name: re-enrolling the same name with a new guard revives \
         \votes the old key cast on still-open proposals."
    (with-capability (GOV)
      (enforce-valid-config members guards quorum-pct threshold-pct)
      (update config CONFIG_KEY
        { 'members: members, 'quorum-pct: quorum-pct, 'threshold-pct: threshold-pct })
      (zip (lambda (m:string g:guard) (write member-guards m { 'guard: g }))
           members guards)
      (emit-event (MEMBERS_ROTATED members quorum-pct threshold-pct))
      "rotated"))

  ;; -----------------------------
  ;; Proposal flow
  ;; -----------------------------

  (defun propose:string (id:string proposer:string title:string deadline:time)
    @doc "A member opens a proposal. ID must be unique. DEADLINE must be in \
         \the future; voting is possible strictly before it. The proposer \
         \does NOT auto-vote (they may vote explicitly like any member). The \
         \current quorum/threshold percentages are snapshotted into the \
         \proposal, locking its passage bar. The proposer signs scoped to \
         \MEMBER-AUTH."
    (with-capability (MEMBER-AUTH proposer)
      (enforce (!= title "") "title required")
      (let ((now (chain-time)))
        (enforce (< now deadline) "deadline must be in the future"))
      (let ((cfg (get-config)))
        (insert proposals id
          { 'proposer: proposer
          , 'title: title
          , 'deadline: deadline
          , 'quorum-pct: (at 'quorum-pct cfg)
          , 'threshold-pct: (at 'threshold-pct cfg)
          , 'yes: []
          , 'no: []
          , 'abstain: []
          , 'status: STATUS_OPEN
          , 'final-yes: 0
          , 'final-no: 0
          , 'final-abstain: 0 }))
      (emit-event (PROPOSED id proposer title deadline))
      id))

  (defun vote:string (id:string member:string choice:string)
    @doc "A member casts an immutable vote (yes | no | abstain) on an open \
         \proposal, strictly before its deadline. One vote per member per \
         \proposal; there is no vote-change (a member unsure at vote time \
         \should wait - voting is possible until the deadline). The member \
         \signs scoped to MEMBER-AUTH."
    (with-capability (MEMBER-AUTH member)
      (enforce (contains choice [CHOICE_YES CHOICE_NO CHOICE_ABSTAIN])
        "choice must be yes, no, or abstain")
      (with-read proposals id
        { 'deadline := deadline, 'yes := yes, 'no := no
        , 'abstain := abstain, 'status := status }
        (enforce (= status STATUS_OPEN) "proposal is not open")
        (let ((now (chain-time)))
          (enforce (< now deadline) "voting deadline has passed"))
        (let ((all-voters (+ yes (+ no abstain))))
          (enforce (not (contains member all-voters)) "member already voted"))
        (if (= choice CHOICE_YES)
          (update proposals id { 'yes: (+ yes [member]) })
          (if (= choice CHOICE_NO)
            (update proposals id { 'no: (+ no [member]) })
            (update proposals id { 'abstain: (+ abstain [member]) })))
        (emit-event (VOTED id member choice))
        id)))

  (defun close:string (id:string)
    @doc "Settle a proposal after its deadline. Callable by anyone: the \
         \recorded votes are the authorization, and settlement is \
         \deterministic. Uses the proposal's SNAPSHOTTED quorum/threshold \
         \(locked at propose) over the CURRENT member set (so rotating a \
         \member out revokes their in-flight votes), then:                    \
         \quorum  = participation*100 >= quorum-pct * member-count           \
         \passed  = quorum AND yes > 0 AND yes*100 >= threshold-pct*(yes+no). \
         \Abstain votes count toward quorum but not toward the threshold. \
         \Records the filtered tallies and emits CLOSED."
    (with-read proposals id
      { 'deadline := deadline, 'yes := yes, 'no := no
      , 'abstain := abstain, 'status := status
      , 'quorum-pct := quorum-pct, 'threshold-pct := threshold-pct }
      (enforce (= status STATUS_OPEN) "proposal is not open")
      (let ((now (chain-time)))
        (enforce (>= now deadline) "voting deadline has not passed"))
      (let* ((cfg (get-config))
             (members (at 'members cfg))
             (in-members (lambda (m:string) (contains m members)))
             (valid-yes (length (filter in-members yes)))
             (valid-no (length (filter in-members no)))
             (valid-abstain (length (filter in-members abstain)))
             (participation (+ valid-yes (+ valid-no valid-abstain)))
             (quorum-met (>= (* participation 100) (* quorum-pct (length members))))
             (threshold-met (and (> valid-yes 0)
                                 (>= (* valid-yes 100)
                                     (* threshold-pct (+ valid-yes valid-no)))))
             (new-status (if (and quorum-met threshold-met)
                           STATUS_PASSED
                           STATUS_REJECTED)))
        (update proposals id
          { 'status: new-status
          , 'final-yes: valid-yes
          , 'final-no: valid-no
          , 'final-abstain: valid-abstain })
        (emit-event (CLOSED id new-status valid-yes valid-no valid-abstain))
        new-status)))

  (defun cancel:string (id:string)
    @doc "Governance cancels an open proposal."
    (with-capability (GOV)
      (with-read proposals id { 'status := status }
        (enforce (= status STATUS_OPEN) "proposal is not open")
        (update proposals id { 'status: STATUS_CANCELLED })
        (emit-event (CANCELLED id))
        id)))

  ;; -----------------------------
  ;; Views
  ;; -----------------------------

  (defun get-proposal:object{proposal-row} (id:string)
    (read proposals id))

  (defun has-voted:bool (id:string member:string)
    (with-read proposals id { 'yes := yes, 'no := no, 'abstain := abstain }
      (contains member (+ yes (+ no abstain)))))
)
