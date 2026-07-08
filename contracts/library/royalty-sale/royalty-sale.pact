(module royalty-sale GOV

  @doc "PCO library template: a self-contained NFT with a conservation-checked  \
  \royalty marketplace - the hardened answer to the settlement, economics, and  \
  \guard-default flaws documented in the Marmalade V2 analysis.                 \
  \                                                                              \
  \This module owns its NFT ledger AND its sale escrow end to end, so it can    \
  \PROVE the safe patterns rather than inherit a shared-escrow sweep:           \
  \                                                                              \
  \  1. FAIL CLOSED. Every royalty/economic input is required and validated at  \
  \     creation; nothing defaults to permissive. (fixes: guard fail-open)      \
  \  2. ONE SETTLEMENT, CONSERVATION-ASSERTED. buy pulls the price into a        \
  \     capability-guarded escrow, then a single routine pays creator + market  \
  \     + seller and asserts royalty + fee + proceeds == price AND that the     \
  \     escrow returns to its baseline. No policy/hook ever holds escrow spend   \
  \     authority. (fixes: shared-escrow sweep, policy-reaches-into-escrow)     \
  \  3. ECONOMICS ON-CHAIN. The royalty rate is fixed on the token at mint; the  \
  \     marketplace fee + account are fixed on the LISTING by the seller. buy    \
  \     reads them from state - never from the buyer's transaction - so a buyer  \
  \     cannot zero the fee. (fixes: caller-supplied marketplace fee)           \
  \  4. SALE-ONLY IS AN EXPLICIT OPT-IN. A token is minted `transferable` or     \
  \     not. A non-transferable token can move ONLY through buy (which always    \
  \     pays royalty) - enforceable royalties - but the creator CHOSE that, and  \
  \     it cannot be silently voided by policy composition. (fixes: blunt        \
  \     always-fail transfer lock)                                              \
  \  5. PRINCIPAL PAYEES. Every payout account (creator, seller, marketplace)    \
  \     is a k:/w:/r: principal, so a payout can never be bricked by a squatted  \
  \     vanity account, and same-account payouts (a primary sale: creator IS     \
  \     the seller) are merged so they cannot collide on the managed-transfer    \
  \     install. (fixes: fund-lock + duplicate-install classes)                 \
  \                                                                              \
  \Scope: instant fixed-price sales in any fungible-v2 currency. Auctions and    \
  \time-escrowed offers are a future extension.                                  \
  \                                                                              \
  \Deployment checklist (see README.md):                                         \
  \  1. Wrap in your namespace; replace the 'royalty-sale-gov' keyset.           \
  \  2. Deploy and create-table (tokens, listings).                             \
  \  3. Validate on devnet before mainnet."

  ;; Conforms to the Kadena NFT standard (contracts/standards/): the asset
  ;; surface (token, ownership, royalty, event vocabulary) and the fixed-price
  ;; market surface. No cross-chain (single-chain template) — nft-xchain-v1 is
  ;; not implemented. See contracts/standards/SPEC.md.
  (implements n_e82dd10f74b7e8c253553de95629fdfa35cf8379.nft-asset-v1)
  (implements n_e82dd10f74b7e8c253553de95629fdfa35cf8379.nft-market-v1)

  ;; -----------------------------
  ;; Governance (upgrade-only; no fund paths)
  ;; -----------------------------

  (defconst GOV_KEYSET:string "royalty-sale-gov"
    @doc "Governance keyset name. Replace with your deployed, namespace- \
         \qualified keyset (multi-sig recommended). Governance can upgrade the \
         \module and nothing else - no function under GOV touches tokens, \
         \listings, or the escrow.")

  (defcap GOV ()
    @doc "Module governance: upgrade only."
    (enforce-guard (keyset-ref-guard GOV_KEYSET)))

  ;; -----------------------------
  ;; Escrow (capability-guarded)
  ;; -----------------------------
  ;; A single escrow account holds the buyer's payment for the instant it takes
  ;; to settle. SPEND is acquired ONLY inside `buy`, after the payment has
  ;; arrived and the conservation split is computed. No other path acquires it.

  (defcap SPEND ()
    @doc "Internal escrow-spend token. Weak body by design: acquired only \
         \inside `buy`'s settlement, never externally, and the settlement pays \
         \out exactly what was paid in (asserted)."
    true)

  (defun escrow-guard-pred:bool () (require-capability (SPEND)))
  (defun create-escrow-guard:guard () (create-user-guard (escrow-guard-pred)))
  (defconst ESCROW:string (create-principal (create-escrow-guard))
    "Escrow principal account name.")

  ;; -----------------------------
  ;; Limits
  ;; -----------------------------

  (defconst BPS-DENOM:integer 10000)
  (defconst MAX-ROYALTY-BPS:integer 5000
    @doc "Sane cap on the royalty rate: 50%. A rate near 100% would leave the \
         \seller with nothing - almost always a mistake, so it is rejected.")
  (defconst MAX-FEE-BPS:integer 1000
    @doc "Sane cap on the marketplace fee: 10%.")
  (defconst MAX-ID-LEN:integer 128)

  ;; -----------------------------
  ;; Schemas & tables
  ;; -----------------------------

  (defschema token
    @doc "A 1-of-1 NFT. Royalty terms are immutable after mint."
    owner:string            ;; current owner (a principal account)
    owner-guard:guard       ;; authorizes owner operations AND receives sale proceeds
    creator:string          ;; royalty payee (a principal account)
    creator-guard:guard     ;; receives royalties (transfer-create target)
    royalty-bps:integer     ;; immutable royalty rate in basis points
    transferable:bool       ;; false = sale-only (royalty-enforced): free transfer rejected
    uri:string)

  (deftable tokens:{token})

  (defschema listing
    @doc "An active fixed-price listing. The marketplace fee is fixed HERE by \
         \the seller, not supplied by the buyer at purchase."
    seller:string
    price:decimal
    currency:module{fungible-v2}
    marketplace:string      ;; fee payee ("" when no fee)
    marketplace-guard:guard ;; fee payee guard (sentinel when no fee)
    marketplace-bps:integer ;; fee rate; 0 = no fee
    active:bool)

  (deftable listings:{listing})

  ;; -----------------------------
  ;; Guards & events
  ;; -----------------------------

  ;; Event vocabulary — signatures match nft-asset-v1 / nft-market-v1 so one
  ;; indexer reads this module and any other conforming marketplace uniformly.
  ;; MINTED carries the initial owner (asset standard S: ownership history is
  ;; fully event-derivable). LISTED's fee-bps is the platform/marketplace fee
  ;; rate (here the seller-named marketplace-bps); routing stays private.
  (defcap MINTED:bool (id:string owner:string creator:string royalty-bps:integer transferable:bool) @event true)
  (defcap LISTED:bool (id:string seller:string price:decimal fee-bps:integer) @event true)
  (defcap DELISTED:bool (id:string) @event true)
  (defcap SOLD:bool (id:string seller:string buyer:string price:decimal royalty:decimal fee:decimal) @event true)
  (defcap TRANSFERRED:bool (id:string from:string to:string) @event true)

  (defcap MINT-AUTH (owner-guard:guard)
    @doc "Scopes the minter's signature to the mint: they prove control of the \
         \owner guard being enrolled. A capability (not a bare enforce-guard) \
         \so the minter signs scoped, not unscoped."
    (enforce-guard owner-guard))

  (defcap OWNER (id:string)
    @doc "Authenticate the current owner of token ID. As a capability, the \
         \owner scopes their signature to (royalty-sale.OWNER \"id\")."
    ; NODE-SAFETY: bind the guard read before enforce-guard (arg position is
    ; node-safe; a table read inside an enforce CONDITION is not).
    (enforce-guard (at 'owner-guard (read tokens id))))

  ;; -----------------------------
  ;; Validation helpers
  ;; -----------------------------

  (defun enforce-valid-id (id:string)
    (enforce (!= id "") "id required")
    (enforce (<= (length id) MAX-ID-LEN) "id too long")
    (enforce (is-charset 0 id) "id must be ASCII"))

  (defun enforce-unit:bool (currency:module{fungible-v2} amount:decimal)
    ; bind precision before the enforce: for an arbitrary fungible-v2, precision
    ; may read the currency's own tables (node-safe only when bound first)
    (let ((prec (currency::precision)))
      (enforce (= amount (floor amount prec)) "amount violates currency precision")))

  ;; -----------------------------
  ;; Mint
  ;; -----------------------------

  (defun mint:string
    ( id:string
      owner:string owner-guard:guard
      creator:string creator-guard:guard
      royalty-bps:integer
      transferable:bool
      uri:string )
    @doc "Mint a 1-of-1 NFT. OWNER receives it; CREATOR receives royalties on \
         \every future sale. Both must be PRINCIPAL accounts (k:/w:/r:) so a \
         \payout can never be bricked by a squatted account. ROYALTY-BPS is \
         \immutable. TRANSFERABLE=false makes the token sale-only (royalty is \
         \then unconditionally enforced - the creator's explicit choice). \
         \The minter must satisfy the OWNER guard (proves control at mint)."
    (enforce-valid-id id)
    ; fail closed: payout accounts must be their guard's principal
    (enforce (validate-principal owner-guard owner)
      "owner must be a principal account (k:/w:/r:)")
    (enforce (validate-principal creator-guard creator)
      "creator must be a principal account (k:/w:/r:)")
    (enforce (and (>= royalty-bps 0) (<= royalty-bps MAX-ROYALTY-BPS))
      (format "royalty-bps must be in [0, {}]" [MAX-ROYALTY-BPS]))
    ; scoped: the minter proves control of the owner guard (not a bare,
    ; unscoped enforce-guard)
    (with-capability (MINT-AUTH owner-guard)
      (insert tokens id
        { 'owner: owner, 'owner-guard: owner-guard
        , 'creator: creator, 'creator-guard: creator-guard
        , 'royalty-bps: royalty-bps
        , 'transferable: transferable
        , 'uri: uri })
      (emit-event (MINTED id owner creator royalty-bps transferable))
      id))

  ;; -----------------------------
  ;; Free transfer (only for transferable tokens)
  ;; -----------------------------

  (defun transfer:string (id:string receiver:string receiver-guard:guard)
    @doc "Gift/move a token with NO payment. Allowed ONLY for a token minted \
         \transferable; a sale-only token rejects this (its royalty is \
         \enforced because buy is the only way to move it). RECEIVER must be a \
         \principal account. The owner signs scoped to OWNER; the token must \
         \not be actively listed."
    (with-read tokens id { 'transferable := transferable }
      (enforce transferable "token is sale-only; use buy"))
    (enforce (validate-principal receiver-guard receiver)
      "receiver must be a principal account (k:/w:/r:)")
    (let ((listed (is-listed id)))
      (enforce (not listed) "delist before transferring"))
    (with-capability (OWNER id)
      ; capture the sender before the update so the event records real provenance
      (let ((from (at 'owner (read tokens id))))
        (update tokens id { 'owner: receiver, 'owner-guard: receiver-guard })
        (emit-event (TRANSFERRED id from receiver))
        id)))

  ;; -----------------------------
  ;; Listing
  ;; -----------------------------

  (defconst NO-MARKETPLACE-GUARD:guard
    (create-capability-guard (GOV))
    @doc "Sentinel guard stored on a fee-free listing's unused marketplace \
         \columns. Never enforced (marketplace-bps 0 => the fee leg is dropped \
         \by merge-payout), so it can be an inert placeholder.")

  (defun list-token:string (id:string price:decimal currency:module{fungible-v2})
    @doc "nft-market-v1: list an owned token at a fixed PRICE in CURRENCY with \
         \NO marketplace fee. For a seller-named marketplace fee, use \
         \list-token-with-fee (a royalty-sale extension beyond the standard \
         \surface). Owner-authenticated. Emits LISTED."
    (list-token-with-fee id price currency "" NO-MARKETPLACE-GUARD 0))

  (defun list-token-with-fee:string
    ( id:string
      price:decimal
      currency:module{fungible-v2}
      marketplace:string marketplace-guard:guard marketplace-bps:integer )
    @doc "royalty-sale extension (beyond nft-market-v1): list at a fixed PRICE \
         \in CURRENCY with a seller-named marketplace fee. The fee rate and \
         \payee are fixed HERE, by the seller - buy reads them from state, so a \
         \buyer cannot zero the fee. MARKETPLACE-BPS 0 means no fee (pass \"\" / \
         \a sentinel guard). A non-zero fee requires a principal marketplace \
         \account. Owner-authenticated."
    (enforce (> price 0.0) "price must be positive")
    (enforce-unit currency price)
    (enforce (and (>= marketplace-bps 0) (<= marketplace-bps MAX-FEE-BPS))
      (format "marketplace-bps must be in [0, {}]" [MAX-FEE-BPS]))
    ; standard S2: a royalty-bearing token must not be listable at a price whose
    ; floored royalty is zero (a dust price would otherwise be a royalty-free
    ; ownership change through buy). Bind royalty-bps + precision first, then
    ; enforce (node-safe ordering — no table read inside the enforce condition).
    (with-read tokens id { 'royalty-bps := royalty-bps }
      (if (> royalty-bps 0)
        (let ((prec (currency::precision)))
          (enforce (> (floor (/ (* price (dec royalty-bps)) (dec BPS-DENOM)) prec) 0.0)
            "price too low: royalty rounds to zero"))
        true))
    ; fail closed: if there is a fee, its payee must be a real principal account
    (if (> marketplace-bps 0)
      (enforce (validate-principal marketplace-guard marketplace)
        "marketplace must be a principal account when a fee is charged")
      true)
    (with-capability (OWNER id)
      (write listings id
        { 'seller: (at 'owner (read tokens id))
        , 'price: price
        , 'currency: currency
        , 'marketplace: marketplace
        , 'marketplace-guard: marketplace-guard
        , 'marketplace-bps: marketplace-bps
        , 'active: true })
      (emit-event (LISTED id (at 'owner (read tokens id)) price marketplace-bps))
      id))

  (defun delist:string (id:string)
    @doc "Cancel an active listing. Owner-authenticated."
    (with-capability (OWNER id)
      (with-read listings id { 'active := active }
        (enforce active "not listed"))
      (update listings id { 'active: false })
      (emit-event (DELISTED id))
      id))

  ;; -----------------------------
  ;; Buy — the single, conservation-asserted settlement
  ;; -----------------------------

  (defun merge-payout:[object] (acc:[object] p:object)
    @doc "Fold helper: merge a payout into the accumulator, summing amounts for \
         \a payee that already appears (so a primary sale where creator == \
         \seller becomes ONE payout and cannot collide on the managed-transfer \
         \install). Drops zero amounts."
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

  (defun pay-from-escrow:string (currency:module{fungible-v2} p:object)
    @doc "Pay one merged payout from the escrow. Requires SPEND in scope."
    (require-capability (SPEND))
    (let ((account:string (at 'account p))
          (amount:decimal (at 'amount p)))
      (install-capability (currency::TRANSFER ESCROW account amount))
      (currency::transfer-create ESCROW account (at 'guard p) amount)))

  (defun buy:string (id:string buyer:string buyer-guard:guard)
    @doc "Purchase a listed token at its fixed price. The BUYER signs the \
         \currency transfer of the full price into the escrow; anyone can then \
         \trigger settlement. Settlement pays creator (royalty) + marketplace \
         \(fee) + seller (remainder) and ASSERTS royalty + fee + proceeds == \
         \price and that the escrow returns to its baseline - conservation is \
         \proven, not assumed. BUYER must be a principal account (becomes the \
         \new owner and a future seller)."
    (enforce (validate-principal buyer-guard buyer)
      "buyer must be a principal account (k:/w:/r:)")
    (with-read listings id
      { 'seller := seller, 'price := price, 'currency := currency:module{fungible-v2}
      , 'marketplace := marketplace, 'marketplace-guard := mk-guard
      , 'marketplace-bps := mk-bps, 'active := active }
      (enforce active "token is not listed for sale")
      (with-read tokens id
        { 'creator := creator, 'creator-guard := creator-guard
        , 'owner-guard := seller-guard, 'royalty-bps := royalty-bps }
        (let* ((prec (currency::precision))
               (royalty (floor (/ (* price (dec royalty-bps)) (dec BPS-DENOM)) prec))
               (fee (if (> mk-bps 0)
                      (floor (/ (* price (dec mk-bps)) (dec BPS-DENOM)) prec)
                      0.0))
               (proceeds (- price (+ royalty fee))))
          (enforce (>= proceeds 0.0) "royalty + fee exceed price")
          ; INTERACTION 1: pull the full price into the escrow. The buyer signs
          ; their own coin.TRANSFER, so they authorize exactly `price` and no
          ; more. After this the escrow account exists, so its balance can be
          ; read in a plain `let` - NEVER inside a `try` or an enforce condition
          ; (both are read-only contexts on the KDA-CE node; a `try` around a
          ; table read is the same REPL-invisible trap this template avoids).
          (currency::transfer-create buyer ESCROW (create-escrow-guard) price)
          (let ((funded-bal (currency::get-balance ESCROW)))
            ; EFFECTS before further INTERACTIONS (checks-effects-interactions):
            ; close the listing and flip ownership BEFORE paying out, so a
            ; re-entrant buy on this listing finds it inactive.
            (update tokens id { 'owner: buyer, 'owner-guard: buyer-guard })
            (update listings id { 'active: false })
            ; INTERACTION 2: pay out. Same-account payees are merged into ONE
            ; payout (a primary sale where creator == seller) so they cannot
            ; collide on coin's managed-transfer install; zero amounts dropped.
            (let* ((raw [ { 'account: creator, 'guard: creator-guard, 'amount: royalty }
                        , { 'account: marketplace, 'guard: mk-guard, 'amount: fee }
                        , { 'account: seller, 'guard: seller-guard, 'amount: proceeds } ])
                   (payouts (fold (merge-payout) [] raw)))
              (with-capability (SPEND)
                (map (pay-from-escrow currency) payouts)))
            ; CONSERVATION (the real proof): exactly `price` must have left the
            ; escrow, so it returns to its pre-sale balance. This holds even if
            ; the shared escrow carried donated dust: funded = baseline + price,
            ; final must equal funded - price = baseline. Read is a plain let.
            (let ((final-bal (currency::get-balance ESCROW)))
              (enforce (= final-bal (- funded-bal price)) "escrow not fully settled"))
            (emit-event (SOLD id seller buyer price royalty fee))
            id)))))

  ;; -----------------------------
  ;; Views
  ;; -----------------------------

  ;; nft-asset-v1.token is exactly this module's 7 token columns, so get-token
  ;; returns the interface schema directly.
  (defun get-token:object{n_e82dd10f74b7e8c253553de95629fdfa35cf8379.nft-asset-v1.token} (id:string) (read tokens id))

  ;; nft-market-v1.listing is the currency-agnostic 5-field public projection;
  ;; the seller-named marketplace payee/guard stay private to this module.
  ;; fee-bps is the marketplace rate (0 for a standard fee-free listing).
  (defun get-listing:object{n_e82dd10f74b7e8c253553de95629fdfa35cf8379.nft-market-v1.listing} (id:string)
    (with-read listings id
      { 'seller := seller, 'price := price, 'currency := currency:module{fungible-v2}
      , 'marketplace-bps := mk-bps, 'active := active }
      { 'seller: seller, 'price: price, 'currency: currency
      , 'fee-bps: mk-bps, 'active: active }))

  (defun owner-of:string (id:string) (at 'owner (read tokens id)))

  (defun is-listed:bool (id:string)
    (with-default-read listings id { 'active: false } { 'active := active } active))

  (defun get-escrow-account:string () ESCROW)
)
