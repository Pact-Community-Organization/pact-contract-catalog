;; nft-market-v1 — Kadena NFT fixed-price sale standard (Pact 5 / KDA-CE)
;;
;; The sale half of the NFT standard: how a token is listed at a fixed price
;; and bought through a trustless, conservation-checked escrow that pays the
;; creator royalty atomically. A module that implements this MUST also
;; implement nft-asset-v1 (a market with no asset is meaningless) and MUST emit
;; nft-asset-v1.SOLD on every buy — that is where the money amounts are
;; reported to indexers.
;;
;; DELIBERATELY OUT OF SCOPE — left implementation-private so competing
;; marketplaces stay conformant without sharing an economic model:
;;   * how the platform / marketplace fee PAYEE is chosen (a fixed revenue
;;     account, a seller-named marketplace, a DAO treasury, …). The fee RATE
;;     and AMOUNT are public via LISTED.fee-bps and SOLD.fee; the routing is
;;     not part of the ABI.
;;   * auctions, offers/bids, bundles, lazy minting — a later interface may add
;;     these; this one is fixed price only.
;; This mirrors the lesson from the Marmalade V2 analysis: standardize the
;; surface tooling depends on, keep the trusted economic surface small and
;; private. Fixing fee routing into the ABI is exactly the over-coupling to
;; avoid.
;;
;; Cannot be upgraded; a breaking change ships as nft-market-v2.

(interface nft-market-v1

  @doc "Standard surface for fixed-price NFT sales with atomic royalty payout. \
       \Settlement MUST be single-point and conservation-asserted: the buyer \
       \pays exactly `price` into an escrow, the escrow pays royalty + fee + \
       \seller, and the implementation MUST assert escrow-in = sum of payouts \
       \to the currency's full precision (SPEC S2). Economic parameters MUST \
       \come from on-chain listing/token state, NEVER from the buy transaction \
       \(SPEC S3)."

  ;; The sale currency is any fungible-v2 (KDA `coin`, a stablecoin, …). A
  ;; KDA-only marketplace simply always passes `coin`. This keeps stable-
  ;; denominated sales possible without a second interface.

  (defschema listing
    @doc "The public projection of an active listing. `fee-bps` is the platform \
         \/ marketplace fee rate SNAPSHOTTED at list time — buy MUST read the \
         \rate from here, never from the buyer's transaction, so a post-listing \
         \rate change cannot alter a live sale and a buyer cannot zero the fee. \
         \`currency` is the fungible the price is denominated in."
    seller:string
    price:decimal
    currency:module{fungible-v2}
    fee-bps:integer
    active:bool)

  (defcap LISTED:bool (id:string seller:string price:decimal fee-bps:integer)
    @doc "Emitted when a token is listed. `fee-bps` is the snapshotted platform \
         \/ marketplace fee rate the sale will charge." @event)

  (defcap DELISTED:bool (id:string)
    @doc "Emitted when an active listing is cancelled." @event)

  (defun list-token:string (id:string price:decimal currency:module{fungible-v2})
    @doc "List an owned, resident token at a fixed PRICE in CURRENCY. PRICE MUST \
         \be positive and satisfy the currency precision. A royalty-bearing \
         \token MUST NOT be listable at a price whose floored royalty is zero \
         \(SPEC S2: a dust price is a royalty-free ownership change). The fee \
         \rate MUST be snapshotted from implementation state at list time, not \
         \taken from the caller. Owner-authenticated (scoped). Emits LISTED.")

  (defun delist:string (id:string)
    @doc "Cancel the caller's active listing. Owner-authenticated. Emits \
         \DELISTED.")

  (defun buy:string (id:string buyer:string buyer-guard:guard)
    @doc "Purchase a listed token at its fixed price. BUYER/BUYER-GUARD MUST be \
         \a principal account; BUYER signs the currency transfer of exactly \
         \`price` into the escrow. Settlement MUST pay creator (royalty) + \
         \platform/marketplace (fee, at the snapshotted rate) + seller \
         \(remainder) and MUST assert escrow conservation (SPEC S2). No \
         \parameter that affects the money MAY be read from the buy transaction \
         \(SPEC S3). Emits nft-asset-v1.SOLD.")

  (defun get-listing:object{listing} (id:string)
    @doc "The public listing row. MUST project exactly the `listing` schema.")

  (defun get-escrow-account:string ()
    @doc "The escrow account that briefly holds sale funds during settlement. \
         \Published so integrators can verify it is a capability-guarded \
         \principal (no external party can spend it) and MUST NOT send funds to \
         \it directly.")
)
