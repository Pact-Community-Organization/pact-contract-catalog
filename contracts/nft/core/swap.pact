;; nft.swap — NFT-for-NFT exchange, bundles, coin on top, bids (ADR-NFT-014).
;;
;; A holder OFFERS what they give for what they want:
;;   * GIVES: zero or more tokens, each an exact amount, escrowed at offer; and/or
;;     COIN-GIVE, coin escrowed at offer. Zero tokens + coin = a BID on a token
;;     nobody has listed (founder 2026-10-13: offers on unlisted tokens).
;;   * WANTS: one or more token ids with one amount; WANT-ALL true = every one of
;;     them (a bundle), false = any ONE of them, the taker's choice (an edition's
;;     copies are interchangeable balances under one id, so "any copy of this
;;     card" is that id; a serialised card is its own id). COIN-ASK is coin the
;;     taker adds on top (the "sweetener").
;;   * optionally the one account allowed to accept; optionally a venue and the
;;     flat coin fee it is paid; optionally an EXPIRY.
;; A taker ACCEPTS in one transaction: what they owe moves to the offerer, the
;; escrow moves to them, the coin on top is SETTLED like a sale. The offerer
;; may CANCEL an open offer; after its expiry ANYONE may CLOSE it — both return
;; the escrow to the offerer.
;;
;; The money. A flat protocol fee (governance) and a flat venue fee (declared
;; by the offerer) are paid by the taker in coin; zero fees drop. The coin on
;; top — coin-ask paid by the taker, coin-give paid by the offerer — is a
;; PRICE and is settled with the sale's legs: the protocol percentage, the
;; publisher (creation-venue) rate and the royalty plan of the PRICED token,
;; which is the first token the coin buys: for coin-ask the first give; for
;; coin-give the (chosen) want. Pure token-for-token pays no royalty — the
;; creator who wants every change of hands priced chooses `sale-only`, which
;; the ledger refuses here. Conservation is asserted on the escrow's coin.
;;
;; Node-safe: every read sits in a let or a with-read. Escrow: a capability-
;; guarded principal per offer, released only inside accept / cancel / close.

