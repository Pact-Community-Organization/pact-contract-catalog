;; nft.swap — NFT-for-NFT exchange (ADR-NFT-014): the price IS a specific token.
;;
;; A holder OFFERS an exact amount of one token for an exact amount of ANY ONE
;; of the tokens they name — one id for a specific card, several ids for "any
;; of these" (founder, 2026-10-12: any copy, or a specific copy) — and,
;; optionally, who may take it. The offered copies move into a per-offer escrow
;; that only this module can release. A TAKER who holds one of the wanted tokens
;; ACCEPTS with that token in one transaction: the wanted copies go to the
;; offerer, the escrowed copies go to the taker. The offerer may CANCEL an open
;; offer at any time; the escrow returns.
;;
;; Copies. An edition's copies are interchangeable balances under ONE token id,
;; so "any copy of this edition" is that id; a serialised card is its own id,
;; so "this exact card" is that id. "Any of these cards" is the list.
;;
;; What the exchange pays. A barter has no price, so there is no percentage to
;; take and no royalty to compute. The framework's model is "a percentage of
;; everything" (ADR-NFT-006), so a swap pays FLAT fees instead, in the chain's
;; coin: a protocol fee set by governance (the same party that sets the sale
;; protocol leg) and, if the offerer named a venue, a venue fee the offerer
;; declared with the offer — both paid by the taker, both visible before the
;; take. Zero fees drop. Creators who want every change of hands priced and
;; royaltied choose `sale-only` at creation (ADR-NFT-007): such tokens cannot
;; be offered or taken here, because the ledger's transfer path — which this
;; module uses unchanged, every attached policy included — refuses them.
;;
;; Node-safe: every read sits in a let or a with-read; no read inside enforce.
;; Escrow: a capability-guarded principal per offer, released only inside
;; `take` and `cancel` (the vault pattern of the pack engine, ADR-NFT-012).

