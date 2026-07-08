;; conformance-driver — exercises an NFT implementation through interface
;; modrefs ONLY. It never names royalty-sale or smartpacts-gallery; every call
;; goes through module{<pco-ns>.nft-asset-v1} / module{<pco-ns>.nft-market-v1},
;; fully qualified against the PCO namespace the standard is published in
;; (testnet06: n_e82dd10f74b7e8c253553de95629fdfa35cf8379 — a different network
;; patches this literal, see README). If a driver function typechecks and runs
;; against a candidate module, that candidate's surface is polymorphically
;; usable through the deployed standard — the whole point.
;;
;; This is test scaffolding, not a library template: it lives under standards/
;; and is loaded only by the conformance .repl suites (into the `user`
;; namespace, so the dispatch crosses namespaces exactly as it does on-chain).

(module conformance-driver GOV
  ;; Test scaffolding, not a deployable artifact — but governance is a real
  ;; keyset (not a `true` body) so the driver holds itself to the same bar the
  ;; standard demands of implementers. The suite defines `user.conformance-gov`.
  (defcap GOV () (enforce-guard (keyset-ref-guard "user.conformance-gov")))

  ;; --- nft-asset-v1 surface ---
  (defun d-mint:string
    ( m:module{n_e82dd10f74b7e8c253553de95629fdfa35cf8379.nft-asset-v1}
      id:string owner:string owner-guard:guard
      creator:string creator-guard:guard
      royalty-bps:integer transferable:bool uri:string )
    (m::mint id owner owner-guard creator creator-guard royalty-bps transferable uri))

  (defun d-transfer:string
    ( m:module{n_e82dd10f74b7e8c253553de95629fdfa35cf8379.nft-asset-v1}
      id:string receiver:string receiver-guard:guard )
    (m::transfer id receiver receiver-guard))

  (defun d-get-token:object{n_e82dd10f74b7e8c253553de95629fdfa35cf8379.nft-asset-v1.token}
    ( m:module{n_e82dd10f74b7e8c253553de95629fdfa35cf8379.nft-asset-v1} id:string )
    (m::get-token id))

  (defun d-owner-of:string
    ( m:module{n_e82dd10f74b7e8c253553de95629fdfa35cf8379.nft-asset-v1} id:string )
    (m::owner-of id))

  (defun d-is-listed:bool
    ( m:module{n_e82dd10f74b7e8c253553de95629fdfa35cf8379.nft-asset-v1} id:string )
    (m::is-listed id))

  ;; project a single field so a suite can assert royalty immutability etc.
  ;; through the modref without re-declaring the schema inline
  (defun d-royalty-bps:integer
    ( m:module{n_e82dd10f74b7e8c253553de95629fdfa35cf8379.nft-asset-v1} id:string )
    (at 'royalty-bps (m::get-token id)))

  (defun d-transferable:bool
    ( m:module{n_e82dd10f74b7e8c253553de95629fdfa35cf8379.nft-asset-v1} id:string )
    (at 'transferable (m::get-token id)))

  ;; --- nft-market-v1 surface ---
  (defun d-list:string
    ( m:module{n_e82dd10f74b7e8c253553de95629fdfa35cf8379.nft-market-v1}
      id:string price:decimal currency:module{fungible-v2} )
    (m::list-token id price currency))

  (defun d-delist:string
    ( m:module{n_e82dd10f74b7e8c253553de95629fdfa35cf8379.nft-market-v1} id:string )
    (m::delist id))

  (defun d-buy:string
    ( m:module{n_e82dd10f74b7e8c253553de95629fdfa35cf8379.nft-market-v1}
      id:string buyer:string buyer-guard:guard )
    (m::buy id buyer buyer-guard))

  (defun d-get-listing:object{n_e82dd10f74b7e8c253553de95629fdfa35cf8379.nft-market-v1.listing}
    ( m:module{n_e82dd10f74b7e8c253553de95629fdfa35cf8379.nft-market-v1} id:string )
    (m::get-listing id))

  (defun d-listing-price:decimal
    ( m:module{n_e82dd10f74b7e8c253553de95629fdfa35cf8379.nft-market-v1} id:string )
    (at 'price (m::get-listing id)))

  (defun d-listing-fee-bps:integer
    ( m:module{n_e82dd10f74b7e8c253553de95629fdfa35cf8379.nft-market-v1} id:string )
    (at 'fee-bps (m::get-listing id)))

  (defun d-listing-active:bool
    ( m:module{n_e82dd10f74b7e8c253553de95629fdfa35cf8379.nft-market-v1} id:string )
    (at 'active (m::get-listing id)))

  (defun d-escrow:string
    ( m:module{n_e82dd10f74b7e8c253553de95629fdfa35cf8379.nft-market-v1} )
    (m::get-escrow-account))
)
