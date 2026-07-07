;; nft-single — a self-sovereign, frozen-at-mint NFT (ADR-019 spike reference template)
;;
;; ONE NFT = ONE MODULE, deployed in the ARTIST's namespace. The artist governs
;; deployment, but the module FREEZES ITSELF at mint: GOVERNANCE refuses every
;; upgrade once minted, so royalty/creator/supply are immutable even to the
;; artist. The NFT owns its own escrow and pays its own royalty on every sale,
;; regardless of which marketplace (in which namespace) triggers it.
;;
;; The namespace this loads into is supplied at deploy (read-msg 'ns); the admin
;; keyset name likewise. In the spike these are the artist's test namespace.

(namespace (read-msg 'ns))

(module nft-single GOVERNANCE
  @doc "A single self-custody NFT: immutable creator royalty, one active \
       \marketplace consignment, own escrow, pays its own royalty. Implements \
       \the ADR-019 nft-asset standard. Frozen at mint."

  (implements std.nft-asset)

  ;; --- governance: freezes at mint ------------------------------------------
  (defconst ADMIN-KS:string (read-msg 'admin-ks)
    @doc "The artist's admin keyset name (namespace-qualified). Governs the \
         \module BEFORE mint (deploy/create-table); after mint the frozen check \
         \blocks all upgrades regardless of this keyset.")

  (defcap GOVERNANCE ()
    @doc "Upgrade gate. Once minted (frozen), NO upgrade is permitted — the \
         \artist cannot change royalty/creator/terms after mint. Before mint \
         \(create-table only), the artist's keyset governs."
    (enforce (not (minted)) "NFT is frozen — terms are immutable after mint")
    (enforce-keyset ADMIN-KS))

  ;; --- constants ------------------------------------------------------------
  (defconst BPS-DENOM:integer 10000)
  (defconst MAX-ROYALTY-BPS:integer 5000 @doc "50% royalty cap.")
  (defconst MAX-FEE-BPS:integer 1000
    @doc "The MOST any marketplace may charge on a sale of THIS NFT: 10%. The \
         \asset caps the fee so a hostile marketplace cannot set an absurd rate.")

  ;; --- escrow (capability-guarded principal owned by THIS module) -----------
  (defcap SPEND ()
    @doc "Internal escrow-spend token. Weak body by design: acquired only inside \
         \`buy`'s settlement, which pays out exactly what was paid in (asserted)."
    true)
  (defun escrow-guard-pred:bool () (require-capability (SPEND)))
  (defun create-escrow-guard:guard () (create-user-guard (escrow-guard-pred)))
  (defconst ESCROW:string (create-principal (create-escrow-guard))
    "This NFT's escrow principal account.")

  ;; --- state (a single self row) --------------------------------------------
  (defschema nft
    @doc "The one and only token this module represents. `mkt-guard` is the \
         \active consignment (which marketplace may sell); `listed` gates it."
    minted:bool
    creator:string          ;; immutable royalty payee
    creator-guard:guard
    royalty-bps:integer     ;; immutable
    owner:string
    owner-guard:guard
    uri:string
    mkt-guard:guard         ;; the consigned marketplace's guard (sentinel when unlisted)
    price:decimal
    listed:bool)
  (deftable state:{nft})
  (defconst SELF:string "self")

  ;; --- events ---------------------------------------------------------------
  (defcap MINTED:bool (creator:string owner:string royalty-bps:integer) @event true)
  (defcap LISTED:bool (price:decimal) @event true)
  (defcap DELISTED:bool () @event true)
  (defcap SOLD:bool (seller:string buyer:string price:decimal royalty:decimal fee:decimal) @event true)
  (defcap TRANSFERRED:bool (from:string to:string) @event true)

  ;; --- owner authorization --------------------------------------------------
  (defcap OWNER ()
    @doc "Authenticate the current owner. Bind the guard BEFORE enforce-guard \
         \(arg position is node-safe; a table read inside an enforce CONDITION \
         \is not)."
    (enforce-guard (at 'owner-guard (read state SELF))))

  ;; --- mint (one-time; freezes) ---------------------------------------------
  (defun minted:bool ()
    (with-default-read state SELF { 'minted: false } { 'minted := m } m))

  (defun mint:string
    ( owner:string owner-guard:guard
      creator:string creator-guard:guard
      royalty-bps:integer uri:string )
    @doc "Create THE token for this module. One-time (insert fails if minted). \
         \Sets frozen (minted=true) so no upgrade can ever change the terms. \
         \OWNER and CREATOR MUST be principals; ROYALTY-BPS in [0, 50%]."
    (enforce (validate-principal owner-guard owner) "owner must be a principal")
    (enforce (validate-principal creator-guard creator) "creator must be a principal")
    (enforce (and (>= royalty-bps 0) (<= royalty-bps MAX-ROYALTY-BPS))
      (format "royalty-bps must be in [0, {}]" [MAX-ROYALTY-BPS]))
    (insert state SELF
      { 'minted: true
      , 'creator: creator, 'creator-guard: creator-guard, 'royalty-bps: royalty-bps
      , 'owner: owner, 'owner-guard: owner-guard, 'uri: uri
      , 'mkt-guard: owner-guard, 'price: 0.0, 'listed: false })
    (emit-event (MINTED creator owner royalty-bps))
    "minted")

  ;; --- views (nft-asset) ----------------------------------------------------
  (defun get-owner:string () (at 'owner (read state SELF)))
  (defun get-creator:string () (at 'creator (read state SELF)))
  (defun get-royalty-bps:integer () (at 'royalty-bps (read state SELF)))
  (defun get-price:decimal () (at 'price (read state SELF)))
  (defun is-listed:bool ()
    (with-default-read state SELF { 'listed: false } { 'listed := l } l))
  (defun is-frozen:bool () (minted))

  ;; --- free transfer (nft-asset) --------------------------------------------
  (defun transfer:string (receiver:string receiver-guard:guard)
    @doc "Gift/move with no payment. Rejected while consigned. Owner-authorized."
    (enforce (validate-principal receiver-guard receiver) "receiver must be a principal")
    (with-read state SELF { 'listed := listed }
      (enforce (not listed) "delist before transferring"))
    (with-capability (OWNER)
      (let ((from (at 'owner (read state SELF))))
        (update state SELF { 'owner: receiver, 'owner-guard: receiver-guard })
        (emit-event (TRANSFERRED from receiver))
        "transferred")))

  ;; --- consignment (nft-asset) ----------------------------------------------
  (defun list-for-sale:string (mkt-guard:guard price:decimal)
    @doc "Consign to ONE marketplace (record its guard + price). Supersedes any \
         \prior consignment. Owner-authorized. Rejects a dust price whose royalty \
         \floors to zero."
    (enforce (> price 0.0) "price must be positive")
    (with-read state SELF { 'royalty-bps := rbps }
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
    @doc "Revoke the active consignment. Owner-authorized."
    (with-capability (OWNER)
      (update state SELF { 'listed: false })
      (emit-event (DELISTED))
      "delisted"))

  ;; --- the sale (nft-asset) -------------------------------------------------
  (defun buy:string
    ( buyer:string buyer-guard:guard
      fee-account:string fee-guard:guard fee-bps:integer )
    @doc "Settle a consigned sale. Enforces the recorded consignment guard (only \
         \the consigned marketplace satisfies it). Pays royalty (state) + fee \
         \(capped) + seller; asserts escrow conservation."
    (enforce (validate-principal buyer-guard buyer) "buyer must be a principal")
    (enforce (validate-principal fee-guard fee-account) "fee account must be a principal")
    (enforce (and (>= fee-bps 0) (<= fee-bps MAX-FEE-BPS))
      (format "fee-bps must be in [0, {}] (asset-capped)" [MAX-FEE-BPS]))
    (with-read state SELF
      { 'mkt-guard := mkt-guard, 'price := price, 'listed := listed
      , 'creator := creator, 'creator-guard := creator-guard
      , 'owner := seller, 'owner-guard := seller-guard, 'royalty-bps := rbps }
      (enforce listed "not listed")
      ;; the load-bearing authorization: only the consigned marketplace's guard.
      ;; Bound above; enforced here in ARG position (node-safe).
      (enforce-guard mkt-guard)
      (let* ((prec (coin.precision))
             (royalty (floor (/ (* price (dec rbps)) (dec BPS-DENOM)) prec))
             (fee (if (> fee-bps 0) (floor (/ (* price (dec fee-bps)) (dec BPS-DENOM)) prec) 0.0))
             (proceeds (- price (+ royalty fee))))
        (enforce (>= proceeds 0.0) "royalty + fee exceed price")
        ;; INTERACTION 1: buyer funds the escrow with exactly `price`
        (coin.transfer-create buyer ESCROW (create-escrow-guard) price)
        (let ((funded (coin.get-balance ESCROW)))
          ;; EFFECTS before payout (checks-effects-interactions)
          (update state SELF { 'owner: buyer, 'owner-guard: buyer-guard, 'listed: false })
          ;; INTERACTION 2: merged payouts (same-payee legs coalesce)
          (let* ((raw [ { 'account: creator, 'guard: creator-guard, 'amount: royalty }
                      , { 'account: fee-account, 'guard: fee-guard, 'amount: fee }
                      , { 'account: seller, 'guard: seller-guard, 'amount: proceeds } ])
                 (payouts (fold (merge-payout) [] raw)))
            (with-capability (SPEND) (map (pay-from-escrow) payouts)))
          ;; CONSERVATION: exactly `price` left the escrow (dust-robust)
          (let ((final (coin.get-balance ESCROW)))
            (enforce (= final (- funded price)) "escrow not fully settled"))
          (emit-event (SOLD seller buyer price royalty fee))
          "sold"))))

  ;; --- payout helpers (from the audited Gallery pattern) --------------------
  (defun merge-payout:[object] (acc:[object] p:object)
    @doc "Merge a payout into the accumulator, summing amounts for a payee that \
         \already appears (creator==seller, creator==fee-account, …) so payees \
         \cannot collide on the managed-transfer install. Drops zero amounts."
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
    @doc "Pay one merged payout from the escrow. Requires SPEND in scope."
    (require-capability (SPEND))
    (install-capability (coin.TRANSFER ESCROW (at 'account p) (at 'amount p)))
    (coin.transfer-create ESCROW (at 'account p) (at 'guard p) (at 'amount p)))
)