(namespace (read-string 'ns))

(module swap GOVERNANCE
  @doc "NFT-for-NFT exchange with bundles, coin on top, bids, expiry; per-offer escrow; flat and priced legs."

  (defconst ADMIN-KS:string (read-string 'admin-ks)
    "Namespaced governance keyset name, read once at deploy.")
  (defcap GOVERNANCE () (enforce-keyset ADMIN-KS))

  (defconst PARAMS-KEY:string "swap-fee")
  (defconst ID-PREFIX:string "x")
  (defconst MAX-LEGS:integer 16 "The most tokens on one side of an offer.")
  (defconst BPS-DENOM:integer 10000)
  (defconst EPOCH:time (time "1970-01-01T00:00:00Z"))

  ;; --- schemas ---------------------------------------------------------------------
  (defschema leg id:string amount:decimal)

  (defschema offer-row
    offerer:string
    offerer-guard:guard
    gives:[object{leg}]     ;; escrowed at offer (may be empty for a pure bid)
    coin-give:decimal       ;; escrowed coin the offerer adds (a bid, or coin on top)
    want-ids:[string]
    want-amount:decimal
    want-all:bool           ;; every wanted token (bundle) or any one (the taker's choice)
    coin-ask:decimal        ;; coin the taker adds on top
    taker:string            ;; "" = anyone
    venue-id:string         ;; "" = none
    venue-account:string
    venue-guard:guard
    venue-fee:decimal       ;; coin, flat, declared by the offerer, paid by the taker
    expires:integer         ;; unix seconds, 0 = never
    active:bool
    taken-by:string)
  (deftable offers:{offer-row})

  (defschema fee-params fee:decimal account:string guard:guard)
  (deftable params:{fee-params})

  ;; --- events ----------------------------------------------------------------------
  (defcap SWAP-OFFERED:bool (offer-id:string offerer:string gives:[object{leg}] coin-give:decimal want-ids:[string] want-amount:decimal want-all:bool coin-ask:decimal taker:string venue-id:string venue-fee:decimal expires:integer)
    @event true)
  (defcap SWAP-ACCEPTED:bool (offer-id:string taker:string want-id:string) @event true)
  (defcap SWAP-CANCELLED:bool (offer-id:string) @event true)
  (defcap SWAP-CLOSED:bool (offer-id:string by:string) @event true)
  (defcap SWAP-FEE:bool (offer-id:string account:string amount:decimal) @event true)
  (defcap SWAP-SETTLED:bool (offer-id:string priced-id:string price:decimal protocol:decimal creation-venue:decimal royalties:decimal proceeds:decimal) @event true)

  ;; --- capabilities ------------------------------------------------------------------
  (defcap OFFERER:bool (offer-id:string offerer-guard:guard)
    @doc "The offerer proves control of the guard the offer was made under."
    (enforce-guard offerer-guard))

  (defcap ESCROW:bool (offer-id:string)
    @doc "Spend authority over the offer's escrow. Weak body by design: acquired \
         \ONLY inside `accept` (after the taker delivered), `cancel` (after the \
         \offerer's guard passed) and `close` (after the expiry passed)."
    true)

  (defun escrow-guard:guard (offer-id:string) (create-capability-guard (ESCROW offer-id)))
  (defun escrow-account:string (offer-id:string) (create-principal (escrow-guard offer-id)))

  ;; --- identity + views --------------------------------------------------------------
  (defun create-offer-id:string (offerer:string gives:[object{leg}] want-ids:[string] nonce:string)
    @doc "x:{hash([offerer, gives, want-ids, nonce, chain-id])}: derived, so a client \
         \knows the escrow account before signing the transfers into it."
    (format "{}:{}" [ID-PREFIX (hash [offerer gives want-ids nonce (at 'chain-id (chain-data))])]))

  (defun now-seconds:integer () (floor (diff-time (at 'block-time (chain-data)) EPOCH)))
  (defun get-offer:object{offer-row} (offer-id:string) (read offers offer-id))
  (defun is-expired:bool (offer-id:string)
    (with-read offers offer-id { 'expires := e } (and (> e 0) (> (now-seconds) e))))

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

  ;; --- offer ---------------------------------------------------------------------------
  (defun offer:string
    ( nonce:string offerer:string gives:[object{leg}] coin-give:decimal
      want-ids:[string] want-amount:decimal want-all:bool coin-ask:decimal
      taker:string venue-id:string venue-fee:decimal expires:integer )
    @doc "Escrow GIVES (each an exact amount) and COIN-GIVE in exchange for WANT-AMOUNT \
         \of every wanted token (WANT-ALL) or any one of them, plus COIN-ASK on top. \
         \The offerer signs the ledger's TRANSFER of every give leg into the escrow \
         \and coin's TRANSFER of COIN-GIVE; those signatures ARE the authorization. \
         \Returns the offer id."
    (let ((give-ids (map (at 'id) gives)))
      (enforce (<= (length gives) MAX-LEGS) (format "at most {} tokens given" [MAX-LEGS]))
      (enforce (= (length give-ids) (length (distinct give-ids))) "gives must be distinct")
      (enforce (and (>= (length want-ids) 1) (<= (length want-ids) MAX-LEGS))
        (format "want-ids must name 1 to {} tokens" [MAX-LEGS]))
      (enforce (= (length want-ids) (length (distinct want-ids))) "want-ids must be distinct")
      (map (lambda (w:string) (enforce (not (contains w give-ids)) "cannot want a token being given")) want-ids)
      (enforce (or (> (length gives) 0) (> coin-give 0.0)) "an offer must give a token or coin")
      (enforce (not (and (> coin-give 0.0) (> coin-ask 0.0))) "coin flows one way: give coin or ask coin, not both")
      (enforce (>= coin-give 0.0) "coin-give must not be negative")
      (enforce (>= coin-ask 0.0) "coin-ask must not be negative")
      (coin.enforce-unit coin-give) (coin.enforce-unit coin-ask)
      (enforce (> want-amount 0.0) "want-amount must be positive")
      (enforce (>= venue-fee 0.0) "venue-fee must not be negative")
      (coin.enforce-unit venue-fee)
      (enforce (or (= expires 0) (> expires (now-seconds))) "expiry must be in the future")
      (map (lambda (g:object{leg})
             (enforce (> (at 'amount g) 0.0) "a given amount must be positive")
             (ledger.enforce-unit (at 'id g) (at 'amount g)))
           gives)
      (map (lambda (w:string) (ledger.enforce-unit w want-amount)) want-ids)
      (if (!= taker "") (enforce (contains (util.check-reserved taker) ["k" "w"]) "reserved taker must be a principal account") true)
      (enforce (or (= venue-id "") (> venue-fee 0.0)) "a named venue needs a positive venue-fee")
      (enforce (or (!= venue-id "") (= venue-fee 0.0)) "a venue-fee needs a venue"))
    (let* ((offer-id (create-offer-id offerer gives want-ids nonce))
           (escrow (escrow-account offer-id))
           (eg (escrow-guard offer-id))
           ;; the offerer's guard: the ledger account of the first give, else their coin account
           (og:guard (if (> (length gives) 0) (ledger.account-guard (at 'id (at 0 gives)) offerer) (at 'guard (coin.details offerer))))
           (venue (if (= venue-id "")
                    { 'account: "", 'guard: (create-capability-guard (GOVERNANCE)) }
                    (let ((v (venue-registry.get-venue venue-id))) { 'account: (at 'account v), 'guard: (at 'guard v) }))))
      (insert offers offer-id
        { 'offerer: offerer, 'offerer-guard: og, 'gives: gives, 'coin-give: coin-give
        , 'want-ids: want-ids, 'want-amount: want-amount, 'want-all: want-all, 'coin-ask: coin-ask, 'taker: taker
        , 'venue-id: venue-id, 'venue-account: (at 'account venue), 'venue-guard: (at 'guard venue), 'venue-fee: venue-fee
        , 'expires: expires, 'active: true, 'taken-by: "" })
      (map (lambda (g:object{leg}) (ledger.transfer-create (at 'id g) offerer escrow eg (at 'amount g))) gives)
      (if (> coin-give 0.0) (coin.transfer-create offerer escrow eg coin-give) "")
      (emit-event (SWAP-OFFERED offer-id offerer gives coin-give want-ids want-amount want-all coin-ask taker venue-id venue-fee expires))
      offer-id))

  ;; --- the priced leg: coin on top settled like a sale -------------------------------
  (defun bps-cut:decimal (price:decimal bps:integer)
    (if (> bps 0) (floor (/ (* price (dec bps)) (dec BPS-DENOM)) (coin.precision)) 0.0))

  (defun royalty-attached:bool (token:object{token-policy.token-info})
    (contains (format "{}" [royalty-policy]) (map (lambda (p:module{token-policy}) (format "{}" [p])) (at 'policies token))))

  (defun merge-leg:[object] (acc:[object] l:object)
    @doc "Merge L into ACC, summing amounts for a payee already present; drops zero legs."
    (if (<= (at 'amount l) 0.0)
      acc
      (if (contains (at 'account l) (map (at 'account) acc))
        (map (lambda (x:object) (if (= (at 'account x) (at 'account l)) (+ { 'amount: (+ (at 'amount x) (at 'amount l)) } x) x)) acc)
        (+ acc [l]))))

  (defun settle-coin:bool (offer-id:string priced-id:string seller:string seller-guard:guard price:decimal)
    @doc "Pay PRICE from the offer's escrow with the sale's legs for PRICED-ID sold by \
         \SELLER: protocol percentage, creation-venue rate, royalty plan, remainder to the \
         \seller. Requires ESCROW in scope. Conservation: exactly PRICE leaves the escrow."
    (require-capability (ESCROW offer-id))
    (let* ((escrow (escrow-account offer-id))
           (before (coin.get-balance escrow))
           (token (ledger.get-token-info priced-id))
           (proto (policy-manager.get-protocol))
           (protocol (bps-cut price (at 'bps proto)))
           (cv (policy-manager.get-creation-venue priced-id))
           (cv-fee (bps-cut price (policy-manager.creation-venue-bps priced-id seller (at 'author token))))
           (plan (if (royalty-attached token) (royalty-policy.plan-for-sale token seller) []))
           (cuts (filter (lambda (c:object) (> (at 'amount c) 0.0))
                   (map (lambda (b:object) { 'account: (at 'account b), 'guard: (at 'guard b), 'amount: (bps-cut price (at 'bps b)) }) plan)))
           (royalties (fold (+) 0.0 (map (at 'amount) cuts)))
           (proceeds (- price (+ protocol (+ cv-fee royalties))))
           (raw (+ (if (> protocol 0.0) [{ 'account: (at 'account proto), 'guard: (at 'guard proto), 'amount: protocol }] [])
                   (+ (if (> cv-fee 0.0) [{ 'account: (at 'account cv), 'guard: (at 'guard cv), 'amount: cv-fee }] [])
                      (+ cuts (if (> proceeds 0.0) [{ 'account: seller, 'guard: seller-guard, 'amount: proceeds }] [])))))
           ;; one payee may hold several legs (a creator selling their own token: royalty + proceeds);
           ;; a managed TRANSFER installs once per payee, so legs are MERGED before paying (the manager's rule)
           (legs (fold (merge-leg) [] raw)))
      (enforce (>= proceeds 0.0) "protocol + creation venue + royalties exceed the coin on top")
      (map (lambda (l:object)
             (install-capability (coin.TRANSFER escrow (at 'account l) (at 'amount l)))
             (coin.transfer-create escrow (at 'account l) (at 'guard l) (at 'amount l)))
           legs)
      (enforce (= (coin.get-balance escrow) (- before price)) "escrow coin not fully settled — conservation failed")
      (emit-event (SWAP-SETTLED offer-id priced-id price protocol cv-fee royalties proceeds))
      true))

  ;; --- accept --------------------------------------------------------------------------
  (defun accept:bool (offer-id:string taker:string want-id:string)
    @doc "Complete the exchange. WANT-ID is the taker's choice among the wanted tokens \
         \(ignored, pass \"\", when the offer wants ALL of them). TAKER signs the \
         \ledger's TRANSFER of each wanted token to the offerer, coin's TRANSFER of \
         \each flat fee to its payee, and coin's TRANSFER of COIN-ASK into the escrow."
    (with-read offers offer-id
      { 'offerer := offerer, 'offerer-guard := og, 'gives := gives, 'coin-give := coin-give
      , 'want-ids := want-ids, 'want-amount := want-amount, 'want-all := want-all, 'coin-ask := coin-ask
      , 'taker := allowed, 'active := active, 'expires := expires
      , 'venue-account := va, 'venue-guard := vg, 'venue-fee := vfee }
      (enforce active "offer is not active")
      (enforce (or (= expires 0) (<= (now-seconds) expires)) "offer has expired")
      (enforce (or (= allowed "") (= allowed taker)) "offer is reserved for another taker")
      (enforce (!= taker offerer) "the offerer cannot accept their own offer")
      (if want-all true (enforce (contains want-id want-ids) "that token is not one the offer wants"))
      (let* ((chosen:[string] (if want-all want-ids [want-id]))
             (priced-want:string (at 0 chosen))
             (tg:guard (ledger.account-guard priced-want taker))
             (p (get-swap-fee))
             (escrow (escrow-account offer-id)))
        ;; flat fees first: a taker who cannot pay never moves a token
        (if (> (at 'fee p) 0.0)
          (let ((_ (coin.transfer-create taker (at 'account p) (at 'guard p) (at 'fee p))))
            (emit-event (SWAP-FEE offer-id (at 'account p) (at 'fee p))))
          true)
        (if (> vfee 0.0)
          (let ((_ (coin.transfer-create taker va vg vfee)))
            (emit-event (SWAP-FEE offer-id va vfee)))
          true)
        ;; the wanted tokens to the offerer (taker-signed)
        (map (lambda (w:string) (ledger.transfer-create w taker offerer og want-amount)) chosen)
        ;; coin on top from the taker: into the escrow, then settled against the first give
        (if (> coin-ask 0.0) (coin.transfer-create taker escrow (escrow-guard offer-id) coin-ask) "")
        (with-capability (ESCROW offer-id)
          ;; the escrow to the taker
          (map (lambda (g:object{leg})
                 (install-capability (ledger.TRANSFER (at 'id g) escrow taker (at 'amount g)))
                 (ledger.transfer-create (at 'id g) escrow taker tg (at 'amount g)))
               gives)
          (if (> coin-ask 0.0) (settle-coin offer-id (at 'id (at 0 gives)) offerer og coin-ask) true)
          ;; the offerer's coin (a bid, or coin on top): settled against the wanted token, sold by the taker
          (if (> coin-give 0.0) (settle-coin offer-id priced-want taker tg coin-give) true))
        (update offers offer-id { 'active: false, 'taken-by: taker })
        (emit-event (SWAP-ACCEPTED offer-id taker (if want-all "" want-id)))
        true)))

  ;; --- cancel / close ------------------------------------------------------------------
  (defun return-escrow:bool (offer-id:string)
    @doc "Everything escrowed goes back to the offerer. Requires ESCROW in scope."
    (require-capability (ESCROW offer-id))
    (with-read offers offer-id { 'offerer := offerer, 'offerer-guard := og, 'gives := gives, 'coin-give := coin-give }
      (let ((escrow (escrow-account offer-id)))
        (map (lambda (g:object{leg})
               (install-capability (ledger.TRANSFER (at 'id g) escrow offerer (at 'amount g)))
               (ledger.transfer-create (at 'id g) escrow offerer og (at 'amount g)))
             gives)
        (if (> coin-give 0.0)
          (let ((_ (install-capability (coin.TRANSFER escrow offerer coin-give))))
            (coin.transfer-create escrow offerer og coin-give))
          "")
        true)))

  (defun cancel:bool (offer-id:string)
    @doc "The offerer withdraws an open offer; the escrow returns to them."
    (with-read offers offer-id { 'offerer-guard := og, 'active := active }
      (enforce active "offer is not active")
      (with-capability (OFFERER offer-id og)
        (with-capability (ESCROW offer-id) (return-escrow offer-id)))
      (update offers offer-id { 'active: false })
      (emit-event (SWAP-CANCELLED offer-id))
      true))

  (defun close:bool (offer-id:string by:string)
    @doc "After the expiry ANYONE may close an open offer; the escrow returns to the \
         \offerer. No stale escrow outlives its deadline by more than one transaction."
    (with-read offers offer-id { 'active := active, 'expires := expires }
      (enforce active "offer is not active")
      (enforce (and (> expires 0) (> (now-seconds) expires)) "offer has not expired")
      (with-capability (ESCROW offer-id) (return-escrow offer-id))
      (update offers offer-id { 'active: false })
      (emit-event (SWAP-CLOSED offer-id by))
      true))
)
