;; nft-xchain-v1 — Kadena cross-chain NFT relocation standard (Pact 5 / KDA-CE)
;;
;; The portability half of the NFT standard: how a token leaves one Chainweb
;; chain and arrives on another via a two-step SPV defpact. OPT-IN — a
;; marketplace that operates on a single chain implements only nft-asset-v1
;; (+ nft-market-v1) and omits this. A module that DOES implement it MUST also
;; implement nft-asset-v1.
;;
;; This is the interface that makes "a token minted on chain 1, sold on chain
;; 0" behave identically across competing marketplaces: same defpact shape,
;; same events, same tombstone semantics, so one indexer follows a token across
;; chains regardless of which marketplace moved it.
;;
;; Cross-chain behavior is DEVNET-provable only — SPV is unsupported in the
;; bare REPL, so a green cross-chain .repl is a false positive (SPEC S6). The
;; conformance suite checks only the same-chain guards of step 0; the SPV round
;; trip is validated on a multi-chain devnet.
;;
;; Cannot be upgraded; a breaking change ships as nft-xchain-v2.

(interface nft-xchain-v1

  @doc "Standard surface for relocating a 1-of-1 token between Chainweb chains. \
       \A move is a two-step SPV defpact: step 0 on the source chain tombstones \
       \the token locally and yields its full record; step 1 on the target \
       \chain writes it live. A move MUST NOT change beneficial ownership of a \
       \sale-only token (SPEC S5: that would bypass the royalty) — such a token \
       \may relocate ONLY to its own current owner. Listings MUST NOT travel. \
       \There is NO rollback across the yield: an initiated move is completed \
       \by continuation only, and an upgrade while moves are in flight MUST \
       \bless the prior module hash (SPEC S6)."

  (defcap MOVE-INITIATED:bool
    (id:string owner:string receiver:string target-chain:string)
    @doc "Emitted by step 0 on the source chain when a token is tombstoned for \
         \relocation. After this event the token is not resident on this chain \
         \until the move is rolled forward on TARGET-CHAIN." @event)

  (defcap MOVE-COMPLETED:bool (id:string receiver:string source-chain:string)
    @doc "Emitted by step 1 on the target chain when the token becomes resident \
         \there, owned by RECEIVER." @event)

  (defpact move-crosschain:string
    ( id:string
      receiver:string
      receiver-guard:guard
      target-chain:string )
    @doc "Relocate token ID to TARGET-CHAIN. Step 0 (source): owner-authorized; \
         \the token MUST be resident and not listed; TARGET-CHAIN MUST be a \
         \valid, different Chainweb chain id; a sale-only token's RECEIVER/ \
         \RECEIVER-GUARD MUST equal its current owner (SPEC S5); the row is \
         \tombstoned and the full record yielded (emits MOVE-INITIATED). Step 1 \
         \(target, via SPV continuation): the record is written resident, owned \
         \by RECEIVER (emits MOVE-COMPLETED). A RECEIVER on a transferable token \
         \MUST be a principal account.")
)
