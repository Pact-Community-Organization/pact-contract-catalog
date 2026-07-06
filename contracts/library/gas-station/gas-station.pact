(module gas-station GOV

  @doc "PCO library template: a gas station with an on-chain, sponsor-controlled \
  \allowlist.                                                                    \
  \                                                                              \
  \A gas station is an autonomous coin account that pays gas on behalf of users, \
  \enabling gasless UX. Because it holds spendable KDA, an unconstrained station \
  \is a free-money faucet.                                                       \
  \                                                                              \
  \DESIGN NOTE 1 (drain defense). A common pattern inspects the transaction's    \
  \`exec-code`/`tx-type` via `read-msg` to allowlist a module. That is NOT sound:\
  \`read-msg` returns the mutable tx `data` payload, which is not bound to the   \
  \code the transaction executes, and a single code string can carry multiple    \
  \top-level forms past a naive prefix check. This template does NOT allowlist    \
  \by code string.                                                               \
  \                                                                              \
  \DESIGN NOTE 2 (bound the REAL gas). The gas price/limit passed to GAS_PAYER   \
  \are signer-supplied and are NOT bound to the transaction's actual gas. All    \
  \bounds and cap accounting here therefore use (chain-data) 'gas-price /        \
  \'gas-limit - the values coin actually debits - NOT the capability arguments.  \
  \                                                                              \
  \This template funds a transaction only if:                                    \
  \  1. the signer proves control of an ENROLLED user's guard (authentication),  \
  \  2. that user is enabled,                                                     \
  \  3. the ACTUAL gas price/limit are within the station bounds, and            \
  \  4. the user's cumulative funding cap would not be exceeded.                 \
  \                                                                              \
  \Deployment checklist (see README.md):                                         \
  \  1. Wrap in your namespace; replace the 'gas-station-gov' keyset.            \
  \  2. Tune MAX_GAS_PRICE / MAX_GAS_LIMIT / DEFAULT_USER_CAP.                    \
  \  3. Deploy, then (init) to create the station account.                       \
  \  4. Fund GAS_STATION with KDA; enroll users with (enroll-user ...).          \
  \  5. Validate the end-to-end gas flow on devnet before mainnet."

  (implements gas-payer-v1)

  ;; -----------------------------
  ;; Governance
  ;; -----------------------------

  (defconst GOV_KEYSET:string "gas-station-gov"
    @doc "Governance keyset name. Replace with your deployed, namespace- \
         \qualified keyset. Referenced by BOTH the GOV cap and the station \
         \guard's withdrawal branch, so editing it here updates both.")

  (defcap GOV ()
    @doc "Module governance."
    (enforce-guard (keyset-ref-guard GOV_KEYSET)))

  ;; -----------------------------
  ;; Policy constants — TUNE THESE
  ;; -----------------------------

  (defconst MAX_GAS_PRICE:decimal 0.000001
    "Maximum ACTUAL gas price this station will fund per transaction")

  (defconst MAX_GAS_LIMIT:integer 1500
    "Maximum ACTUAL gas limit this station will fund per transaction")

  (defconst DEFAULT_USER_CAP:decimal 1.0
    "Default cumulative KDA a newly enrolled user may be funded, unless overridden")

  ;; -----------------------------
  ;; Events (audit trail)
  ;; -----------------------------

  (defcap ENROLL (user:string cap:decimal)
    @doc "Emitted when a user is enrolled / re-enrolled."
    @event
    true)

  (defcap DISABLE (user:string)
    @doc "Emitted when a user is disabled."
    @event
    true)

  (defcap RESET (user:string)
    @doc "Emitted when a user's spent counter is reset."
    @event
    true)

  (defcap FUNDED (user:string amount:decimal)
    @doc "Emitted when the station funds gas for a user (actual max cost)."
    @event
    true)

  (defcap WITHDRAW (receiver:string amount:decimal)
    @doc "Emitted on governance withdrawal of residual station funds."
    @event
    true)

  ;; -----------------------------
  ;; Allowlist storage
  ;; -----------------------------

  (defschema allow-row
    @doc "Per-user funding allowance."
    guard:guard      ;; authenticates the user; must be satisfied to draw funding
    enabled:bool
    cap:decimal      ;; cumulative KDA this user may be funded
    spent:decimal)   ;; cumulative KDA funded so far (from ACTUAL gas)

  (deftable allowlist:{allow-row})

  ;; -----------------------------
  ;; Station account (capability-guarded)
  ;; -----------------------------

  (defcap ALLOW_GAS ()
    @doc "Internal permission token. Weak body by design: it is composed ONLY \
         \inside GAS_PAYER, after every policy check passes, and is required by \
         \the station account guard. It is not acquirable from outside this \
         \module, so it grants no authority on its own."
    true)

  (defun gas-payer-guard-pred:bool ()
    @doc "User-guard predicate controlling the station account. Satisfied by \
         \EITHER the gas-payment path (coin.GAS + ALLOW_GAS in scope) OR the \
         \governance keyset (for residual-fund recovery via withdraw). \
         \enforce-one short-circuits on the first passing branch."
    (enforce-one "station spend not authorized"
      [ (and (require-capability (coin.GAS))
             (require-capability (ALLOW_GAS)))
        (enforce-guard (keyset-ref-guard GOV_KEYSET)) ]))

  (defun create-gas-payer-guard:guard ()
    @doc "gas-payer-v1: the guard controlling the station coin account."
    (create-user-guard (gas-payer-guard-pred)))

  (defconst GAS_STATION:string
    (create-principal (create-gas-payer-guard))
    "Principal account name derived from the gas-payer guard")

  ;; -----------------------------
  ;; GAS_PAYER policy
  ;; -----------------------------

  (defcap GAS_PAYER:bool
    ( user:string
      limit:integer
      price:decimal )
    @doc "Fund gas for an ENROLLED, AUTHENTICATED user, bounding and accounting \
         \against the transaction's ACTUAL gas (chain-data), not the signer- \
         \supplied cap arguments. Composes ALLOW_GAS iff all checks pass."

    ; canonical gas-payer-v1 invariants (on the declared args)
    (enforce (> limit 0) "gas limit must be positive")
    (enforce (> price 0.0) "gas price must be positive")

    ; bind the ACTUAL gas the tx will consume — this is what coin debits.
    (let ( (actual-price:decimal (at 'gas-price (chain-data)))
           (actual-limit:integer (at 'gas-limit (chain-data))) )

      ; bound the real spend
      (enforce (<= actual-price MAX_GAS_PRICE)
        (format "actual gas price {} exceeds station max {}" [actual-price MAX_GAS_PRICE]))
      (enforce (<= actual-limit MAX_GAS_LIMIT)
        (format "actual gas limit {} exceeds station max {}" [actual-limit MAX_GAS_LIMIT]))

      ; authenticate + authorize against the sponsor-controlled allowlist.
      ; read is let-bound before any enforce (node-safe).
      (with-read allowlist user
        { "guard" := user-guard, "enabled" := enabled, "cap" := cap, "spent" := spent }
        (enforce-guard user-guard)                 ; F2: signer must control the user
        (enforce enabled "user is not enrolled for gas sponsorship")
        (let ((tx-max-cost:decimal (* (dec actual-limit) actual-price)))
          ; defense-in-depth: chainweb + coin.buy-gas already reject non-positive
          ; gas, so this is unreachable on-chain, but it guarantees spent is
          ; monotonic even if a future coin change relaxed that.
          (enforce (>= tx-max-cost 0.0) "invalid gas cost")
          (enforce (<= (+ spent tx-max-cost) cap)
            (format "user funding cap {} would be exceeded" [cap]))
          (update allowlist user { "spent": (+ spent tx-max-cost) })
          (emit-event (FUNDED user tx-max-cost)))))

    (compose-capability (ALLOW_GAS)))

  ;; -----------------------------
  ;; Sponsor administration (governance-gated)
  ;; -----------------------------

  (defun enroll-user:string (user:string guard:guard cap:decimal)
    @doc "Enroll USER (authenticated by GUARD) for gas sponsorship with a \
         \cumulative funding CAP (KDA). Re-enrolling updates guard and cap and \
         \re-enables without resetting spent."
    (with-capability (GOV)
      (enforce (!= user "") "user required")
      (enforce (>= cap 0.0) "cap must be non-negative")
      (with-default-read allowlist user
        { "spent": 0.0 }
        { "spent" := spent }
        (write allowlist user
          { "guard": guard, "enabled": true, "cap": cap, "spent": spent }))
      (emit-event (ENROLL user cap))
      "enrolled"))

  (defun enroll-user-default:string (user:string guard:guard)
    @doc "Enroll USER at DEFAULT_USER_CAP."
    (enroll-user user guard DEFAULT_USER_CAP))

  (defun disable-user:string (user:string)
    @doc "Disable gas sponsorship for USER (preserves guard, cap, spent)."
    (with-capability (GOV)
      (with-read allowlist user
        { "guard" := guard, "cap" := cap, "spent" := spent }
        (write allowlist user
          { "guard": guard, "enabled": false, "cap": cap, "spent": spent }))
      (emit-event (DISABLE user))
      "disabled"))

  (defun reset-user-spent:string (user:string)
    @doc "Reset USER's cumulative spent counter to zero (e.g. new period)."
    (with-capability (GOV)
      (with-read allowlist user
        { "guard" := guard, "enabled" := enabled, "cap" := cap }
        (write allowlist user
          { "guard": guard, "enabled": enabled, "cap": cap, "spent": 0.0 }))
      (emit-event (RESET user))
      "reset"))

  (defun get-user:object{allow-row} (user:string)
    @doc "Read a user's allowlist row."
    (read allowlist user))

  ;; -----------------------------
  ;; Lifecycle & treasury
  ;; -----------------------------

  (defun init:string ()
    @doc "Create the station coin account. Call exactly once; a second call \
         \aborts because the account already exists. Fund GAS_STATION with \
         \KDA separately."
    (with-capability (GOV)
      (coin.create-account GAS_STATION (create-gas-payer-guard))))

  (defun withdraw:string (receiver:string amount:decimal)
    @doc "Governance recovery of residual KDA from the station. Authorization \
         \is the station account guard itself: its governance branch enforces \
         \the gas-station-gov keyset. The caller must sign the transaction with \
         \the gas-station-gov key scoping (coin.TRANSFER GAS_STATION receiver  \
         \amount) - that signature both installs the managed transfer cap and  \
         \satisfies the station guard. No separate GOV acquisition is needed."
    (emit-event (WITHDRAW receiver amount))
    (coin.transfer GAS_STATION receiver amount))

  (defun get-station-account:string ()
    @doc "Return the station principal account name."
    GAS_STATION)
)
