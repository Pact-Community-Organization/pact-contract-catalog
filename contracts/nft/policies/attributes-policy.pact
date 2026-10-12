;; nft.attributes-policy — on-chain attributes other contracts can read (ADR-NFT-010).
;;
;; A game that keeps a card's level in its own table locks that state inside one
;; contract; a second game cannot read it, and if the first game dies the state
;; dies with it. This policy gives a token a bounded, shared, readable state
;; surface: a fixed set of KEYS, each with its own WRITER guard, both fixed at
;; creation. Any contract reads; only the named writer writes its key; nobody
;; can add keys, rotate writers or touch another token's keys. Values are
;; strings (JSON if the writer wants structure) bounded by a per-token size, so
;; every write and every relocation is a known size.
;;
;; Options, both at creation: history "events" (default; the ATTRIBUTE-SET trail
;; is the history) or "onchain" (every superseded value is kept, keyed by
;; version); holder-freeze false (default) or true (the holder of the whole
;; supply may freeze every key for good — one-way, owner-only).
;;
;; Every hook requires the ledger's matching -CALL capability in scope, so no
;; hook is reachable outside the real ledger lifecycle path.

(namespace (read-string 'ns))

(module attributes-policy GOVERNANCE
  @doc "Bounded on-chain attributes per token with fixed per-key writers; \
       \readable by any contract; optional on-chain history and holder freeze."

  (implements token-policy)
  (use token-policy [token-info payout])

  (defconst ADMIN-KS:string (read-string 'admin-ks)
    @doc "Admin keyset name, captured ONCE at deploy — never read from a \
         \caller's payload at enforcement time.")

  (defcap GOVERNANCE ()
    (enforce-keyset ADMIN-KS))

  (defconst SPEC-MSG-KEY:string "attributes_spec"
    @doc "Create-token-tx payload key: { writers: [{key, guard}], max-value-bytes, \
         \history, holder-freeze }. REQUIRED (fail closed).")
  (defconst MAX-KEYS:integer 32
    @doc "Hard bound on keys per token: keeps the passport a known size.")
  (defconst MAX-VALUE-BYTES-CEILING:integer 4096
    @doc "Hard ceiling on the per-token value size a creator may choose.")
  (defconst HISTORY-EVENTS:string "events")
  (defconst HISTORY-ONCHAIN:string "onchain")

  (defschema writer
    key:string
    guard:guard)

  (defschema spec-row
    writers:[object{writer}]
    max-value-bytes:integer
    history:string
    holder-freeze:bool
    frozen:bool)
  (deftable specs:{spec-row})

  (defschema attribute-row
    value:string
    version:integer
    updated:time)
  (deftable attributes:{attribute-row})

  (defschema history-row
    value:string
    version:integer
    at:time)
  (deftable attr-history:{history-row})

  (defcap ATTRIBUTES:bool (token-id:string key-names:[string] history:string holder-freeze:bool)
    @doc "Emitted once at creation with the key set and options."
    @event true)
  (defcap ATTRIBUTE-SET:bool (token-id:string key:string version:integer value:string)
    @doc "Emitted on every write: the event trail is the default history."
    @event true)
  (defcap ATTRIBUTES-FROZEN:bool (token-id:string by:string)
    @event true)

  (defcap WRITE:bool (token-id:string key:string)
    @doc "The key's writer proves control of the guard fixed at creation."
    (with-read specs token-id { 'writers := ws }
      (let ((matches (filter (lambda (w:object{writer}) (= key (at 'key w))) ws)))
        (enforce (= 1 (length matches)) "unknown attribute key")
        (enforce-guard (at 'guard (at 0 matches))))))

  (defcap FREEZE:bool (token-id:string account:string)
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (enforce-guard (l::holder-guard token-id account))))

  ;; --- keys / views ---------------------------------------------------------------
  (defun attr-key:string (token-id:string key:string) (format "{}:{}" [token-id key]))
  (defun hist-key:string (token-id:string key:string version:integer) (format "{}:{}:{}" [token-id key version]))

  (defun get-spec:object{spec-row} (token-id:string) (read specs token-id))
  (defun get-keys:[string] (token-id:string)
    (map (at 'key) (at 'writers (read specs token-id))))
  (defun get-attribute:object{attribute-row} (token-id:string key:string)
    @doc "The current value, version and time of KEY; aborts if never written."
    (read attributes (attr-key token-id key)))
  (defun get-attribute-or:string (token-id:string key:string default:string)
    @doc "The current value of KEY, or DEFAULT if never written."
    (with-default-read attributes (attr-key token-id key) { 'value: default } { 'value := v } v))
  (defun get-attributes:[object] (token-id:string)
    @doc "Every key with its current row ({key, value, version}), unwritten keys at version 0."
    (map (lambda (k:string)
           (with-default-read attributes (attr-key token-id k) { 'value: "", 'version: 0 } { 'value := v, 'version := ver }
             { 'key: k, 'value: v, 'version: ver }))
         (get-keys token-id)))
  (defun get-attribute-at:object{history-row} (token-id:string key:string version:integer)
    @doc "On-chain history mode only: the value that VERSION replaced."
    (read attr-history (hist-key token-id key version)))
  (defun is-frozen:bool (token-id:string) (at 'frozen (read specs token-id)))

  (defun enforce-valid-spec:bool (ws:[object{writer}] mvb:integer h:string)
    (enforce (> (length ws) 0) "at least one attribute key is required")
    (enforce (<= (length ws) MAX-KEYS) (format "at most {} attribute keys" [MAX-KEYS]))
    (let ((ks (map (at 'key) ws)))
      (enforce (= (length ks) (length (distinct ks))) "duplicate attribute key")
      (map (lambda (k:string) (enforce (!= "" k) "attribute key must not be empty")) ks))
    (enforce (and (> mvb 0) (<= mvb MAX-VALUE-BYTES-CEILING))
      (format "max-value-bytes must be in [1, {}]" [MAX-VALUE-BYTES-CEILING]))
    (enforce (or (= h HISTORY-EVENTS) (= h HISTORY-ONCHAIN)) "history must be \"events\" or \"onchain\""))

  ;; --- the write path --------------------------------------------------------------
  (defun set-attribute:bool (token-id:string key:string value:string)
    @doc "Set KEY to VALUE. Only the key's writer; refused when frozen; the \
         \value is bounded; the version increments; history is recorded by \
         \event, and on chain too when the creator chose that."
    (with-read specs token-id { 'max-value-bytes := mvb, 'history := h, 'frozen := fz }
      (enforce (not fz) "attributes are frozen by the holder")
      (enforce (<= (length value) mvb) "attribute value too long")
      (with-capability (WRITE token-id key)
        (with-default-read attributes (attr-key token-id key) { 'value: "", 'version: 0 }
          { 'value := old, 'version := ver }
          (let ((nv (+ 1 ver)) (now (at 'block-time (chain-data))))
            (if (and (= h HISTORY-ONCHAIN) (> ver 0))
              (insert attr-history (hist-key token-id key nv) { 'value: old, 'version: nv, 'at: now })
              true)
            (write attributes (attr-key token-id key) { 'value: value, 'version: nv, 'updated: now })
            (emit-event (ATTRIBUTE-SET token-id key nv value))))))
    true)

  (defun freeze-copy:bool (token-id:string account:string)
    @doc "The holder of the WHOLE supply freezes every key for good (only when \
         \the creator enabled holder-freeze). One-way; no admin counterpart."
    (with-read specs token-id { 'holder-freeze := hf, 'frozen := fz }
      (enforce hf "this token does not allow a holder freeze")
      (enforce (not fz) "attributes are already frozen"))
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (let ((bal (l::holder-balance token-id account))
            (sup (l::token-supply token-id)))
        (enforce (> bal 0.0) "the account holds none of this token")
        (enforce (= bal sup) "only the holder of the whole supply may freeze the attributes")))
    (with-capability (FREEZE token-id account)
      (update specs token-id { 'frozen: true })
      (emit-event (ATTRIBUTES-FROZEN token-id account)))
    true)

  ;; --- token-policy hooks --------------------------------------------------------
  (defun enforce-init:bool (token:object{token-info})
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::INIT-CALL (at 'id token) (at 'precision token) (at 'uri token))))
    (let ((spec (read-msg SPEC-MSG-KEY)))
      (let ((ws:[object{writer}] (at 'writers spec))
            (mvb:integer (at 'max-value-bytes spec))
            (h:string (at 'history spec))
            (hf:bool (at 'holder-freeze spec)))
        (enforce-valid-spec ws mvb h)
        (insert specs (at 'id token)
          { 'writers: ws, 'max-value-bytes: mvb, 'history: h, 'holder-freeze: hf, 'frozen: false })
        (emit-event (ATTRIBUTES (at 'id token) (map (at 'key) ws) h hf))))
    true)

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

  ;; --- cross-chain passport: spec + every current attribute ------------------------
  (defun enforce-xchain-send:object (token:object{token-info} sender:string receiver:string receiver-guard:guard target-chain:string amount:decimal)
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::XCHAIN-SEND-CALL (at 'id token) sender receiver target-chain amount)))
    (let ((sp (read specs (at 'id token))))
      { 'writers: (at 'writers sp), 'max-value-bytes: (at 'max-value-bytes sp)
      , 'history: (at 'history sp), 'holder-freeze: (at 'holder-freeze sp), 'frozen: (at 'frozen sp)
      , 'attributes: (get-attributes (at 'id token)) }))

  (defun enforce-xchain-receive:bool (token:object{token-info} receiver:string receiver-guard:guard amount:decimal state:object)
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::XCHAIN-RECEIVE-CALL (at 'id token) receiver amount)))
    (let ((ws:[object{writer}] (at 'writers state))
          (mvb:integer (at 'max-value-bytes state))
          (h:string (at 'history state))
          (hf:bool (at 'holder-freeze state))
          (fz:bool (at 'frozen state))
          (attrs:[object] (at 'attributes state))
          (id (at 'id token)))
      (enforce-valid-spec ws mvb h)
      (with-default-read specs id { 'max-value-bytes: -1 } { 'max-value-bytes := existing }
        (if (= -1 existing)
          (insert specs id { 'writers: ws, 'max-value-bytes: mvb, 'history: h, 'holder-freeze: hf, 'frozen: fz })
          (with-read specs id { 'writers := lws, 'max-value-bytes := lmvb, 'history := lh, 'holder-freeze := lhf, 'frozen := lfz }
            (enforce (and (= ws lws) (and (= mvb lmvb) (and (= h lh) (= hf lhf)))) "attributes passport mismatch")
            (if (and fz (not lfz)) (update specs id { 'frozen: true }) true))))
      ;; the NEWER version of each key wins; equal versions must agree; an older
      ;; arrival never downgrades
      (map (lambda (a:object)
             (let ((k:string (at 'key a)) (v:string (at 'value a)) (ver:integer (at 'version a)))
               (enforce (contains k (map (at 'key) ws)) "attribute key not in the spec")
               (enforce (<= (length v) mvb) "attribute value too long")
               (with-default-read attributes (attr-key id k) { 'value: "", 'version: 0 } { 'value := lv, 'version := lver }
                 (if (> ver lver)
                   (write attributes (attr-key id k) { 'value: v, 'version: ver, 'updated: (at 'block-time (chain-data)) })
                   (if (= ver lver)
                     (enforce (= v lv) "attribute value mismatch at the same version")
                     true)))))
           attrs))
    true)

  (defun mint-decision:string (token:object{token-info}) (identity "abstain"))
  (defun uri-decision:string (token:object{token-info}) (identity "abstain"))
  (defun enforce-update-uri:bool (token:object{token-info} new-uri:string)
    (enforce false "this policy does not permit uri updates"))
)
