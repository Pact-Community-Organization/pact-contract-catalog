;; nft-marketplace — sale-contract standard
;;
;; The marketplace half of the separation: a sale contract that OWNS NO TOKENS.
;; It presents a guard (the one an owner consigns to via nft-asset.list-for-sale)
;; and drives a foreign NFT's sale through a module{std.nft-asset} modref.
;;
;; The Pact-5 constraint (design note): a caller cannot acquire THIS module's
;; SELL capability from outside, so `execute-sale` is a PUBLIC entry that acquires
;; SELL internally and calls nft::buy. The NFT is a modref PARAMETER — one
;; marketplace sells any conforming NFT, never a hard-coded one.

(interface nft-marketplace

  @doc "A permissionless NFT sale contract. Owns no tokens; sells any nft-asset \
       \consigned to its guard. Its fee policy (rate, payee) is its own — the \
       \asset caps the fee it will accept, but does not dictate it."

  (defun marketplace-guard:guard ()
    @doc "The guard an owner consigns to (nft-asset.list-for-sale mkt-guard …). \
         \Only this marketplace can satisfy it, so only this marketplace can \
         \drive a sale of an NFT consigned to it.")

  (defun execute-sale:string
    ( nft:module{std.nft-asset}
      buyer:string buyer-guard:guard )
    @doc "Sell NFT (consigned to this marketplace) to BUYER. Acquires this \
         \marketplace's SELL authority internally and calls nft::buy, passing \
         \this marketplace's fee account/guard and rate. The NFT enforces the \
         \consignment guard and pays the creator royalty itself, so this \
         \marketplace can never bypass the royalty — it only adds its own fee.")
)
