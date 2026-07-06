(module vesting GOV

  @doc "PCO library template: KDA vesting with cliff + linear release,           \
  \escrowed upfront.                                                             \
  \                                                                              \
  \A grant locks its FULL amount in a module-owned (capability-guarded) vault    \
  \at creation - the beneficiary never depends on the funder staying solvent    \
  \or honest. The beneficiary claims the vested portion over time; if the       \
  \grant is revocable, the funder can revoke the UNVESTED portion back, but     \
  \never what has already vested.                                               \
  \                                                                              \
  \Model:                                                                        \
  \  - `create-grant` escrows TOTAL from the funder into the vault (the         \
  \    funder's own coin.TRANSFER signature is the authorization).              \
  \  - vested(t): 0 before CLIFF; linear from START to END; TOTAL after END.    \
  \  - `claim` pays (vested - claimed) to the beneficiary account, guarded by   \
  \    the guard enrolled at grant creation.                                    \
  \  - `revoke` (only if the grant was created revocable) freezes the grant at  \
  \    its vested amount and refunds the rest to the funder.                    \
  \  - The DEPLOYED code gives governance NO path to escrowed funds (upgrade    \
  \    authority only). An upgrade can change that code: pin the module hash    \
  \    you audited and put GOV under a multi-sig keyset.                        \
  \                                                                              \
  \Deployment checklist (see README.md):                                         \
  \  1. Wrap in your namespace; replace the 'vesting-gov' keyset.                \
  \  2. Deploy; no init step - grants are self-contained.                        \
  \  3. Validate on devnet before mainnet."

  ;; -----------------------------
  ;; Governance
  ;; -----------------------------

  (defconst GOV_KEYSET:string "vesting-gov"
    @doc "Governance keyset name. Replace with your deployed, namespace- \
         \qualified keyset (multi-sig recommended). In the deployed code \
         \governance can upgrade the module and nothing else - no function \
         \under GOV touches escrowed funds - but upgrade power IS ultimate \
         \power over future code, so treat this keyset accordingly.")

  (defcap GOV ()
    @doc "Module governance: upgrade only. No fund paths."
    (enforce-guard (keyset-ref-guard GOV_KEYSET)))

  ;; -----------------------------
  ;; Schema & table
  ;; -----------------------------

  (defschema grant-row
    @doc "One vesting grant. TOTAL is frozen to the vested amount on revoke."
    funder:string             ;; coin account that escrowed the funds (refund target)
    beneficiary:string        ;; coin account paid on claim
    beneficiary-guard:guard   ;; guard enrolled at creation; authorizes claims
    total:decimal             ;; total granted (frozen at vested-at-revoke on revoke)
    claimed:decimal           ;; amount already claimed
    start:time                ;; vesting start (may be in the past)
    cliff:time                ;; nothing is claimable before this (start <= cliff <= end)
    end:time                  ;; fully vested at/after this (end > start)
    revocable:bool            ;; whether the funder may revoke the unvested part
    status:string)            ;; "active" | "revoked"

  (deftable grants:{grant-row})

  (defconst STATUS_ACTIVE:string "active")
  (defconst STATUS_REVOKED:string "revoked")

  (defconst COIN_PRECISION:integer 12
    @doc "coin's minimum-precision unit; vested amounts are floored to it so \
         \claim transfers always satisfy coin.enforce-unit.")

  ;; -----------------------------
  ;; Events
  ;; -----------------------------

  (defcap GRANT_CREATED (id:string funder:string beneficiary:string total:decimal
                         start:time cliff:time end:time revocable:bool)
    @event true)

  (defcap CLAIMED (id:string beneficiary:string amount:decimal)
    @event true)

  (defcap REVOKED (id:string funder:string refund:decimal vested:decimal)
    @event true)

  ;; -----------------------------
  ;; Vault account (capability-guarded)
  ;; -----------------------------
  ;; The vault is a principal backed by a capability guard requiring SPEND.
  ;; SPEND is acquired ONLY inside `claim` and `revoke`, after their checks.
  ;; So coin can debit the vault only through those two audited paths.

  (defcap SPEND ()
    @doc "Internal permission token gating vault debits. Weak body by design: \
         \composed/acquired ONLY inside `claim` (after the beneficiary-guard + \
         \claimable checks) and `revoke` (after the funder-guard + revocable \
         \checks), and required by the vault account guard. Not acquirable \
         \from outside this module."
    true)

  (defun vault-guard-pred:bool ()
    @doc "User-guard predicate for the vault: satisfied only while SPEND is in \
         \scope (during a claim or revoke)."
    (require-capability (SPEND)))

  (defun create-vault-guard:guard ()
    (create-user-guard (vault-guard-pred)))

  (defconst VAULT:string
    (create-principal (create-vault-guard))
    "Vault principal account name.")

  ;; -----------------------------
  ;; Authentication capabilities
  ;; -----------------------------

  (defcap CLAIM-AUTH (id:string)
    @doc "Authenticate the beneficiary of grant ID via the guard enrolled at \
         \grant creation. As a capability, the beneficiary scopes their \
         \signature to `(vesting.CLAIM-AUTH \"my-grant\")`, so it does not also \
         \authorize other operations their key could satisfy in the transaction."
    ; NODE-SAFETY: bind the table read to a local FIRST, then enforce - a table
    ; read evaluated inside an enforce condition passes in the REPL but FAILS
    ; on the KDA-CE node. (pact non-negotiable #4)
    (let ((g (at 'beneficiary-guard (read grants id))))
      (enforce-guard g)))

  (defcap REVOKE-AUTH (id:string)
    @doc "Authenticate the funder of grant ID via the CURRENT guard of their \
         \coin account (looked up live, so revoke authority follows a coin \
         \key rotation instead of reviving a compromised old key)."
    (let* ((funder (at 'funder (read grants id)))
           (fg (at 'guard (coin.details funder))))
      (enforce-guard fg)))

  ;; -----------------------------
  ;; Vesting math
  ;; -----------------------------

  (defun chain-time:time ()
    @doc "Current block time (the PARENT block's timestamp on Chainweb - about \
         \one block behind wall-clock, irrelevant at vesting timescales)."
    (at 'block-time (chain-data)))

  (defun compute-vested:decimal (total:decimal start:time cliff:time end:time at-time:time)
    @doc "Schedule function: 0 before CLIFF; TOTAL at/after END; otherwise \
         \linear in elapsed time since START, floored to coin precision so the \
         \result is always transferable. Multiplies BEFORE dividing: decimal \
         \division is the only lossy step, so it must come last (dividing \
         \first, e.g. total * (elapsed/duration), loses precision and can \
         \understate exact schedule points)."
    (if (< at-time cliff)
      0.0
      (if (>= at-time end)
        total
        (floor (/ (* total (diff-time at-time start)) (diff-time end start))
               COIN_PRECISION))))

  (defun vested-amount:decimal (id:string)
    @doc "Amount vested for grant ID as of now. A revoked grant is frozen: its \
         \TOTAL was set to the vested amount at revoke time."
    (with-read grants id
      { 'total := total, 'start := start, 'cliff := cliff
      , 'end := end, 'status := status }
      (if (= status STATUS_REVOKED)
        total
        (compute-vested total start cliff end (chain-time)))))

  (defun claimable-amount:decimal (id:string)
    @doc "Amount the beneficiary of grant ID could claim right now. Clamped \
         \to zero: under a regressed block-time the raw difference could be \
         \negative, and integrators should never see a negative claimable."
    (with-read grants id { 'claimed := claimed }
      (let ((raw (- (vested-amount id) claimed)))
        (if (> raw 0.0) raw 0.0))))

  ;; -----------------------------
  ;; Grant lifecycle
  ;; -----------------------------

  (defun create-grant:string (id:string funder:string beneficiary:string
                              beneficiary-guard:guard total:decimal
                              start:time cliff:time end:time revocable:bool)
    @doc "Create grant ID and escrow TOTAL from FUNDER into the vault. The \
         \funder authorizes by signing coin.TRANSFER (they are spending their \
         \own funds); no module-level permission is required. ID must be \
         \unique. BENEFICIARY-GUARD is enrolled now and authorizes all claims. \
         \BENEFICIARY must be the principal of that guard (k:/w:/r:): this \
         \binds the payout name to the enrolled guard, so the account can \
         \neither be squatted with a foreign guard (coin rejects it) nor \
         \guard-rotated out from under the grant (coin forbids rotating \
         \principal accounts) - without it, either would leave the escrow \
         \permanently unclaimable. START may be in the past (e.g. an \
         \employment start date)."
    (enforce (> total 0.0) "total must be positive")
    (coin.enforce-unit total)
    (enforce (!= beneficiary VAULT) "beneficiary cannot be the vault")
    (enforce (validate-principal beneficiary-guard beneficiary)
      "beneficiary must be the principal of its guard")
    ; key-backed principals only: a u:/c: guard can be syntactically valid yet
    ; unsatisfiable (e.g. a capability guard no one can ever bring into scope),
    ; which would lock the escrow forever - and there is no admin sweep.
    (let ((protocol (typeof-principal beneficiary)))
      (enforce (contains protocol ["k:" "w:" "r:"])
        "beneficiary must be a key-backed principal (k:/w:/r:)"))
    (enforce (< start end) "end must be after start")
    (enforce (>= cliff start) "cliff cannot precede start")
    (enforce (<= cliff end) "cliff cannot exceed end")
    (insert grants id
      { 'funder: funder
      , 'beneficiary: beneficiary
      , 'beneficiary-guard: beneficiary-guard
      , 'total: total
      , 'claimed: 0.0
      , 'start: start
      , 'cliff: cliff
      , 'end: end
      , 'revocable: revocable
      , 'status: STATUS_ACTIVE })
    ; escrow upfront: the funder's coin.TRANSFER signature authorizes this.
    ; transfer-create binds the vault to its deterministic capability guard,
    ; so a pre-created vault account with the right guard is tolerated and a
    ; squatted one with a different guard aborts (front-run safe).
    (coin.transfer-create funder VAULT (create-vault-guard) total)
    (emit-event (GRANT_CREATED id funder beneficiary total start cliff end revocable))
    id)

  (defun claim:string (id:string)
    @doc "Pay the beneficiary everything vested and not yet claimed. Requires \
         \the beneficiary's signature scoped to (CLAIM-AUTH id). Pays via \
         \transfer-create with the enrolled guard, so the beneficiary account \
         \is created on first claim if absent, and a squatted account with a \
         \different guard cannot receive the funds. Works on both active and \
         \revoked grants (a revoked grant still owes its vested remainder)."
    (with-capability (CLAIM-AUTH id)
      (with-read grants id
        { 'beneficiary := beneficiary
        , 'beneficiary-guard := beneficiary-guard
        , 'claimed := claimed }
        (let* ((vested (vested-amount id))
               (claimable (- vested claimed)))
          (enforce (> claimable 0.0) "nothing claimable")
          ; settle BEFORE the transfer (defends re-entry; claimed only grows)
          (update grants id { 'claimed: (+ claimed claimable) })
          (with-capability (SPEND)
            (install-capability (coin.TRANSFER VAULT beneficiary claimable))
            (coin.transfer-create VAULT beneficiary beneficiary-guard claimable))
          (emit-event (CLAIMED id beneficiary claimable))
          id))))

  (defun revoke:string (id:string)
    @doc "Funder revokes the UNVESTED portion of a revocable grant: the grant \
         \is frozen at its vested amount (still claimable by the beneficiary) \
         \and the rest is refunded to the funder. Requires the funder's \
         \signature scoped to (REVOKE-AUTH id). Fails if the grant is not \
         \revocable, already revoked, or already fully vested."
    (with-capability (REVOKE-AUTH id)
      (with-read grants id
        { 'funder := funder
        , 'total := total
        , 'claimed := claimed
        , 'start := start
        , 'cliff := cliff
        , 'end := end
        , 'revocable := revocable
        , 'status := status }
        (enforce revocable "grant is not revocable")
        (enforce (= status STATUS_ACTIVE) "grant is not active")
        ; Clamp vested to at least CLAIMED. The vault is shared across grants:
        ; if block-time ever regressed (non-monotonic clock), an unclamped
        ; vested below claimed would make refund exceed this grant's remaining
        ; escrow (total - claimed) and pay the excess out of OTHER grants'
        ; funds. The clamp also keeps the frozen total >= claimed, so the
        ; revoked grant's claimable can never go negative.
        (let* ((vested-raw (compute-vested total start cliff end (chain-time)))
               (vested (if (> vested-raw claimed) vested-raw claimed))
               (refund (- total vested)))
          (enforce (> refund 0.0) "nothing to revoke; grant fully vested")
          ; freeze BEFORE the transfer: total := vested, so future claims can
          ; pay out exactly the earned remainder and nothing more
          (update grants id { 'total: vested, 'status: STATUS_REVOKED })
          (with-capability (SPEND)
            (install-capability (coin.TRANSFER VAULT funder refund))
            (coin.transfer VAULT funder refund))
          (emit-event (REVOKED id funder refund vested))
          id))))

  ;; -----------------------------
  ;; Views
  ;; -----------------------------

  (defun get-grant:object{grant-row} (id:string)
    (read grants id))

  (defun get-vault-account:string () VAULT)

  (defun vault-balance:decimal ()
    (coin.get-balance VAULT))
)
