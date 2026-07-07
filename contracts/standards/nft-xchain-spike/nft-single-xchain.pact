;; nft-single-xchain — a self-sovereign, frozen-at-mint NFT that can MOVE ACROSS
;; CHAINS without pre-deploying on every chain (spike).
;;
;; A Pact module cannot ship its own code cross-chain, and the defpact
;; continuation transport requires the SAME module to already exist on the target
;; chain. This module uses the OTHER cross-chain mechanism — `verify-spv "TXOUT"`
;; — so the NFT can be DEPLOYED ON DEMAND at a destination and mint itself from a
;; verified proof of its departure at the source. The artist/owner pays deploy
;; gas only on chains the NFT actually visits.
;;
;; RESIDENCY: `present` is true on exactly ONE chain and false everywhere the NFT
;; has left. A move is depart (source: present->false, return the payload) then
;; claim (target: verify-spv the payload, insert present->true). `present=true`
;; on the target is reachable ONLY by consuming proof of `present=false` at the
;; source, so the NFT can never be live on two chains — the invariant is
;; maintained by the transition, not audited after the fact.
;;
;; Same-chain behavior (consignment, sale, royalty) is identical to nft-single;
;; every operation additionally requires `present` on this chain.

(namespace (read-msg 'ns))

(module nft-single-xchain GOVERNANCE
  @doc "A self-custody NFT with an immutable creator royalty, one active \
       \marketplace consignment, its own escrow, and cross-chain relocation via \
       \verify-spv. Frozen at mint."

  (implements std.nft-asset)

  ;; --- governance: freezes at mint ------------------------------------------
  (defconst ADMIN-KS:string (read-msg 'admin-ks))
  (defcap GOVERNANCE ()
    (enforce (not (minted)) "NFT is frozen — terms are immutable after mint")
    (enforce-keyset ADMIN-KS))

  ;; --- constants ------------------------------------------------------------
  (defconst BPS-DENOM:integer 10000)
  (defconst MAX-ROYALTY-BPS:integer 5000)
  (defconst MAX-FEE-BPS:integer 1000)
  ;; the immutable origin id: the token's identity, stable across every chain it
  ;; visits (set at mint on the origin chain, carried verbatim in the payload).
  (defconst SELF:string "self")

  ;; --- escrow ---------------------------------------------------------------
  (defcap SPEND ()
    @doc "Internal escrow-spend token. Weak body by design: acquired only inside \
         \`buy`'s settlement, which pays out exactly what was paid in (asserted)."
    true)
  (defun escrow-guard-pred:bool () (require-capability (SPEND)))
  (defun create-escrow-guard:guard () (create-user-guard (escrow-guard-pred)))
  (defconst ESCROW:string (create-principal (create-escrow-guard)))

  ;; --- state ----------------------------------------------------------------
  (defschema nft
    minted:bool
    present:bool            ;; RESIDENCY: is the NFT live on THIS chain?
    origin-id:string        ;; immutable identity across chains
    creator:string
    creator-guard:guard
    royalty-bps:integer
    owner:string
    owner-guard:guard
    uri:string
    mkt-guard:guard
    price:decimal
    listed:bool)
  (deftable state:{nft})

  ;; the object shape a depart RETURNS and a claim VERIFIES (the TXOUT payload).
  (defschema move-payload
    origin-id:string
    owner:string
    owner-guard:guard
    creator:string
    creator-guard:guard
    royalty-bps:integer
    uri:string
    source-chain:string
    target-chain:string)

  ;; --- events ---------------------------------------------------------------
  (defcap MINTED:bool (creator:string owner:string royalty-bps:integer) @event true)
  (defcap LISTED:bool (price:decimal) @event true)
  (defcap DELISTED:bool () @event true)
  (defcap SOLD:bool (seller:string buyer:string price:decimal royalty:decimal fee:decimal) @event true)
  (defcap TRANSFERRED:bool (from:string to:string) @event true)
  (defcap DEPARTED:bool (origin-id:string owner:string target-chain:string) @event true)
  (defcap CLAIMED:bool (origin-id:string owner:string source-chain:string) @event true)

  ;; --- helpers --------------------------------------------------------------
  (defun minted:bool ()
    (with-default-read state SELF { 'minted: false } { 'minted := m } m))
  (defun is-present:bool ()
    (with-default-read state SELF { 'present: false } { 'present := p } p))
  (defun this-chain:string () (at 'chain-id (chain-data)))

  (defcap OWNER ()
    (enforce-guard (at 'owner-guard (read state SELF))))

  ;; --- mint (origin chain; freezes; present=true) ---------------------------
  (defun mint:string
    ( owner:string owner-guard:guard
      creator:string creator-guard:guard
      royalty-bps:integer uri:string )
    @doc "Create THE token on its ORIGIN chain (present=true). One-time. Sets \
         \frozen. origin-id = SELF (this module's identity). Principals required."
    (enforce (validate-principal owner-guard owner) "owner must be a principal")
    (enforce (validate-principal creator-guard creator) "creator must be a principal")
    (enforce (and (>= royalty-bps 0) (<= royalty-bps MAX-ROYALTY-BPS))
      (format "royalty-bps must be in [0, {}]" [MAX-ROYALTY-BPS]))
    (insert state SELF
      { 'minted: true, 'present: true, 'origin-id: SELF
      , 'creator: creator, 'creator-guard: creator-guard, 'royalty-bps: royalty-bps
      , 'owner: owner, 'owner-guard: owner-guard, 'uri: uri
      , 'mkt-guard: owner-guard, 'price: 0.0, 'listed: false })
    (emit-event (MINTED creator owner royalty-bps))
    "minted")

  ;; --- views (nft-asset) ----------------------------------------------------
  (defun get-owner:string ()
    (with-read state SELF { 'owner := o, 'present := p }
      (enforce p "token is not on this chain") o))
  (defun get-creator:string () (at 'creator (read state SELF)))
  (defun get-royalty-bps:integer () (at 'royalty-bps (read state SELF)))
  (defun get-price:decimal () (at 'price (read state SELF)))
  (defun is-listed:bool ()
    (with-default-read state SELF { 'listed: false } { 'listed := l } l))
  (defun is-frozen:bool () (minted))

  ;; --- free transfer (nft-asset) --------------------------------------------
  (defun transfer:string (receiver:string receiver-guard:guard)
    (enforce (validate-principal receiver-guard receiver) "receiver must be a principal")
    (with-read state SELF { 'listed := listed, 'present := present }
      (enforce present "token is not on this chain")
      (enforce (not listed) "delist before transferring"))
    (with-capability (OWNER)
      (let ((from (at 'owner (read state SELF))))
        (update state SELF { 'owner: receiver, 'owner-guard: receiver-guard })
        (emit-event (TRANSFERRED from receiver))
        "transferred")))

  ;; --- consignment (nft-asset) ----------------------------------------------
  (defun list-for-sale:string (mkt-guard:guard price:decimal)
    (enforce (> price 0.0) "price must be positive")
    (with-read state SELF { 'royalty-bps := rbps, 'present := present }
      (enforce present "token is not on this chain")
      (if (> rbps 0)
        (let ((prec (coin.precision)))
          (enforce (> (floor (/ (* price (dec rbps)) (dec BPS-DENOM)) prec) 0.0)
            "price too low: royalty rounds to zero"))
        true))
    (with-capability (OWNER)
      (update state SELF { 'mkt-guard: mkt-guard, 'price: price, 'listed: true })
      (emit-event (LISTED price))
      "listed"))

  (defun delist:string ()
    (with-read state SELF { 'present := present }
      (enforce present "token is not on this chain"))
    (with-capability (OWNER)
      (update state SELF { 'listed: false })
      (emit-event (DELISTED))
      "delisted"))

  ;; --- the sale (nft-asset) -------------------------------------------------
  (defun buy:string
    ( buyer:string buyer-guard:guard
      fee-account:string fee-guard:guard fee-bps:integer )
    (enforce (validate-principal buyer-guard buyer) "buyer must be a principal")
    (enforce (validate-principal fee-guard fee-account) "fee account must be a principal")
    (enforce (and (>= fee-bps 0) (<= fee-bps MAX-FEE-BPS))
      (format "fee-bps must be in [0, {}] (asset-capped)" [MAX-FEE-BPS]))
    (with-read state SELF
      { 'mkt-guard := mkt-guard, 'price := price, 'listed := listed, 'present := present
      , 'creator := creator, 'creator-guard := creator-guard
      , 'owner := seller, 'owner-guard := seller-guard, 'royalty-bps := rbps }
      (enforce present "token is not on this chain")
      (enforce listed "not listed")
      (enforce-guard mkt-guard)
      (let* ((prec (coin.precision))
             (royalty (floor (/ (* price (dec rbps)) (dec BPS-DENOM)) prec))
             (fee (if (> fee-bps 0) (floor (/ (* price (dec fee-bps)) (dec BPS-DENOM)) prec) 0.0))
             (proceeds (- price (+ royalty fee))))
        (enforce (>= proceeds 0.0) "royalty + fee exceed price")
        (coin.transfer-create buyer ESCROW (create-escrow-guard) price)
        (let ((funded (coin.get-balance ESCROW)))
          (update state SELF { 'owner: buyer, 'owner-guard: buyer-guard, 'listed: false })
          (let* ((raw [ { 'account: creator, 'guard: creator-guard, 'amount: royalty }
                      , { 'account: fee-account, 'guard: fee-guard, 'amount: fee }
                      , { 'account: seller, 'guard: seller-guard, 'amount: proceeds } ])
                 (payouts (fold (merge-payout) [] raw)))
            (with-capability (SPEND) (map (pay-from-escrow) payouts)))
          (let ((final (coin.get-balance ESCROW)))
            (enforce (= final (- funded price)) "escrow not fully settled"))
          (emit-event (SOLD seller buyer price royalty fee))
          "sold"))))

  ;; --- CROSS-CHAIN: depart (source) then claim (target) ---------------------
  (defun depart:object{move-payload} (target-chain:string)
    @doc "Leave THIS chain for TARGET-CHAIN. Owner-authorized; the token must be \
         \present here and NOT consigned. Sets present=false (tombstone) and \
         \RETURNS the move payload (this tx's object result — the TXOUT the \
         \target chain will verify). A sale-only relocation cannot change the \
         \owner (the payload carries the current owner); ownership only changes \
         \via `buy`, so a move is never a royalty bypass. The payload binds \
         \TARGET-CHAIN, so the resulting proof can be claimed only there."
    (with-read state SELF
      { 'present := present, 'listed := listed, 'origin-id := oid
      , 'owner := owner, 'owner-guard := owner-guard
      , 'creator := creator, 'creator-guard := creator-guard
      , 'royalty-bps := rbps, 'uri := uri }
      (enforce present "token is not on this chain")
      (enforce (not listed) "delist before moving")
      (enforce (!= target-chain "") "empty target-chain")
      (enforce (!= (this-chain) target-chain) "cannot move to the same chain")
      (enforce (contains target-chain coin.VALID_CHAIN_IDS)
        "target chain is not a valid chainweb chain id")
      (with-capability (OWNER)
        (update state SELF { 'present: false, 'listed: false })
        (emit-event (DEPARTED oid owner target-chain))
        { 'origin-id: oid
        , 'owner: owner, 'owner-guard: owner-guard
        , 'creator: creator, 'creator-guard: creator-guard
        , 'royalty-bps: rbps, 'uri: uri
        , 'source-chain: (this-chain), 'target-chain: target-chain })))

  (defun claim:string (proof:object)
    @doc "Arrive on THIS chain by verifying an SPV proof of a `depart` at the \
         \source. verify-spv returns the proven move-payload; the token is \
         \written present=true here with the SAME creator/royalty/owner. The \
         \proof binds TARGET-CHAIN — enforced to equal this chain, so a proof \
         \cannot be replayed onto a different chain. `insert` fails if this \
         \module already holds the token here (no double-claim on one chain)."
    (let ((p (verify-spv "TXOUT" proof)))
      (enforce (= (at 'target-chain p) (this-chain))
        "proof is not addressed to this chain (replay/misroute rejected)")
      (insert state SELF
        { 'minted: true, 'present: true, 'origin-id: (at 'origin-id p)
        , 'creator: (at 'creator p), 'creator-guard: (at 'creator-guard p)
        , 'royalty-bps: (at 'royalty-bps p)
        , 'owner: (at 'owner p), 'owner-guard: (at 'owner-guard p)
        , 'uri: (at 'uri p)
        , 'mkt-guard: (at 'owner-guard p), 'price: 0.0, 'listed: false })
      (emit-event (CLAIMED (at 'origin-id p) (at 'owner p) (at 'source-chain p)))
      "claimed"))

  ;; --- payout helpers -------------------------------------------------------
  (defun merge-payout:[object] (acc:[object] p:object)
    (if (<= (at 'amount p) 0.0)
      acc
      (let ((seen (contains (at 'account p) (map (at 'account) acc))))
        (if seen
          (map (lambda (x:object)
                 (if (= (at 'account x) (at 'account p))
                   (+ { 'amount: (+ (at 'amount x) (at 'amount p)) } x)
                   x))
               acc)
          (+ acc [p])))))

  (defun pay-from-escrow:string (p:object)
    (require-capability (SPEND))
    (install-capability (coin.TRANSFER ESCROW (at 'account p) (at 'amount p)))
    (coin.transfer-create ESCROW (at 'account p) (at 'guard p) (at 'amount p)))
)
