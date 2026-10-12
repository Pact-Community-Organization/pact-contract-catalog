;; nft.pack-engine — packs of cards, drawn by a public beacon from a sealed vault.
;;
;; ADR-NFT-012 (founder, 2026-10-12). A SERIES is configured by an artist from
;; cards they authored on this chain: how many packs, how many cards per pack,
;; which SLOTS a pack has (e.g. 2 commons + 1 rare-or-better), which TIERS fill
;; each slot, and how many copies of each card the series holds. At SEALING the
;; artist mints every card the series can ever deliver into the series' VAULT
;; (a capability-guarded account only `reveal` can debit) and mints the sealed
;; PACKS (an ordinary token the artist created) to themselves. Odds are COUNTS:
;; draws are without replacement from what the vault holds, so the published
;; counts are the odds, exactly, and an opening can never fail for lack of cards.
;;
;; OPENING is two transactions. `request-open`: the holder BURNS one sealed pack
;; (the ledger proves ownership) and is assigned the first beacon round at least
;; MIN-MARGIN seconds in the future; requests for a round queue in order.
;; `reveal`: ANYONE submits that round's beacon; the registered verifier proves it
;; was published; the queue is drawn in request order from a seed bound to the
;; series, the round and each request, and the cards move from the vault to each
;; opener. No house input, no block hash, no re-roll, no admin path to the vault.
;; After sealing the artist has no power left: no reprice, no reroll, no
;; withdrawal of the pool (no_pause_max_decentralization).
;;
;; MONEY never touches this module: sealed packs and cards are sold through the
;; ledger's sale defpact and the manager's settlement like any other token.
;;
;; Cards in a series must be transferable (transfer-mode "free" or no mode
;; policy) because delivery is a free transfer from the vault; sealed packs may
;; carry any mode. The engine holds the beacon verifier as a modref of
;; `beacon-verifier`, registered once by governance.

