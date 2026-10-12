;; nft.guarded-uri-policy — guard-authorized uri updates, with history and a
;; holder's right to freeze (ADR-NFT-005).
;;
;; The uri-update authority is REQUIRED in the create-token transaction and
;; bound into this policy's own state at init — fail closed: a missing guard
;; aborts creation, it never defaults to "anyone may update" or to "the
;; framework admin may update". This policy returns "permit" from the base
;; token-policy uri-decision hook, and the manager then calls its
;; enforce-update-uri, where the stored guard authorizes the specific update.
;; Stack nft.non-updatable-uri-policy alongside and its veto wins — the manager
;; evaluates every attached policy's stance, so one veto is final.
;;
;; Two creation-time options, both with safe defaults (they only ADD records or
;; restrict the updater; neither widens who may update):
;;   * uri_history: "events" (default) — the ledger's URI-UPDATED event trail is
;;     the history; or "onchain" — this policy also keeps every superseded uri in
;;     `uri-history`, keyed by version, readable by any contract;
;;   * uri_holder_freeze: false (default) — or true: a holder of the WHOLE supply
;;     (a 1/1 owner, or the sole holder of a print run) may freeze the token's
;;     uri for good; afterwards no updater can change it. One-way, owner-only,
;;     no admin counterpart. The option is visible before anyone buys.
;;
;; All token-policy lifecycle hooks are permissive; each still requires the
;; ledger's matching -CALL capability in scope, so no hook is reachable
;; outside the real ledger lifecycle path.

