(module property-lease GOV

  @doc "PCO library template: on-chain rental-lease rails.                       \
  \                                                                              \
  \A registry of PROPERTIES, each holding many LEASES. All money sits in one    \
  \capability-guarded vault coin account; an internal bucket ledger earmarks    \
  \every payment per property into TAX / REPAIRS / BENEFICIARY / LANDLORD       \
  \shares. Jurisdiction-specific law is NOT on-chain: each lease anchors the    \
  \hash of a signed off-chain lease document (rails on-chain, contract          \
  \off-chain).                                                                   \
  \                                                                              \
  \Model:                                                                        \
  \  - A landlord self-registers a property with immutable revenue-split basis  \
  \    points (tax / repairs / a configurable BENEFICIARY - a protocol fee,     \
  \    co-owner, or DAO treasury; the landlord takes the residual). Splits are  \
  \    locked at registration so the beneficiary cannot be zeroed later.        \
  \  - Landlord + tenant co-sign to create or renew a lease (mutual assent).    \
  \  - The tenant (or anyone) escrows the security deposit, then rent is paid   \
  \    one period at a time - rent splits into the buckets, a flat late fee     \
  \    past grace goes to the landlord, and the landlord residual absorbs       \
  \    rounding dust so the vault conserves to the last decimal.                \
  \  - Landlord withdraws TAX / REPAIRS / LANDLORD to any payee (evented with   \
  \    a memo). BENEFICIARY is push-only to its fixed destination.              \
  \  - Either party may give notice to shorten the term; at the end the         \
  \    landlord files ONE capped deposit claim inside a claim window, after     \
  \    which anyone may settle (claim to landlord, remainder to tenant).        \
  \                                                                              \
  \Governance is upgrade-only: no function under GOV touches leases, buckets,   \
  \or the vault.                                                                 \
  \                                                                              \
  \KEY TRUST LIMITATION: v1 has NO ARBITER. The landlord's capped deposit       \
  \claim is honored unilaterally - the tenant cannot dispute it on-chain. Use   \
  \this only where the off-chain document and legal system are the real         \
  \backstop. See README.md and AUDIT.md.                                        \
  \                                                                              \
  \Deployment checklist (see README.md):                                        \
  \  1. Wrap in your namespace; replace the 'property-lease-gov' keyset.        \
  \  2. Deploy and create-table (properties, leases, buckets).                  \
  \  3. Validate on devnet before mainnet."

  ;; -----------------------------
  ;; Governance (upgrade-only; no fund paths)
  ;; -----------------------------

  (defconst GOV_KEYSET:string "property-lease-gov"
    @doc "Governance keyset name. Replace with your deployed, namespace- \
         \qualified keyset (multi-sig recommended). Governance can upgrade the \
         \module and nothing else - no function under GOV touches leases, \
         \buckets, or the vault.")

  (defcap GOV ()
    @doc "Module governance: upgrade only."
    (enforce-guard (keyset-ref-guard GOV_KEYSET)))

  ;; -----------------------------
  ;; Vault (capability-guarded)
  ;; -----------------------------
  ;; Internal token guarding the vault coin account and all bucket mutation.
  ;; Weak body by design; every public acquisition is either behind a real
  ;; guard (landlord withdrawals) or pays only recorded accounting to a stored
  ;; destination (pay-rent credits, push-beneficiary, settle-deposit).

  (defcap VAULT ()
    @doc "Internal vault + bucket-ledger token. NEVER a public authorization: \
         \acquired only inside this module, always after a real guard check or \
         \bounded to recorded accounting paid to a stored account."
    true)

  (defconst VAULT-GUARD (create-capability-guard (VAULT)))
  (defconst VAULT-ACCOUNT (create-principal VAULT-GUARD))

  ;; -----------------------------
  ;; Limits
  ;; -----------------------------

  (defconst MIN-TIME (time "1970-01-01T00:00:00Z"))
  (defconst MAX-TIME (time "2200-01-01T00:00:00Z"))
  (defconst BPS-DENOM 10000)
  (defconst MAX-ID-LEN 64)
  (defconst MAX-MEMO-LEN 256)

  (defconst BUCKET-TAX "TAX")
  (defconst BUCKET-REPAIRS "REPAIRS")
  (defconst BUCKET-BENEFICIARY "BENEFICIARY")
  (defconst BUCKET-LANDLORD "LANDLORD")

  ;; -----------------------------
  ;; Schemas & tables
  ;; -----------------------------

  (defschema property
    landlord:string          ; landlord coin account (payout target)
    landlord-guard:guard     ; authorizes all landlord operations
    beneficiary:string       ; configurable revenue-share beneficiary account
    beneficiary-guard:guard
    info:string              ; free-form premises pointer/hash
    tax-bps:integer          ; immutable after registration
    repairs-bps:integer
    beneficiary-bps:integer
    active:bool)             ; false = no NEW leases (withdrawals unaffected)
  (deftable properties:{property})

  (defschema lease
    property-id:string
    tenant:string
    tenant-guard:guard
    doc-hash:string          ; hash of the signed off-chain lease document
    rent:decimal             ; KDA per period
    period-days:integer
    grace-days:integer
    late-fee:decimal         ; flat KDA, entirely to the landlord bucket
    deposit:decimal
    deposit-held:decimal
    start:time
    end:time
    paid-through:time        ; rent covered until this instant
    notice-days:integer
    claim-window-days:integer
    claim-amount:decimal
    claim-filed:bool)
  (deftable leases:{lease})

  (defschema bucket balance:decimal)
  (deftable buckets:{bucket}) ; key: "<property-id>|<BUCKET>"

  ;; -----------------------------
  ;; Events
  ;; -----------------------------

  (defcap PROPERTY-REGISTERED (property-id:string landlord:string) @event true)
  (defcap LEASE-SIGNED (lease-id:string property-id:string tenant:string rent:decimal doc-hash:string) @event true)
  (defcap DEPOSIT-PAID (lease-id:string payer:string amount:decimal) @event true)
  (defcap RENT-PAID (lease-id:string payer:string amount:decimal late-fee:decimal paid-through:time) @event true)
  (defcap WITHDRAWAL (property-id:string bucket:string amount:decimal payee:string memo:string) @event true)
  (defcap DEPOSIT-CLAIMED (lease-id:string amount:decimal memo:string) @event true)
  (defcap DEPOSIT-SETTLED (lease-id:string to-tenant:decimal to-landlord:decimal) @event true)
  (defcap NOTICE-GIVEN (lease-id:string new-end:time) @event true)
  (defcap LEASE-RENEWED (lease-id:string new-end:time new-rent:decimal) @event true)
  (defcap PROPERTY-ACTIVE-SET (property-id:string active:bool) @event true)

  ;; -----------------------------
  ;; Party authentication (scoped capabilities)
  ;; -----------------------------
  ;; As capabilities, a party scopes their signature to exactly one action on
  ;; one property/lease, instead of signing unscoped. The stored guard is read
  ;; and bound in the enforce-guard ARGUMENT position (node-safe: a guard read
  ;; there is not a table read inside an enforce CONDITION).

  (defcap LANDLORD (property-id:string)
    @doc "Authenticate the landlord of PROPERTY-ID via the guard enrolled at \
         \registration."
    (enforce-guard (at 'landlord-guard (read properties property-id))))

  (defcap TENANT (lease-id:string)
    @doc "Authenticate the tenant of LEASE-ID via the guard enrolled at lease \
         \creation."
    (enforce-guard (at 'tenant-guard (read leases lease-id))))

  (defcap PARTY (lease-id:string)
    @doc "Authenticate EITHER party to LEASE-ID (landlord or tenant). Both \
         \guards are bound to locals FIRST (node-safe), then enforce-one \
         \accepts whichever the caller satisfies. A party scopes their \
         \termination signature to (property-lease.PARTY \"lease-id\")."
    (let* ((l (read leases lease-id))
           (lg (at 'landlord-guard (read properties (at 'property-id l))))
           (tg (at 'tenant-guard l)))
      (enforce-one "landlord or tenant signature required"
        [ (enforce-guard lg) (enforce-guard tg) ])))

  ;; -----------------------------
  ;; Validation helpers (pure)
  ;; -----------------------------

  (defun enforce-valid-id (id:string)
    (enforce (!= id "") "id empty")
    (enforce (<= (length id) MAX-ID-LEN) "id too long")
    (enforce (is-charset 0 id) "id must be ASCII")
    (enforce (not (contains "|" id)) "id must not contain |"))

  (defun enforce-precision (amount:decimal msg:string)
    (enforce (= (floor amount 12) amount) msg))

  (defun enforce-positive (amount:decimal msg:string)
    (enforce (> amount 0.0) msg)
    (enforce-precision amount msg))

  (defun enforce-non-negative (amount:decimal msg:string)
    (enforce (>= amount 0.0) msg)
    (enforce-precision amount msg))

  (defun enforce-time-bounds (t:time msg:string)
    ;; add-time can silently wrap int64; bounding every stored time closes it
    (enforce (>= t MIN-TIME) msg)
    (enforce (<= t MAX-TIME) msg))

  (defun chain-now:time ()
    (at 'block-time (chain-data)))

  (defun split-amount:decimal (amount:decimal bps:integer)
    ;; floor to coin precision; the landlord residual absorbs the dust,
    ;; so the four cuts always sum EXACTLY to the rent (conservation)
    (floor (/ (* amount (dec bps)) 10000.0) 12))

  ;; -----------------------------
  ;; Internal ledger (VAULT-only)
  ;; -----------------------------

  (defun bucket-key:string (property-id:string bucket:string)
    (format "{}|{}" [property-id bucket]))

  (defun credit-bucket:string (property-id:string bucket:string amount:decimal)
    (require-capability (VAULT))
    (if (> amount 0.0)
      (let ((key (bucket-key property-id bucket)))
        (with-default-read buckets key { "balance": 0.0 } { "balance" := bal }
          (write buckets key { "balance": (+ bal amount) })))
      "zero credit skipped"))

  (defun debit-bucket:string (property-id:string bucket:string amount:decimal)
    (require-capability (VAULT))
    (let* ((key (bucket-key property-id bucket))
           (bal (at 'balance (read buckets key))))
      (enforce (>= bal amount) "insufficient bucket balance")
      (update buckets key { "balance": (- bal amount) })))

  (defun vault-pay:string (payee:string payee-guard:guard amount:decimal)
    (require-capability (VAULT))
    (install-capability (coin.TRANSFER VAULT-ACCOUNT payee amount))
    (coin.transfer-create VAULT-ACCOUNT payee payee-guard amount))

  ;; -----------------------------
  ;; Registry
  ;; -----------------------------

  (defun register-property:string
    ( property-id:string
      landlord:string landlord-guard:guard
      beneficiary:string beneficiary-guard:guard
      info:string
      tax-bps:integer repairs-bps:integer beneficiary-bps:integer )
    @doc "Landlord self-registers a property (their guard must sign). Split \
    \bps are IMMUTABLE afterwards; landlord share = 10000 - sum(bps)."
    (enforce-valid-id property-id)
    ;; Payout destinations MUST be principal accounts (k:/w:/r:). They are paid
    ;; via coin.transfer-create with their ENROLLED guard; a vanity name could
    ;; be squatted with a foreign guard (or never created), and coin would then
    ;; abort every payout to it - permanently locking the LANDLORD/beneficiary
    ;; funds (and, via a bricked settle, the tenant's deposit). validate-principal
    ;; binds name==principal(guard), which coin's reserved-name protocol makes
    ;; unsquattable and guarantees the guard matches.
    (enforce (validate-principal landlord-guard landlord)
      "landlord must be a principal account (k:/w:/r:)")
    (enforce (validate-principal beneficiary-guard beneficiary)
      "beneficiary must be a principal account (k:/w:/r:)")
    (enforce (<= (length info) MAX-MEMO-LEN) "info too long")
    (enforce (>= tax-bps 0) "tax-bps negative")
    (enforce (>= repairs-bps 0) "repairs-bps negative")
    (enforce (>= beneficiary-bps 0) "beneficiary-bps negative")
    (enforce (<= (+ tax-bps (+ repairs-bps beneficiary-bps)) BPS-DENOM)
      "splits exceed 100%")
    (enforce-guard landlord-guard)
    (insert properties property-id
      { "landlord": landlord, "landlord-guard": landlord-guard
      , "beneficiary": beneficiary, "beneficiary-guard": beneficiary-guard
      , "info": info
      , "tax-bps": tax-bps, "repairs-bps": repairs-bps
      , "beneficiary-bps": beneficiary-bps
      , "active": true })
    (emit-event (PROPERTY-REGISTERED property-id landlord))
    (format "property {} registered" [property-id]))

  (defun set-property-active:string (property-id:string active:bool)
    @doc "Landlord gates NEW lease creation; existing leases and withdrawals \
    \are unaffected."
    (with-capability (LANDLORD property-id)
      (update properties property-id { "active": active })
      (emit-event (PROPERTY-ACTIVE-SET property-id active))
      (format "property {} active: {}" [property-id active])))

  ;; -----------------------------
  ;; Lease lifecycle
  ;; -----------------------------

  (defun create-lease:string
    ( lease-id:string property-id:string
      tenant:string tenant-guard:guard
      doc-hash:string
      rent:decimal period-days:integer grace-days:integer late-fee:decimal
      deposit:decimal
      start:time end:time
      notice-days:integer claim-window-days:integer )
    @doc "Mutual assent: BOTH landlord and tenant guards must sign the tx \
    \(landlord scopes LANDLORD, tenant scopes TENANT is not yet possible - the \
    \lease does not exist - so the tenant guard is enforced directly here). \
    \doc-hash anchors the signed off-chain lease document."
    (enforce-valid-id lease-id)
    (let ((p (read properties property-id)))
      (enforce (at 'active p) "property not active")
      ;; the tenant is a settlement payout destination (deposit refund) - it
      ;; must be a principal account for the same reason as the landlord /
      ;; beneficiary (see register-property); otherwise a squatted refund
      ;; account bricks settle-deposit and locks the deposit forever.
      (enforce (validate-principal tenant-guard tenant)
        "tenant must be a principal account (k:/w:/r:)")
      (enforce (!= doc-hash "") "doc-hash required")
      (enforce (<= (length doc-hash) 128) "doc-hash too long")
      (enforce-positive rent "rent must be positive with precision <= 12")
      (enforce-non-negative late-fee "late-fee must be >= 0 with precision <= 12")
      (enforce-non-negative deposit "deposit must be >= 0 with precision <= 12")
      (enforce (and (>= period-days 1) (<= period-days 366)) "period-days out of range [1,366]")
      (enforce (and (>= grace-days 0) (<= grace-days 366)) "grace-days out of range [0,366]")
      (enforce (and (>= notice-days 0) (<= notice-days 365)) "notice-days out of range [0,365]")
      (enforce (and (>= claim-window-days 0) (<= claim-window-days 365)) "claim-window-days out of range [0,365]")
      (enforce-time-bounds start "start out of bounds")
      (enforce-time-bounds end "end out of bounds")
      (enforce (< start end) "start must precede end")
      ;; mutual assent: landlord (scoped) + tenant (the guard being enrolled)
      (with-capability (LANDLORD property-id)
        (enforce-guard tenant-guard)
        (insert leases lease-id
          { "property-id": property-id
          , "tenant": tenant, "tenant-guard": tenant-guard
          , "doc-hash": doc-hash
          , "rent": rent, "period-days": period-days
          , "grace-days": grace-days, "late-fee": late-fee
          , "deposit": deposit, "deposit-held": 0.0
          , "start": start, "end": end, "paid-through": start
          , "notice-days": notice-days
          , "claim-window-days": claim-window-days
          , "claim-amount": 0.0, "claim-filed": false })
        (emit-event (LEASE-SIGNED lease-id property-id tenant rent doc-hash))
        (format "lease {} signed" [lease-id]))))

  (defun pay-deposit:string (lease-id:string payer:string)
    @doc "Escrow the remaining security deposit. Payer signs coin.TRANSFER \
    \payer -> vault for (deposit - deposit-held); anyone may pay."
    (let* ((l (read leases lease-id))
           (deposit (at 'deposit l))
           (held (at 'deposit-held l))
           (due (- deposit held))
           (now (chain-now))
           (lease-end (at 'end l)))
      (enforce (> due 0.0) "deposit already fully escrowed")
      (enforce (< now lease-end) "lease term is over")
      (coin.transfer-create payer VAULT-ACCOUNT VAULT-GUARD due)
      (update leases lease-id { "deposit-held": deposit })
      (emit-event (DEPOSIT-PAID lease-id payer due))
      (format "deposit escrowed: {}" [due])))

  (defun pay-rent:string (lease-id:string payer:string)
    @doc "Pay exactly ONE billing period (the next uncovered one): rent plus \
    \the late fee when past paid-through + grace. Anyone may pay (guarantor \
    \pattern) - coin's DEBIT authorizes the payer. Requires escrowed deposit."
    (let* ((l (read leases lease-id))
           (property-id (at 'property-id l))
           (p (read properties property-id))
           (now (chain-now))
           (rent (at 'rent l))
           (paid-through (at 'paid-through l))
           (grace-end (add-time paid-through (days (at 'grace-days l))))
           (late (> now grace-end))
           (fee (if late (at 'late-fee l) 0.0))
           (total (+ rent fee))
           (tax-cut (split-amount rent (at 'tax-bps p)))
           (repairs-cut (split-amount rent (at 'repairs-bps p)))
           (beneficiary-cut (split-amount rent (at 'beneficiary-bps p)))
           (landlord-cut (+ fee (- rent (+ tax-cut (+ repairs-cut beneficiary-cut)))))
           (new-paid-through (add-time paid-through (days (at 'period-days l))))
           (deposit (at 'deposit l))
           (held (at 'deposit-held l))
           (lease-end (at 'end l)))
      (enforce (= held deposit) "security deposit must be fully escrowed before rent")
      (enforce (< paid-through lease-end) "lease term already fully paid")
      (coin.transfer-create payer VAULT-ACCOUNT VAULT-GUARD total)
      (with-capability (VAULT)
        (credit-bucket property-id BUCKET-TAX tax-cut)
        (credit-bucket property-id BUCKET-REPAIRS repairs-cut)
        (credit-bucket property-id BUCKET-BENEFICIARY beneficiary-cut)
        (credit-bucket property-id BUCKET-LANDLORD landlord-cut))
      (update leases lease-id { "paid-through": new-paid-through })
      (emit-event (RENT-PAID lease-id payer total fee new-paid-through))
      (format "rent paid; covered through {}" [new-paid-through])))

  ;; -----------------------------
  ;; Withdrawals
  ;; -----------------------------

  (defun withdraw-bucket:string
    ( property-id:string bucket:string amount:decimal
      payee:string payee-guard:guard memo:string )
    @doc "Landlord-guarded withdrawal from TAX / REPAIRS / LANDLORD. Payee is \
    \free (tax authority, contractor, self); evented with memo for on-chain \
    \spend transparency. BENEFICIARY is push-only."
    (enforce (contains bucket [BUCKET-TAX BUCKET-REPAIRS BUCKET-LANDLORD])
      "bucket not landlord-withdrawable")
    (enforce (<= (length memo) MAX-MEMO-LEN) "memo too long")
    (enforce-positive amount "amount must be positive with precision <= 12")
    (with-capability (LANDLORD property-id)
      (with-capability (VAULT)
        (debit-bucket property-id bucket amount)
        (vault-pay payee payee-guard amount))
      (emit-event (WITHDRAWAL property-id bucket amount payee memo))
      (format "{} withdrawn from {} {}" [amount property-id bucket])))

  (defun push-beneficiary:string (property-id:string)
    @doc "Permissionless: push the entire BENEFICIARY bucket to the property's \
    \fixed beneficiary account (destination immutable => no auth needed)."
    (let* ((p (read properties property-id))
           (key (bucket-key property-id BUCKET-BENEFICIARY))
           (bal (at 'balance (read buckets key))))
      (enforce (> bal 0.0) "beneficiary bucket empty")
      (with-capability (VAULT)
        (debit-bucket property-id BUCKET-BENEFICIARY bal)
        (vault-pay (at 'beneficiary p) (at 'beneficiary-guard p) bal))
      (emit-event (WITHDRAWAL property-id BUCKET-BENEFICIARY bal (at 'beneficiary p) "push"))
      (format "pushed {} to beneficiary" [bal])))

  ;; -----------------------------
  ;; Deposit settlement
  ;; -----------------------------

  (defun claim-deposit:string (lease-id:string amount:decimal memo:string)
    @doc "Landlord files ONE deduction claim (<= escrowed deposit) inside the \
    \claim window after end. v1 has NO ARBITER - the claim is unilateral; the \
    \off-chain document + legal system are the backstop."
    (enforce (<= (length memo) MAX-MEMO-LEN) "memo too long")
    (enforce-non-negative amount "claim must be >= 0 with precision <= 12")
    (let* ((l (read leases lease-id))
           (property-id (at 'property-id l))
           (now (chain-now))
           (lease-end (at 'end l))
           (window-end (add-time lease-end (days (at 'claim-window-days l))))
           (held (at 'deposit-held l))
           (filed (at 'claim-filed l)))
      (enforce (not filed) "claim already filed")
      (enforce (>= now lease-end) "lease not ended yet")
      (enforce (< now window-end) "claim window closed")
      (enforce (<= amount held) "claim exceeds escrowed deposit")
      (with-capability (LANDLORD property-id)
        (update leases lease-id { "claim-amount": amount, "claim-filed": true })
        (emit-event (DEPOSIT-CLAIMED lease-id amount memo))
        (format "claim of {} filed" [amount]))))

  (defun settle-deposit:string (lease-id:string)
    @doc "Permissionless after the claim window: claim -> landlord, \
    \remainder -> tenant."
    (let* ((l (read leases lease-id))
           (p (read properties (at 'property-id l)))
           (now (chain-now))
           (window-end (add-time (at 'end l) (days (at 'claim-window-days l))))
           (held (at 'deposit-held l))
           (claim (at 'claim-amount l))
           (to-tenant (- held claim)))
      (enforce (> held 0.0) "no deposit to settle")
      (enforce (>= now window-end) "claim window still open")
      (with-capability (VAULT)
        ;; Coalesce identical payees: if the landlord and tenant are the same
        ;; account, two vault-pays would install the SAME managed
        ;; (coin.TRANSFER vault payee amount) twice and abort ("already
        ;; installed"), stranding the deposit. Pay the full held amount once.
        (if (= (at 'landlord p) (at 'tenant l))
          (vault-pay (at 'landlord p) (at 'landlord-guard p) held)
          [ (if (> claim 0.0)
              (vault-pay (at 'landlord p) (at 'landlord-guard p) claim)
              "no landlord claim")
            (if (> to-tenant 0.0)
              (vault-pay (at 'tenant l) (at 'tenant-guard l) to-tenant)
              "full deposit claimed") ]))
      (update leases lease-id { "deposit-held": 0.0 })
      (emit-event (DEPOSIT-SETTLED lease-id to-tenant claim))
      (format "settled: {} to tenant, {} to landlord" [to-tenant claim])))

  ;; -----------------------------
  ;; Termination / renewal
  ;; -----------------------------

  (defun give-notice:string (lease-id:string new-end:time)
    @doc "Either party shortens the term, respecting notice-days. Cannot cut \
    \below paid-through (no refund logic in v1)."
    (let* ((l (read leases lease-id))
           (property-id (at 'property-id l))
           (now (chain-now))
           (lease-end (at 'end l))
           (earliest (add-time now (days (at 'notice-days l))))
           (paid-through (at 'paid-through l)))
      (enforce (< now lease-end) "lease already ended")
      (enforce-time-bounds new-end "new-end out of bounds")
      (enforce (< new-end lease-end) "notice must shorten the term")
      (enforce (>= new-end earliest) "notice period too short")
      (enforce (>= new-end paid-through) "cannot end before paid-through (no refunds in v1)")
      ;; Either party may terminate; they scope their signature to PARTY, whose
      ;; body binds both guards BEFORE the enforce-one (node-safe: the reads run
      ;; in the defcap body, not inside an enforce/enforce-one CONDITION).
      (with-capability (PARTY lease-id)
        (update leases lease-id { "end": new-end })
        (emit-event (NOTICE-GIVEN lease-id new-end))
        (format "term shortened to {}" [new-end]))))

  (defun renew-lease:string (lease-id:string new-end:time new-rent:decimal)
    @doc "Mutual assent: BOTH guards must sign (landlord scopes LANDLORD, \
    \tenant scopes TENANT). Extends term, re-prices future periods."
    (let* ((l (read leases lease-id))
           (property-id (at 'property-id l))
           (now (chain-now))
           (lease-end (at 'end l)))
      (enforce (< now lease-end) "lease already ended; create a new lease")
      (enforce-time-bounds new-end "new-end out of bounds")
      (enforce (> new-end lease-end) "renewal must extend the term")
      (enforce-positive new-rent "rent must be positive with precision <= 12")
      (with-capability (LANDLORD property-id)
        (with-capability (TENANT lease-id)
          (update leases lease-id { "end": new-end, "rent": new-rent })
          (emit-event (LEASE-RENEWED lease-id new-end new-rent))
          (format "renewed to {} at rent {}" [new-end new-rent])))))

  ;; -----------------------------
  ;; Views (local reads)
  ;; -----------------------------

  (defun get-property:object{property} (property-id:string)
    (read properties property-id))

  (defun get-lease:object{lease} (lease-id:string)
    (read leases lease-id))

  (defun bucket-balance:decimal (property-id:string bucket:string)
    (with-default-read buckets (bucket-key property-id bucket)
      { "balance": 0.0 } { "balance" := bal }
      bal))

  (defun vault-account:string () VAULT-ACCOUNT)

  (defun rent-due:object (lease-id:string)
    @doc "Next period's amount (incl. late fee), lateness, and payability."
    (let* ((l (read leases lease-id))
           (now (chain-now))
           (paid-through (at 'paid-through l))
           (grace-end (add-time paid-through (days (at 'grace-days l))))
           (late (> now grace-end))
           (fee (if late (at 'late-fee l) 0.0)))
      { "amount": (+ (at 'rent l) fee)
      , "late": late
      , "next-period-start": paid-through
      , "payable": (and (< paid-through (at 'end l))
                        (= (at 'deposit-held l) (at 'deposit l))) }))

  (defun lease-state:string (lease-id:string)
    @doc "Lifecycle is computed from time + row state, never stored."
    (let* ((l (read leases lease-id))
           (now (chain-now))
           (lease-end (at 'end l))
           (window-end (add-time lease-end (days (at 'claim-window-days l)))))
      (cond
        ((< now lease-end)
          (if (< (at 'deposit-held l) (at 'deposit l)) "AWAITING-DEPOSIT" "ACTIVE"))
        ((> (at 'deposit-held l) 0.0)
          (if (< now window-end) "CLAIM-WINDOW" "SETTLEMENT-DUE"))
        "CLOSED")))
)

(create-table properties)
(create-table leases)
(create-table buckets)
