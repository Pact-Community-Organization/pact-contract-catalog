;; nft-asset-v1 — Kadena 1-of-1 NFT asset standard (Pact 5 / KDA-CE)
;;
;; The asset half of the NFT standard: what a token IS, who owns it, its
;; immutable creator royalty, and the event vocabulary every wallet, indexer
;; and marketplace aggregator reads. Deliberately says NOTHING about how a
;; token is sold — that is nft-market-v1 — or moved across chains — that is
;; nft-xchain-v1. An implementation MAY implement this interface alone (a
;; non-tradable collectible), or with either or both of the others.
;;
;; This interface can never be upgraded (Pact CannotUpgradeInterface). Any
;; breaking change ships as nft-asset-v2. The normative rules an implementer
;; MUST satisfy — beyond these signatures — live in SPEC.md; the conformance
;; suite mechanically checks them against any candidate module.

(interface nft-asset-v1

  @doc "Standard surface for a 1-of-1 (non-fungible, non-fractional) token with \
       \an immutable creator royalty. Ownership is a single account+guard; a \
       \token is indivisible and has exactly one owner at a time. Royalty terms \
       \are fixed at mint and can never change. See SPEC.md for the normative \
       \MUST/MUST-NOT rules (fail-closed inputs, principal accounts, royalty \
       \immutability, event-completeness) that this signature set cannot express."

  ;; --- shared row shape ------------------------------------------------------
  ;; get-token returns this named schema so any reader binds the same fields
  ;; across every conforming module. Implementations MAY store additional
  ;; private columns, but get-token MUST project exactly these.
  (defschema token
    @doc "The public projection of a token. `royalty-bps` is immutable after \
         \mint. `transferable` false marks a sale-only token (see SPEC S4): it \
         \may change beneficial owner ONLY through a royalty-paying sale."
    owner:string
    owner-guard:guard
    creator:string
    creator-guard:guard
    royalty-bps:integer
    transferable:bool
    uri:string)

  ;; --- events (the indexer vocabulary) --------------------------------------
  ;; Every conforming module MUST emit these — and ONLY with these signatures —
  ;; so one indexer reconstructs full ownership and sale history across all
  ;; implementers. MINTED carries the initial owner (an indexer that sees only
  ;; MINTED + TRANSFERRED + SOLD can derive current ownership without a chain
  ;; read). A market implementation's buy MUST emit SOLD (declared here so the
  ;; asset-level indexer sees sales even for asset-only tooling).

  (defcap MINTED:bool
    (id:string owner:string creator:string royalty-bps:integer transferable:bool)
    @doc "Emitted exactly once, when a token is created. `owner` is the initial \
         \owner; `creator` is the permanent royalty payee." @event)

  (defcap TRANSFERRED:bool (id:string from:string to:string)
    @doc "Emitted on a no-payment ownership change (gift / custody move). A \
         \royalty-paying sale emits SOLD, not TRANSFERRED." @event)

  (defcap SOLD:bool
    (id:string seller:string buyer:string price:decimal royalty:decimal fee:decimal)
    @doc "Emitted by a market implementation's buy. `price` is the amount the \
         \buyer paid; `royalty` went to the creator; `fee` to the platform / \
         \marketplace; the remainder (price - royalty - fee) to the seller. \
         \Amounts are in the sale currency's units." @event)

  ;; --- mint -----------------------------------------------------------------
  (defun mint:string
    ( id:string
      owner:string owner-guard:guard
      creator:string creator-guard:guard
      royalty-bps:integer
      transferable:bool
      uri:string )
    @doc "Create a 1-of-1 token with id ID. OWNER/OWNER-GUARD and \
         \CREATOR/CREATOR-GUARD MUST each be a principal account (validate- \
         \principal). ROYALTY-BPS is the immutable royalty in basis points and \
         \MUST be validated against an implementation cap. The caller MUST \
         \prove control of OWNER-GUARD (scoped). Emits MINTED. See SPEC S1/S3.")

  ;; --- free transfer --------------------------------------------------------
  (defun transfer:string (id:string receiver:string receiver-guard:guard)
    @doc "Move a token with NO payment. RECEIVER/RECEIVER-GUARD MUST be a \
         \principal account. MUST reject a sale-only token (transferable=false) \
         \and MUST reject a token that is currently listed. Owner-authenticated \
         \(scoped). Emits TRANSFERRED. See SPEC S4.")

  ;; --- views (read-only; the fields tooling depends on) ---------------------
  (defun get-token:object{token} (id:string)
    @doc "The public token row. MUST project exactly the `token` schema. NOTE: \
         \for a cross-chain implementer (nft-xchain-v1) this MAY return the \
         \stale row of a token that has moved away — the `token` schema carries \
         \no residence field. Residence is signalled by `owner-of` (which MUST \
         \abort on a non-resident token) and the MOVE-INITIATED/MOVE-COMPLETED \
         \events; an indexer MUST follow those, not poll get-token, to track a \
         \token across chains.")

  (defun owner-of:string (id:string)
    @doc "The current owner account. An implementation whose tokens can leave \
         \the chain (see nft-xchain-v1) MUST reject a token not resident here \
         \rather than return a stale owner.")

  (defun is-listed:bool (id:string)
    @doc "True iff the token currently has an active listing. MUST be total \
         \(never abort) — false for unknown or unlisted tokens.")
)