(namespace (read-string 'ns))

(module guarded-uri-policy GOVERNANCE
  @doc "Guard-gated uri updates for the nft framework: the update guard binds \
       \once at token creation; the manager's update-uri routing enforces it; \
       \optional on-chain history and holder freeze."

  (implements token-policy)
  (use token-policy [token-info payout])

  (defconst ADMIN-KS:string (read-string 'admin-ks)
    @doc "Admin keyset name, captured ONCE at deploy — never read from a \
         \caller's payload at enforcement time.")

  (defcap GOVERNANCE ()
    (enforce-keyset ADMIN-KS))

  (defconst URI-GUARD-MSG-KEY:string "uri_guard"
    @doc "Create-token-tx payload key carrying the uri-update guard. REQUIRED \
         \for any token carrying this policy — fail closed.")
  (defconst URI-HISTORY-MSG-KEY:string "uri_history"
    @doc "Optional create-token-tx payload key: \"events\" (default) or \"onchain\".")
  (defconst URI-HOLDER-FREEZE-MSG-KEY:string "uri_holder_freeze"
    @doc "Optional create-token-tx payload key: may the sole holder freeze the uri? (default false)")
  (defconst HISTORY-EVENTS:string "events")
  (defconst HISTORY-ONCHAIN:string "onchain")

  (defschema uri-guard-schema
    @doc "Who may update the token's uri, bound once at token creation, plus \
         \the two options and the one-way frozen flag. token-id mirrors the \
         \row key (\"\" = the never-stored sentinel the cross-chain receive uses \
         \to detect absence)."
    token-id:string
    guard:guard
    history:string
    holder-freeze:bool
    frozen:bool)
  (deftable uri-guards:{uri-guard-schema})

  (defschema uri-version-row
    @doc "A superseded uri (on-chain history mode): the uri that version VERSION \
         \replaced, and when."
    uri:string
    version:integer
    at:time)
  (deftable uri-history:{uri-version-row})

  (defcap URI-GUARD:bool (token-id:string history:string holder-freeze:bool)
    @doc "Emitted once, when the uri-update guard and options bind at token creation."
    @event true)
  (defcap URI-FROZEN:bool (token-id:string by:string)
    @doc "Emitted when the sole holder freezes the uri for good."
    @event true)
  (defcap FREEZE:bool (token-id:string account:string)
    @doc "The sole holder proves control of their balance row's guard."
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (enforce-guard (l::holder-guard token-id account))))

  ;; --- views -------------------------------------------------------------------
  (defun get-uri-guard:guard (token-id:string)
    (at 'guard (read uri-guards token-id)))
  (defun get-uri-options:object{uri-guard-schema} (token-id:string)
    (read uri-guards token-id))
  (defun is-frozen:bool (token-id:string)
    (at 'frozen (read uri-guards token-id)))
  (defun history-key:string (token-id:string version:integer)
    (format "{}:{}" [token-id version]))
  (defun get-uri-at:object{uri-version-row} (token-id:string version:integer)
    @doc "On-chain history mode only: the uri that was replaced by VERSION."
    (read uri-history (history-key token-id version)))

  (defun enforce-valid-history:bool (h:string)
    (enforce (or (= h HISTORY-EVENTS) (= h HISTORY-ONCHAIN))
      "uri_history must be \"events\" or \"onchain\""))

  ;; --- the holder's one-way freeze ------------------------------------------------
  (defun freeze-copy:bool (token-id:string account:string)
    @doc "The holder of the WHOLE supply freezes the uri for good. Allowed only \
         \when the creator enabled uri_holder_freeze. No admin can undo or \
         \perform this; the ledger's own guard check is the only authority."
    (with-read uri-guards token-id { 'holder-freeze := hf, 'frozen := fz }
      (enforce hf "this token does not allow a holder freeze")
      (enforce (not fz) "the uri is already frozen"))
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (let ((bal (l::holder-balance token-id account))
            (sup (l::token-supply token-id)))
        (enforce (> bal 0.0) "the account holds none of this token")
        (enforce (= bal sup) "only the holder of the whole supply may freeze the uri")))
    (with-capability (FREEZE token-id account)
      (update uri-guards token-id { 'frozen: true })
      (emit-event (URI-FROZEN token-id account)))
    true)

  ;; --- uri stance: PERMIT, then the stored guard authorizes the update -----------
  ;; mint stance: metadata authority is not issuance authority
  (defun mint-decision:string (token:object{token-info}) (identity "abstain"))

  (defun uri-decision:string (token:object{token-info}) (identity "permit"))
  (defun enforce-update-uri:bool (token:object{token-info} new-uri:string)
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::UPDATE-URI-CALL (at 'id token) new-uri)))
    (with-read uri-guards (at 'id token) { 'guard := g, 'history := h, 'frozen := fz }
      (enforce (not fz) "the uri is frozen by its holder")
      (enforce-guard g)
      ;; on-chain history: record the uri this update supersedes under the
      ;; version the ledger is about to assign (current + 1)
      (if (= h HISTORY-ONCHAIN)
        (insert uri-history (history-key (at 'id token) (+ 1 (at 'uri-version token)))
          { 'uri: (at 'uri token), 'version: (+ 1 (at 'uri-version token)), 'at: (at 'block-time (chain-data)) })
        true))
    true)

  ;; --- token-policy hooks (permissive, -CALL gated) -------------------------------
  (defun enforce-init:bool (token:object{token-info})
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::INIT-CALL (at 'id token) (at 'precision token) (at 'uri token))))
    ;; the guard is REQUIRED (typed read: absent -> abort, fail closed); the two
    ;; options are optional with the restrictive-or-neutral default
    (let ((g:guard (read-msg URI-GUARD-MSG-KEY))
          (h:string (try HISTORY-EVENTS (read-string URI-HISTORY-MSG-KEY)))
          (hf:bool (try false (read-msg URI-HOLDER-FREEZE-MSG-KEY))))
      (enforce-valid-history h)
      (insert uri-guards (at 'id token)
        { 'token-id: (at 'id token), 'guard: g, 'history: h, 'holder-freeze: hf, 'frozen: false })
      (emit-event (URI-GUARD (at 'id token) h hf)))
    true)

  ;; payout stance (ADR-NFT-011): this policy claims nothing from a sale
  (defun payout-bps:integer (token:object{token-info}) 0)

  (defun enforce-mint:bool (token:object{token-info} account:string guard:guard amount:decimal)
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::MINT-CALL (at 'id token) account amount)))
    true)

  (defun enforce-burn:bool (token:object{token-info} account:string amount:decimal)
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::BURN-CALL (at 'id token) account amount)))
    true)

  (defun enforce-offer:bool (token:object{token-info} seller:string amount:decimal timeout:integer sale-id:string)
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::OFFER-CALL (at 'id token) seller amount timeout sale-id)))
    true)

  (defun enforce-withdraw:bool (token:object{token-info} seller:string amount:decimal timeout:integer sale-id:string)
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::WITHDRAW-CALL (at 'id token) seller amount timeout sale-id)))
    true)

  (defun enforce-buy:[object{payout}] (token:object{token-info} seller:string buyer:string buyer-guard:guard amount:decimal sale-id:string)
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::BUY-CALL (at 'id token) seller buyer amount sale-id)))
    [])

  (defun enforce-transfer:bool (token:object{token-info} sender:string guard:guard receiver:string amount:decimal)
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::TRANSFER-CALL (at 'id token) sender receiver amount)))
    true)

  ;; --- cross-chain passport (policy state travels with the token) ---------------
  (defun enforce-xchain-send:object (token:object{token-info} sender:string receiver:string receiver-guard:guard target-chain:string amount:decimal)
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::XCHAIN-SEND-CALL (at 'id token) sender receiver target-chain amount)))
    (with-read uri-guards (at 'id token) { 'guard := g, 'history := h, 'holder-freeze := hf, 'frozen := fz }
      { 'guard: g, 'history: h, 'holder-freeze: hf, 'frozen: fz }))

  (defun enforce-xchain-receive:bool (token:object{token-info} receiver:string receiver-guard:guard amount:decimal state:object)
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::XCHAIN-RECEIVE-CALL (at 'id token) receiver amount)))
    (let ((g:guard (at 'guard state))
          (h:string (at 'history state))
          (hf:bool (at 'holder-freeze state))
          (fz:bool (at 'frozen state)))
      (enforce-valid-history h)
      (with-default-read uri-guards (at 'id token) { 'token-id: "" } { 'token-id := existing }
        (if (= "" existing)
          (insert uri-guards (at 'id token)
            { 'token-id: (at 'id token), 'guard: g, 'history: h, 'holder-freeze: hf, 'frozen: fz })
          ;; a RETURNING token: the immutable guard and options must be identical;
          ;; the frozen flag is one-way, so it propagates (never clears)
          (with-read uri-guards (at 'id token) { 'guard := lg, 'history := lh, 'holder-freeze := lhf, 'frozen := lfz }
            (enforce (= g lg) "uri-guard passport mismatch")
            (enforce (and (= h lh) (= hf lhf)) "uri-options passport mismatch")
            (if (and fz (not lfz)) (update uri-guards (at 'id token) { 'frozen: true }) true)))))
    true)
)