(namespace (read-string 'ns))

(module swap GOVERNANCE
  @doc "NFT-for-NFT exchange with per-offer escrow and flat coin fees."

  (defconst ADMIN-KS:string (read-string 'admin-ks)
    "Namespaced governance keyset name, read once at deploy.")
  (defcap GOVERNANCE () (enforce-keyset ADMIN-KS))

  (defconst PARAMS-KEY:string "swap-fee")
  (defconst ID-PREFIX:string "x")
  (defconst MAX-WANTS:integer 16
    "The most alternatives one offer may name (a bounded loop at offer and accept).")

  ;; --- schemas ---------------------------------------------------------------------
  (defschema offer-row
    offerer:string
    offerer-guard:guard
    give-id:string
    give-amount:decimal
    want-ids:[string]       ;; any ONE of these, the taker's choice
    want-amount:decimal
    taker:string            ;; "" = anyone
    venue-id:string         ;; "" = none
    venue-account:string
    venue-guard:guard
    venue-fee:decimal       ;; coin, flat, declared by the offerer
    active:bool
    taken-by:string)
  (deftable offers:{offer-row})

  (defschema fee-params
    fee:decimal
    account:string
    guard:guard)
  (deftable params:{fee-params})

  ;; --- events ----------------------------------------------------------------------
  (defcap SWAP-OFFERED:bool (offer-id:string offerer:string give-id:string give-amount:decimal want-ids:[string] want-amount:decimal taker:string venue-id:string venue-fee:decimal)
    @event true)
  (defcap SWAP-ACCEPTED:bool (offer-id:string taker:string want-id:string) @event true)
  (defcap SWAP-CANCELLED:bool (offer-id:string) @event true)
  (defcap SWAP-FEE:bool (offer-id:string account:string amount:decimal) @event true)

  ;; --- capabilities ------------------------------------------------------------------
  (defcap OFFERER:bool (offer-id:string offerer-guard:guard)
    @doc "The offerer proves control of the guard the offer was made under."
    (enforce-guard offerer-guard))

  (defcap ESCROW:bool (offer-id:string)
    @doc "Spend authority over the offer's escrow. Weak body by design: acquired \
         \ONLY inside `accept` (after the taker delivered) and `cancel` (after the \
         \offerer's guard passed)."
    true)

  (defun escrow-guard:guard (offer-id:string) (create-capability-guard (ESCROW offer-id)))
  (defun escrow-account:string (offer-id:string) (create-principal (escrow-guard offer-id)))

  ;; --- identity ----------------------------------------------------------------------
  (defun create-offer-id:string (offerer:string give-id:string want-ids:[string] nonce:string)
    @doc "x:{hash([offerer, give-id, want-ids, nonce, chain-id])}: derived, so a client \
         \knows the escrow account before signing the transfer into it."
    (format "{}:{}" [ID-PREFIX (hash [offerer give-id want-ids nonce (at 'chain-id (chain-data))])]))

  ;; --- governance: the flat protocol fee --------------------------------------------
  (defun set-swap-fee:bool (fee:decimal account:string guard:guard)
    @doc "Governance sets the flat coin fee a taker pays per exchange, and its payee."
    (enforce (>= fee 0.0) "swap fee must not be negative")
    (coin.enforce-unit fee)
    (if (> fee 0.0)
      (enforce (validate-principal guard account) "fee account must be the principal of its guard")
      true)
    (with-capability (GOVERNANCE)
      (write params PARAMS-KEY { 'fee: fee, 'account: account, 'guard: guard }))
    true)

  (defun get-swap-fee:object{fee-params} ()
    (with-default-read params PARAMS-KEY
      { 'fee: 0.0, 'account: "", 'guard: (create-capability-guard (GOVERNANCE)) }
      { 'fee := f, 'account := a, 'guard := g } { 'fee: f, 'account: a, 'guard: g }))

  ;; --- views ---------------------------------------------------------------------------
  (defun get-offer:object{offer-row} (offer-id:string) (read offers offer-id))

  ;; --- offer ---------------------------------------------------------------------------
  (defun offer:string
    ( nonce:string offerer:string give-id:string give-amount:decimal
      want-ids:[string] want-amount:decimal taker:string venue-id:string venue-fee:decimal )
    @doc "Escrow GIVE-AMOUNT of GIVE-ID in exchange for WANT-AMOUNT of any ONE of \
         \WANT-IDS (one id = that exact token; several = the taker chooses). TAKER \
         \\"\" lets anyone take; a venue, if named, is paid VENUE-FEE coin by the \
         \taker. The offerer signs the ledger's TRANSFER of the escrowed copies; that \
         \signature IS the authorization — the offerer's guard is the ledger's \
         \account guard, read here, never a payload. Returns the offer id."
    (enforce (and (>= (length want-ids) 1) (<= (length want-ids) MAX-WANTS))
      (format "want-ids must name 1 to {} tokens" [MAX-WANTS]))
    (enforce (= (length want-ids) (length (distinct want-ids))) "want-ids must be distinct")
    (enforce (not (contains give-id want-ids)) "cannot want the token being given")
    (enforce (> give-amount 0.0) "give-amount must be positive")
    (enforce (> want-amount 0.0) "want-amount must be positive")
    (enforce (>= venue-fee 0.0) "venue-fee must not be negative")
    (coin.enforce-unit venue-fee)
    (ledger.enforce-unit give-id give-amount)
    ;; every wanted token must exist (a typo would make an offer nobody can accept) and take the amount
    (map (lambda (w:string) (ledger.enforce-unit w want-amount)) want-ids)
    (if (!= taker "") (enforce (contains (util.check-reserved taker) ["k" "w"]) "reserved taker must be a principal account") true)
    (let* ((offer-id (create-offer-id offerer give-id want-ids nonce))
           (og:guard (ledger.account-guard give-id offerer))
           (venue (if (= venue-id "")
                    { 'account: "", 'guard: (create-capability-guard (GOVERNANCE)) }
                    (let ((v (venue-registry.get-venue venue-id))) { 'account: (at 'account v), 'guard: (at 'guard v) }))))
      (enforce (or (= venue-id "") (> venue-fee 0.0)) "a named venue needs a positive venue-fee")
      (enforce (or (!= venue-id "") (= venue-fee 0.0)) "a venue-fee needs a venue")
      (insert offers offer-id
        { 'offerer: offerer, 'offerer-guard: og, 'give-id: give-id, 'give-amount: give-amount
        , 'want-ids: want-ids, 'want-amount: want-amount, 'taker: taker
        , 'venue-id: venue-id, 'venue-account: (at 'account venue), 'venue-guard: (at 'guard venue), 'venue-fee: venue-fee
        , 'active: true, 'taken-by: "" })
      (ledger.transfer-create give-id offerer (escrow-account offer-id) (escrow-guard offer-id) give-amount)
      (emit-event (SWAP-OFFERED offer-id offerer give-id give-amount want-ids want-amount taker venue-id venue-fee))
      offer-id))

  ;; --- accept --------------------------------------------------------------------------
  (defun accept:bool (offer-id:string taker:string want-id:string)
    @doc "Complete the exchange with WANT-ID, one of the offer's wanted tokens: \
         \TAKER's copies of it go to the offerer, the escrow goes to TAKER, the flat \
         \fees go to their payees. TAKER signs the ledger's TRANSFER of the wanted \
         \copies and coin's TRANSFER of each fee; those signatures are the authorization."
    (with-read offers offer-id
      { 'offerer := offerer, 'offerer-guard := og, 'give-id := give-id, 'give-amount := give-amount
      , 'want-ids := want-ids, 'want-amount := want-amount, 'taker := allowed, 'active := active
      , 'venue-account := va, 'venue-guard := vg, 'venue-fee := vfee }
      (enforce active "offer is not active")
      (enforce (contains want-id want-ids) "that token is not one the offer wants")
      (enforce (or (= allowed "") (= allowed taker)) "offer is reserved for another taker")
      (enforce (!= taker offerer) "the offerer cannot accept their own offer")
      (let ((tg:guard (ledger.account-guard want-id taker))
            (p (get-swap-fee)))
        ;; fees first: a taker who cannot pay never moves a token
        (if (> (at 'fee p) 0.0)
          (let ((_ (coin.transfer-create taker (at 'account p) (at 'guard p) (at 'fee p))))
            (emit-event (SWAP-FEE offer-id (at 'account p) (at 'fee p))))
          true)
        (if (> vfee 0.0)
          (let ((_ (coin.transfer-create taker va vg vfee)))
            (emit-event (SWAP-FEE offer-id va vfee)))
          true)
        ;; the wanted copies to the offerer (taker-signed), then the escrow to the taker
        (ledger.transfer-create want-id taker offerer og want-amount)
        (with-capability (ESCROW offer-id)
          (install-capability (ledger.TRANSFER give-id (escrow-account offer-id) taker give-amount))
          (ledger.transfer-create give-id (escrow-account offer-id) taker tg give-amount))
        (update offers offer-id { 'active: false, 'taken-by: taker })
        (emit-event (SWAP-ACCEPTED offer-id taker want-id))
        true)))

  ;; --- cancel --------------------------------------------------------------------------
  (defun cancel:bool (offer-id:string)
    @doc "The offerer withdraws an open offer; the escrow returns to them."
    (with-read offers offer-id
      { 'offerer := offerer, 'offerer-guard := og, 'give-id := give-id, 'give-amount := give-amount, 'active := active }
      (enforce active "offer is not active")
      (with-capability (OFFERER offer-id og)
        (with-capability (ESCROW offer-id)
          (install-capability (ledger.TRANSFER give-id (escrow-account offer-id) offerer give-amount))
          (ledger.transfer-create give-id (escrow-account offer-id) offerer og give-amount)))
      (update offers offer-id { 'active: false })
      (emit-event (SWAP-CANCELLED offer-id))
      true))
)