(namespace (read-string 'ns))

(module pack-engine GOVERNANCE
  @doc "Series of card packs drawn by a public beacon from a sealed, \
       \capability-guarded vault; counts are the odds."

  (defconst ADMIN-KS:string (read-string 'admin-ks)
    @doc "Admin keyset name, captured ONCE at deploy — never read from a \
         \caller's payload at enforcement time.")

  (defcap GOVERNANCE ()
    (enforce-keyset ADMIN-KS))

  ;; --- bounds (every operation a known size) -------------------------------------
  (defconst MIN-MARGIN:decimal 120.0
    @doc "Seconds between an open request and the beacon round it is pinned to \
         \(the roulette rule: never under 120 s, so no party knows the beacon \
         \when committing).")
  (defconst MAX-CARDS-PER-PACK:integer 10)
  (defconst MAX-SLOTS:integer 4)
  (defconst MAX-POOL-CARDS:integer 64)
  (defconst MAX-PACKS:integer 10000)
  (defconst MAX-QUEUE:integer 5
    @doc "Requests revealed per round at most; a full round pushes a request to \
         \the next round, keeping every reveal under the block gas ceiling.")
  (defconst MAX-ROUND-SEARCH:integer 20)
  (defconst SERIES-ID-PREFIX:string "s")

  ;; --- the verifier (registered once) -------------------------------------------
  (defschema verifier-ref v:module{beacon-verifier})
  (deftable verifiers:{verifier-ref})
  (defconst VERIFIER-KEY:string "v")

  (defun set-verifier:bool (v:module{beacon-verifier})
    @doc "One-time registration of the beacon verifier this engine trusts. Gov-gated."
    (with-capability (GOVERNANCE)
      (insert verifiers VERIFIER-KEY { 'v: v }))
    true)

  (defun verifier:module{beacon-verifier} ()
    (at 'v (read verifiers VERIFIER-KEY)))

  ;; --- schemas -----------------------------------------------------------------
  (defschema slot
    name:string
    picks:integer
    tiers:[string])

  (defschema series
    name:string
    artist:string
    artist-guard:guard
    pack-token:string
    cards-per-pack:integer
    packs-total:integer
    slots:[object{slot}]
    card-ids:[string]
    locked:bool
    sealed:bool
    opened:integer
    origin-chain:string)
  (deftable series-table:{series})

  (defschema pool-card
    token-id:string
    tier:string
    count:integer
    left:integer)
  (deftable pool:{pool-card})

  (defschema open-request
    series-id:string
    opener:string
    opener-guard:guard
    round:integer
    revealed:bool)
  (deftable requests:{open-request})

  (defschema round-queue ids:[string])
  (deftable queues:{round-queue})

  ;; --- events -----------------------------------------------------------------------
  (defcap SERIES-CREATED:bool (series-id:string artist:string pack-token:string cards-per-pack:integer packs-total:integer) @event true)
  (defcap POOL-CARD-ADDED:bool (series-id:string token-id:string tier:string count:integer) @event true)
  (defcap SERIES-LOCKED:bool (series-id:string) @event true)
  (defcap SERIES-SEALED:bool (series-id:string vault:string packs-total:integer) @event true)
  (defcap OPEN-REQUESTED:bool (request-id:string series-id:string opener:string rnd:integer) @event true)
  (defcap CARD-REVEALED:bool (request-id:string token-id:string) @event true)
  (defcap OPENED:bool (request-id:string series-id:string rnd:integer) @event true)

  ;; --- capabilities -------------------------------------------------------------------
  (defcap ARTIST:bool (series-id:string artist-guard:guard)
    @doc "The series' artist proves control of the guard the id is derived from."
    (enforce-guard artist-guard))

  (defcap VAULT:bool (series-id:string)
    @doc "Spend authority over the series' vault. Acquired ONLY inside `reveal`."
    true)

  (defun vault-guard:guard (series-id:string) (create-capability-guard (VAULT series-id)))
  (defun vault-account:string (series-id:string) (create-principal (vault-guard series-id)))

  ;; --- identity --------------------------------------------------------------------------
  (defun create-series-id:string (name:string artist-guard:guard)
    @doc "s:{hash([name, artist-guard, chain-id])}: a series name belongs to the \
         \guard that controls it, on this chain."
    (format "{}:{}" [SERIES-ID-PREFIX (hash [name artist-guard (at 'chain-id (chain-data))])]))

  (defun pool-key:string (series-id:string token-id:string) (format "{}|{}" [series-id token-id]))
  (defun queue-key:string (series-id:string rnd:integer) (format "{}|{}" [series-id rnd]))

  ;; --- views ------------------------------------------------------------------------------
  (defun get-series:object{series} (series-id:string) (read series-table series-id))
  (defun get-pool-card:object{pool-card} (series-id:string token-id:string) (read pool (pool-key series-id token-id)))
  (defun get-odds:[object{pool-card}] (series-id:string)
    @doc "Every card in the series with its configured count and what is left: \
         \the odds, readable at any moment."
    (map (lambda (t:string) (read pool (pool-key series-id t))) (at 'card-ids (read series-table series-id))))
  (defun get-request:object{open-request} (request-id:string) (read requests request-id))
  (defun get-queue:[string] (series-id:string rnd:integer)
    (with-default-read queues (queue-key series-id rnd) { 'ids: [] } { 'ids := ids } ids))

  ;; --- configuration (artist-signed, before sealing) ------------------------------------
  (defun enforce-valid-slots:bool (slots:[object{slot}] cards-per-pack:integer)
    (enforce (and (> (length slots) 0) (<= (length slots) MAX-SLOTS))
      (format "between 1 and {} slots" [MAX-SLOTS]))
    (map (lambda (s:object{slot})
           (enforce (> (at 'picks s) 0) "a slot picks at least one card")
           (enforce (> (length (at 'tiers s)) 0) "a slot names at least one tier"))
         slots)
    (enforce (= cards-per-pack (fold (+) 0 (map (at 'picks) slots))) "slot picks must sum to cards-per-pack")
    ;; a tier belongs to exactly one slot, so the vault partitions cleanly
    (let ((all-tiers (fold (+) [] (map (at 'tiers) slots))))
      (enforce (= (length all-tiers) (length (distinct all-tiers))) "a tier may appear in one slot only")))

  (defun create-series:string
    ( name:string artist-guard:guard pack-token:string
      cards-per-pack:integer packs-total:integer slots:[object{slot}] )
    @doc "Open a series. PACK-TOKEN is a token the artist authored on this chain \
         \with an issuance run of exactly PACKS-TOTAL (so no pack can ever exist \
         \beyond the series). Returns the series id."
    (enforce (!= "" name) "series name required")
    (enforce (and (> cards-per-pack 0) (<= cards-per-pack MAX-CARDS-PER-PACK))
      (format "cards-per-pack must be in [1, {}]" [MAX-CARDS-PER-PACK]))
    (enforce (and (> packs-total 0) (<= packs-total MAX-PACKS))
      (format "packs-total must be in [1, {}]" [MAX-PACKS]))
    (enforce-valid-slots slots cards-per-pack)
    (let* ((artist:string (create-principal artist-guard))
           (pt (ledger.get-token-info pack-token))
           (run (issuance-policy.get-issuance pack-token)))
      (enforce (= artist (at 'author pt)) "the pack token must be authored by the artist")
      (enforce (= (at 'origin-chain pt) (at 'chain-id (chain-data))) "the pack token must be born on this chain")
      (enforce (= 0 (at 'precision pt)) "the pack token must have precision 0")
      (enforce (= (dec packs-total) (at 'max-issued run)) "the pack token's print run must equal packs-total")
      (enforce (= 0.0 (at 'issued run)) "the pack token must not have been minted yet")
      (let ((id:string (create-series-id name artist-guard)))
        (with-capability (ARTIST id artist-guard)
          (insert series-table id
            { 'name: name, 'artist: artist, 'artist-guard: artist-guard, 'pack-token: pack-token
            , 'cards-per-pack: cards-per-pack, 'packs-total: packs-total, 'slots: slots
            , 'card-ids: [], 'locked: false, 'sealed: false, 'opened: 0
            , 'origin-chain: (at 'chain-id (chain-data)) })
          (emit-event (SERIES-CREATED id artist pack-token cards-per-pack packs-total)))
        id)))

  (defun tier-known:bool (slots:[object{slot}] tier:string)
    (contains tier (fold (+) [] (map (at 'tiers) slots))))

  (defun add-pool-card:bool (series-id:string token-id:string tier:string count:integer)
    @doc "Put COUNT copies of TOKEN-ID into TIER. The card must be authored by \
         \the artist on this chain and must still be mintable for COUNT."
    (enforce (> count 0) "count must be positive")
    (with-read series-table series-id
      { 'artist := artist, 'artist-guard := ag, 'slots := slots, 'card-ids := ids, 'locked := locked }
      (enforce (not locked) "the series is locked")
      (enforce (tier-known slots tier) "unknown tier")
      (enforce (< (length ids) MAX-POOL-CARDS) (format "at most {} cards in a series" [MAX-POOL-CARDS]))
      (let ((t (ledger.get-token-info token-id))
            (run (issuance-policy.get-issuance token-id)))
        (enforce (= artist (at 'author t)) "a pool card must be authored by the artist")
        (enforce (= (at 'origin-chain t) (at 'chain-id (chain-data))) "a pool card must be born on this chain")
        (enforce (= 0 (at 'precision t)) "a pool card must have precision 0")
        (enforce (<= (dec count) (- (at 'max-issued run) (at 'issued run))) "count exceeds the card's remaining print run"))
      (with-capability (ARTIST series-id ag)
        (insert pool (pool-key series-id token-id) { 'token-id: token-id, 'tier: tier, 'count: count, 'left: count })
        (update series-table series-id { 'card-ids: (+ ids [token-id]) })
        (emit-event (POOL-CARD-ADDED series-id token-id tier count))))
    true)

  ;; --- sealing: lock, mint the vault (in batches), finish ---------------------------------
  (defun slot-count:integer (series-id:string s:object{slot} ids:[string])
    (fold (+) 0
      (map (lambda (t:string)
             (with-read pool (pool-key series-id t) { 'tier := tier, 'count := c }
               (if (contains tier (at 'tiers s)) c 0)))
           ids)))

  (defun lock-series:bool (series-id:string)
    @doc "Freeze the configuration. Every slot's counts must equal exactly \
         \picks x packs-total, so the vault partitions into whole packs with \
         \nothing left over and nothing missing."
    (with-read series-table series-id
      { 'artist-guard := ag, 'slots := slots, 'card-ids := ids, 'packs-total := n, 'locked := locked }
      (enforce (not locked) "already locked")
      (enforce (> (length ids) 0) "the series has no cards")
      (map (lambda (s:object{slot})
             (enforce (= (slot-count series-id s ids) (* (at 'picks s) n))
               (format "slot {} holds {} cards, needs exactly {}" [(at 'name s) (slot-count series-id s ids) (* (at 'picks s) n)])))
           slots)
      (with-capability (ARTIST series-id ag)
        (update series-table series-id { 'locked: true })
        (emit-event (SERIES-LOCKED series-id))))
    true)

  (defun mint-pool:bool (series-id:string token-ids:[string])
    @doc "Mint the configured copies of each listed card into the vault. The \
         \ARTIST signs (the ledger's author-only mint); call in batches that fit \
         \the block gas. Refused before lock and after seal."
    (with-read series-table series-id { 'locked := locked, 'sealed := sealed }
      (enforce locked "lock the series first")
      (enforce (not sealed) "the series is sealed"))
    (let ((vault (vault-account series-id)) (vg (vault-guard series-id)))
      (map (lambda (t:string)
             (with-read pool (pool-key series-id t) { 'count := c }
               (ledger.mint t vault vg (dec c))))
           token-ids))
    true)

  (defun seal-series:bool (series-id:string)
    @doc "Verify the vault holds exactly every configured copy, mint the sealed \
         \packs to the artist, and seal. From here the artist has no power left."
    (with-read series-table series-id
      { 'artist := artist, 'artist-guard := ag, 'pack-token := pt, 'packs-total := n
      , 'card-ids := ids, 'locked := locked, 'sealed := sealed }
      (enforce locked "lock the series first")
      (enforce (not sealed) "already sealed")
      (let ((vault (vault-account series-id)))
        (map (lambda (t:string)
               (with-read pool (pool-key series-id t) { 'count := c }
                 ;; a vault row that was never credited reads as 0 (try only reads)
                 (enforce (= (dec c) (try 0.0 (ledger.get-balance t vault)))
                   (format "the vault holds the wrong number of {}" [t]))))
             ids))
      (with-capability (ARTIST series-id ag)
        (ledger.mint pt artist ag (dec n))
        (update series-table series-id { 'sealed: true })
        (emit-event (SERIES-SEALED series-id (vault-account series-id) n))))
    true)

  ;; --- opening ---------------------------------------------------------------------------
  (defun free-round:integer (series-id:string from:integer)
    @doc "The first round at or after FROM whose queue has room."
    (at 'r
      (fold (lambda (acc:object r:integer)
              (if (at 'found acc)
                acc
                (if (< (length (get-queue series-id r)) MAX-QUEUE)
                  { 'found: true, 'r: r }
                  acc)))
            { 'found: false, 'r: from }
            (enumerate from (+ from MAX-ROUND-SEARCH)))))

  (defun request-open:string (series-id:string opener:string)
    @doc "Burn one sealed pack held by OPENER (the ledger proves ownership) and \
         \queue an opening for the first beacon round at least MIN-MARGIN \
         \seconds away. Returns the request id."
    (with-read series-table series-id { 'sealed := sealed, 'pack-token := pt, 'origin-chain := oc }
      (enforce sealed "the series is not sealed")
      (enforce (= oc (at 'chain-id (chain-data))) "packs open on the series' origin chain")
      (let* ((v:module{beacon-verifier} (verifier))
             (opener-guard:guard (ledger.account-guard pt opener))
             (now (at 'block-time (chain-data)))
             (earliest (+ 1 (v::round-at (add-time now MIN-MARGIN))))
             (rnd (free-round series-id earliest))
             (rid:string (hash [series-id opener (tx-hash) rnd])))
        (enforce (<= (length (get-queue series-id rnd)) (- MAX-QUEUE 1)) "no round with room in range")
        ;; the opener's own signature authorizes the burn (ledger DEBIT)
        (ledger.burn pt opener 1.0)
        (insert requests rid { 'series-id: series-id, 'opener: opener, 'opener-guard: opener-guard, 'round: rnd, 'revealed: false })
        (write queues (queue-key series-id rnd) { 'ids: (+ (get-queue series-id rnd) [rid]) })
        (emit-event (OPEN-REQUESTED rid series-id opener rnd))
        rid)))

  ;; --- the draw --------------------------------------------------------------------------
  (defun slot-cards:[object{pool-card}] (series-id:string s:object{slot} ids:[string])
    (filter (lambda (c:object{pool-card}) (and (contains (at 'tier c) (at 'tiers s)) (> (at 'left c) 0)))
      (map (lambda (t:string) (read pool (pool-key series-id t))) ids)))

  (defun pick-card:string (cards:[object{pool-card}] r:integer)
    @doc "Weighted pick WITHOUT replacement: walk the cards' remaining counts and \
         \return the one whose cumulative range contains R (0 <= R < total left)."
    (at 'chosen
      (fold (lambda (acc:object c:object{pool-card})
              (if (!= "" (at 'chosen acc))
                acc
                (let ((upto (+ (at 'cum acc) (at 'left c))))
                  (if (< r upto) { 'cum: upto, 'chosen: (at 'token-id c) } { 'cum: upto, 'chosen: "" }))))
            { 'cum: 0, 'chosen: "" }
            cards)))

  (defun draw-one:bool (series-id:string s:object{slot} rid:string opener:string og:guard seed:integer k:integer)
    (with-read series-table series-id { 'card-ids := ids }
      (let* ((cards (slot-cards series-id s ids))
             (total (fold (+) 0 (map (at 'left) cards)))
             (_ (enforce (> total 0) "slot exhausted"))
             (r (mod (str-to-int 64 (hash (format "{}|{}|{}|{}" [seed rid (at 'name s) k]))) total))
             (chosen (pick-card cards r)))
        (with-read pool (pool-key series-id chosen) { 'left := left }
          (update pool (pool-key series-id chosen) { 'left: (- left 1) }))
        (install-capability (ledger.TRANSFER chosen (vault-account series-id) opener 1.0))
        (ledger.transfer-create chosen (vault-account series-id) opener og 1.0)
        (emit-event (CARD-REVEALED rid chosen))
        true)))

  (defun draw-request:bool (series-id:string rid:string seed:integer rnd:integer)
    (with-read requests rid { 'opener := opener, 'opener-guard := og, 'revealed := revealed }
      (enforce (not revealed) "request already revealed")
      (with-read series-table series-id { 'slots := slots, 'opened := opened }
        (map (lambda (s:object{slot})
               (map (lambda (k:integer) (draw-one series-id s rid opener og seed k))
                    (enumerate 1 (at 'picks s))))
             slots)
        (update series-table series-id { 'opened: (+ opened 1) }))
      (update requests rid { 'revealed: true })
      (emit-event (OPENED rid series-id rnd)))
    true)

  (defun reveal:bool (series-id:string rnd:integer sig-hex:string)
    @doc "ANYONE may submit the beacon for RND. The verifier proves it; every \
         \request queued for RND is drawn in request order from a seed bound to \
         \the series and the round; the cards leave the vault. No beacon, no \
         \draw; one beacon, one draw."
    (let* ((v:module{beacon-verifier} (verifier))
           (ids (get-queue series-id rnd)))
      (enforce (> (length ids) 0) "nothing queued for this round")
      (let ((seed:integer (v::verified-seed (format "pack|{}|{}" [series-id rnd]) rnd sig-hex)))
        (with-capability (VAULT series-id)
          (map (lambda (rid:string) (draw-request series-id rid seed rnd)) ids))
        (write queues (queue-key series-id rnd) { 'ids: [] })))
    true)
)
