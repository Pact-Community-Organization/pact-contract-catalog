(module treasury GOV

  @doc "PCO library template: an M-of-N multisig treasury.                       \
  \                                                                              \
  \Holds KDA in a module-owned (capability-guarded) vault account that can be    \
  \spent ONLY through an on-chain proposal that collects approvals from a        \
  \threshold of authorized signers. Approvals are asynchronous - each signer     \
  \approves in their own transaction - and every step emits an event for audit.  \
  \                                                                              \
  \Model:                                                                        \
  \  - A fixed set of SIGNER accounts and a THRESHOLD (M of N) are configured    \
  \    at init and rotatable by governance.                                      \
  \  - Anyone in the signer set may `propose` a spend (recipient, amount).       \
  \  - Each signer `approve`s at most once; approvals are counted on-chain.      \
  \  - Once approvals >= threshold, anyone may `execute` the proposal, which     \
  \    debits the vault to the recipient exactly once.                           \
  \  - Governance may `cancel` a pending proposal and rotate the signer set.     \
  \                                                                              \
  \Deployment checklist (see README.md):                                         \
  \  1. Wrap in your namespace; replace the 'treasury-gov' keyset.               \
  \  2. Deploy, then (init [signers] threshold) with your signer accounts.       \
  \  3. Fund VAULT with KDA (get-vault-account returns its name).                \
  \  4. Validate on devnet before mainnet."

  ;; -----------------------------
  ;; Governance
  ;; -----------------------------

  (defconst GOV_KEYSET:string "treasury-gov"
    @doc "Governance keyset name. Replace with your deployed, namespace- \
         \qualified keyset (multi-sig recommended).")

  (defcap GOV ()
    @doc "Module governance: rotate signers/threshold, cancel proposals, upgrade."
    (enforce-guard (keyset-ref-guard GOV_KEYSET)))

  ;; -----------------------------
  ;; Schemas & tables
  ;; -----------------------------

  (defschema config-row
    @doc "Singleton treasury config."
    signers:[string]     ;; authorized signer account names
    threshold:integer)   ;; approvals required to execute

  (deftable config:{config-row})

  (defschema proposal-row
    @doc "A pending or settled spend proposal."
    proposer:string
    recipient:string
    amount:decimal
    approvals:[string]   ;; signer accounts that have approved (deduplicated)
    status:string)       ;; "pending" | "executed" | "cancelled"

  (deftable proposals:{proposal-row})

  (defschema signer-row
    @doc "Row-level guard for a signer account, captured at enrollment."
    guard:guard)

  (deftable signer-guards:{signer-row})

  (defconst CONFIG_KEY:string "config")

  (defconst STATUS_PENDING:string "pending")
  (defconst STATUS_EXECUTED:string "executed")
  (defconst STATUS_CANCELLED:string "cancelled")

  ;; -----------------------------
  ;; Events
  ;; -----------------------------

  (defcap PROPOSED (id:string proposer:string recipient:string amount:decimal)
    @event true)

  (defcap APPROVED (id:string signer:string approvals:integer)
    @event true)

  (defcap EXECUTED (id:string recipient:string amount:decimal)
    @event true)

  (defcap CANCELLED (id:string)
    @event true)

  (defcap SIGNERS_ROTATED (signers:[string] threshold:integer)
    @event true)

  ;; -----------------------------
  ;; Vault account (capability-guarded)
  ;; -----------------------------
  ;; The vault is a principal backed by a capability guard requiring SPEND.
  ;; SPEND is acquired ONLY inside `execute`, after an on-chain threshold check.
  ;; So coin can debit the vault only during a threshold-approved execution.

  (defcap SPEND ()
    @doc "Internal permission token gating vault debits. Weak body by design: \
         \composed/acquired ONLY inside `execute` after the approval threshold \
         \is verified, and required by the vault account guard. Not acquirable \
         \from outside this module."
    true)

  (defun vault-guard-pred:bool ()
    @doc "User-guard predicate for the vault: satisfied only when SPEND is in \
         \scope (during a threshold-approved execute)."
    (require-capability (SPEND)))

  (defun create-vault-guard:guard ()
    (create-user-guard (vault-guard-pred)))

  (defconst VAULT:string
    (create-principal (create-vault-guard))
    "Vault principal account name.")

  ;; -----------------------------
  ;; Internal helpers
  ;; -----------------------------

  (defun get-config:object{config-row} ()
    (read config CONFIG_KEY))

  (defun is-signer:bool (account:string)
    (contains account (at 'signers (get-config))))

  (defcap SIGNER-AUTH (account:string)
    @doc "Authenticate ACCOUNT as a current signer: it must be in the signer set \
         \AND the caller must satisfy its enrolled guard. As a capability, a \
         \signer can scope their signature to `(treasury.SIGNER-AUTH \"alice\")`, \
         \so an approval signature does NOT also authorize other operations the \
         \same key could satisfy in the transaction."
    ; NODE-SAFETY: `is-signer` reads the config table. A table read inside an
    ; `enforce` condition passes in the REPL but FAILS on the KDA-CE node
    ; ('Operation is not allowed in read-only or system-only mode'). Bind the
    ; read to a local FIRST, then enforce the local. (pact non-negotiable #4)
    (let ((signer-ok (is-signer account)))
      (enforce signer-ok "not an authorized signer"))
    (with-read signer-guards account { 'guard := g }
      (enforce-guard g)))

  ;; -----------------------------
  ;; Lifecycle & governance
  ;; -----------------------------

  (defun account-exists:bool (account:string)
    @doc "True if ACCOUNT exists on coin. Uses coin's public API (get-balance \
         \aborts on a missing account); we cannot read coin-table directly \
         \(cross-module table access requires coin's admin)."
    (try false (let ((_ (coin.get-balance account))) true)))

  (defun ensure-vault-account:string ()
    @doc "Create the vault coin account, tolerating a pre-existing one so init \
         \cannot be front-run bricked. The vault guard is deterministic \
         \(create-vault-guard); a pre-created vault necessarily carries it \
         \because the principal name encodes that guard, and coin.create-account \
         \enforces name==principal(guard). So a pre-existing vault is safe to \
         \accept, and we only create when absent."
    ; bind the existence check before branching (no read inside an enforce)
    (let ((exists (account-exists VAULT)))
      (if exists
        "vault already exists"
        (coin.create-account VAULT (create-vault-guard)))))

  (defun enforce-valid-config:bool (signers:[string] threshold:integer guards:[guard])
    @doc "Shared validation for the signer set. Rejects an empty set, a \
         \non-positive or unreachable threshold, a signers/guards length \
         \mismatch, and duplicate signers (which would silently make N-of-M \
         \unreachable, since approvals are deduplicated per account)."
    (enforce (> (length signers) 0) "at least one signer required")
    (enforce (> threshold 0) "threshold must be positive")
    (enforce (<= threshold (length signers)) "threshold exceeds signer count")
    (enforce (= (length signers) (length guards)) "signers/guards length mismatch")
    (enforce (= (length (distinct signers)) (length signers)) "duplicate signers"))

  (defun init:string (signers:[string] threshold:integer guards:[guard])
    @doc "One-time setup: configure the signer set + threshold, capture each \
         \signer's guard, and create the vault coin account. GUARDS must align \
         \positionally with SIGNERS. Idempotent w.r.t. a pre-created vault \
         \account (front-run safe); the config insert still enforces one-time \
         \setup."
    (with-capability (GOV)
      (enforce-valid-config signers threshold guards)
      (insert config CONFIG_KEY { 'signers: signers, 'threshold: threshold })
      (zip (lambda (s:string g:guard) (write signer-guards s { 'guard: g }))
           signers guards)
      (ensure-vault-account)
      (emit-event (SIGNERS_ROTATED signers threshold))
      "initialized"))

  (defun rotate-signers:string (signers:[string] threshold:integer guards:[guard])
    @doc "Governance: replace the signer set + threshold."
    (with-capability (GOV)
      (enforce-valid-config signers threshold guards)
      (update config CONFIG_KEY { 'signers: signers, 'threshold: threshold })
      (zip (lambda (s:string g:guard) (write signer-guards s { 'guard: g }))
           signers guards)
      (emit-event (SIGNERS_ROTATED signers threshold))
      "rotated"))

  ;; -----------------------------
  ;; Proposal flow
  ;; -----------------------------

  (defun propose:string (id:string proposer:string recipient:string amount:decimal)
    @doc "A signer proposes a spend. ID must be unique. The proposer is counted \
         \as the first approval. The proposer signs scoped to SIGNER-AUTH."
    (with-capability (SIGNER-AUTH proposer)
      (enforce (> amount 0.0) "amount must be positive")
      (coin.enforce-unit amount)
      (enforce (!= recipient "") "recipient required")
      (enforce (!= recipient VAULT) "recipient cannot be the vault")
      ; reject a proposal that could never execute: the recipient account must
      ; already exist on this chain. Bind the check before the enforce (node-safe).
      ; A caller can create the recipient first (coin.create-account) if needed.
      (let ((recipient-exists (account-exists recipient)))
        (enforce recipient-exists
          "recipient account does not exist; create it before proposing"))
      (insert proposals id
        { 'proposer: proposer
        , 'recipient: recipient
        , 'amount: amount
        , 'approvals: [proposer]
        , 'status: STATUS_PENDING })
      (emit-event (PROPOSED id proposer recipient amount))
      (emit-event (APPROVED id proposer 1))
      id))

  (defun approve:string (id:string signer:string)
    @doc "A signer approves a pending proposal. Idempotent per signer: a repeat \
         \approval by the same signer is rejected. The signer signs scoped to \
         \SIGNER-AUTH."
    (with-capability (SIGNER-AUTH signer)
      (with-read proposals id
        { 'approvals := approvals, 'status := status }
        (enforce (= status STATUS_PENDING) "proposal is not pending")
        (enforce (not (contains signer approvals)) "signer already approved")
        (let ((new-approvals (+ approvals [signer])))
          (update proposals id { 'approvals: new-approvals })
          (emit-event (APPROVED id signer (length new-approvals)))
          id))))

  (defun execute:string (id:string)
    @doc "Execute a proposal that has reached the approval threshold. Debits \
         \the vault to the recipient exactly once. Callable by anyone once the \
         \threshold is met (the approvals are the authorization)."
    (with-read proposals id
      { 'recipient := recipient
      , 'amount := amount
      , 'approvals := approvals
      , 'status := status }
      (enforce (= status STATUS_PENDING) "proposal is not pending")
      ; Count only approvals from CURRENT signers. A signer rotated out (e.g. a
      ; compromised key) must not have their stale approval count toward the
      ; threshold. Bind the config read before the enforce (node-safe).
      (let* ((cfg (get-config))
             (current-signers (at 'signers cfg))
             (threshold (at 'threshold cfg))
             (valid-approvals (filter (lambda (a:string) (contains a current-signers)) approvals)))
        (enforce (>= (length valid-approvals) threshold)
          (format "valid approvals {} below threshold {}" [(length valid-approvals) threshold]))
        ; mark settled BEFORE the transfer (guards against re-execution even if
        ; coin.transfer re-entered; status is re-checked above on any re-entry)
        (update proposals id { 'status: STATUS_EXECUTED })
        (with-capability (SPEND)
          (install-capability (coin.TRANSFER VAULT recipient amount))
          (coin.transfer VAULT recipient amount))
        (emit-event (EXECUTED id recipient amount))
        id)))

  (defun cancel:string (id:string)
    @doc "Governance cancels a pending proposal."
    (with-capability (GOV)
      (with-read proposals id { 'status := status }
        (enforce (= status STATUS_PENDING) "proposal is not pending")
        (update proposals id { 'status: STATUS_CANCELLED })
        (emit-event (CANCELLED id))
        id)))

  ;; -----------------------------
  ;; Views
  ;; -----------------------------

  (defun get-proposal:object{proposal-row} (id:string)
    (read proposals id))

  (defun get-vault-account:string () VAULT)

  (defun vault-balance:decimal ()
    (coin.get-balance VAULT))
)
