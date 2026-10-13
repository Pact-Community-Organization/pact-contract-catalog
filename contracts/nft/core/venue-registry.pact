;; nft.venue-registry — who opens a workshop, store or gallery, and what they charge.
;;
;; ADR-NFT-011 (founder, 2026-10-12): every fee but the protocol's is a free market.
;; Whoever runs a venue registers it here with THREE rates, in basis points of the
;; sale price:
;;   * primary-bps — the venue's cut on the FIRST sale of a token it helped create
;;                   (the seller is the token's author), bound into the token at
;;                   creation when the creator names this venue;
;;   * resale-bps  — the same venue's cut on every later sale of that token;
;;   * listing-bps — the venue's cut when it LISTS a token for sale (a store or
;;                   gallery), bound into the quote at offer.
;; The owner may change the rates at any time — for FUTURE creations and
;; listings only: the ledger copies the rates into each token at creation and
;; into each quote at offer, so no rate change ever reaches an existing token or
;; an open sale. Registration is permissionless; the venue id is derived from the
;; name and the owner guard, so nobody can claim another's venue on any chain.

(namespace (read-string 'ns))

(module venue-registry GOVERNANCE
  @doc "Permissionless registry of venues (workshops, stores, galleries) and \
       \their three fee rates; rates are snapshotted by the ledger at use."

  (defconst ADMIN-KS:string (read-string 'admin-ks)
    @doc "Admin keyset name, captured ONCE at deploy — never read from a \
         \caller's payload at enforcement time.")

  (defcap GOVERNANCE ()
    (enforce-keyset ADMIN-KS))

  (defconst BPS-DENOM:integer 10000)
  (defconst VENUE-ID-PREFIX:string "v")

  (defschema venue
    name:string
    owner-guard:guard
    account:string
    guard:guard
    primary-bps:integer
    resale-bps:integer
    listing-bps:integer)
  (deftable venues:{venue})

  (defcap VENUE:bool (venue-id:string name:string account:string primary-bps:integer resale-bps:integer listing-bps:integer)
    @doc "Emitted at registration and on every rate change."
    @event true)

  (defcap OWNER:bool (venue-id:string owner-guard:guard)
    @doc "The venue owner proves control of the guard the id is derived from."
    (enforce-guard owner-guard))

  ;; --- identity ----------------------------------------------------------------
  (defun create-venue-id:string (name:string owner-guard:guard)
    @doc "v:{hash([name, owner-guard])} — derived, so a venue name belongs to \
         \whoever controls the guard, on every chain."
    (format "{}:{}" [VENUE-ID-PREFIX (hash [name owner-guard])]))

  (defun enforce-valid-bps:bool (label:string bps:integer)
    (enforce (and (>= bps 0) (<= bps BPS-DENOM))
      (format "{} must be in [0, {}]" [label BPS-DENOM])))

  ;; --- registration (permissionless; owner-signed) -----------------------------
  (defun register-venue:string
    ( name:string owner-guard:guard account:string guard:guard
      primary-bps:integer resale-bps:integer listing-bps:integer )
    @doc "Register a venue. Returns its id. The payout ACCOUNT must be the \
         \principal of GUARD under a binding protocol (k:/w:/c:, or r: in a \
         \principal namespace — util.enforce-binding-payee). One-time: \
         \the insert refuses a second registration of the same name by the \
         \same owner (use set-rates to change rates)."
    (enforce (!= "" name) "venue name required")
    ;; ADR-NFT-016: k:/w:/c:, or r: in a principal namespace (a store may rotate its payout keys)
    (util.enforce-binding-payee account guard)
    (enforce-valid-bps "primary-bps" primary-bps)
    (enforce-valid-bps "resale-bps" resale-bps)
    (enforce-valid-bps "listing-bps" listing-bps)
    (let ((id:string (create-venue-id name owner-guard)))
      (with-capability (OWNER id owner-guard)
        (insert venues id
          { 'name: name, 'owner-guard: owner-guard, 'account: account, 'guard: guard
          , 'primary-bps: primary-bps, 'resale-bps: resale-bps, 'listing-bps: listing-bps })
        (emit-event (VENUE id name account primary-bps resale-bps listing-bps)))
      id))

  (defun set-rates:bool (venue-id:string primary-bps:integer resale-bps:integer listing-bps:integer)
    @doc "Change the venue's rates for FUTURE creations and listings. Owner-signed."
    (enforce-valid-bps "primary-bps" primary-bps)
    (enforce-valid-bps "resale-bps" resale-bps)
    (enforce-valid-bps "listing-bps" listing-bps)
    (with-read venues venue-id { 'owner-guard := og, 'name := name, 'account := account }
      (with-capability (OWNER venue-id og)
        (update venues venue-id
          { 'primary-bps: primary-bps, 'resale-bps: resale-bps, 'listing-bps: listing-bps })
        (emit-event (VENUE venue-id name account primary-bps resale-bps listing-bps))))
    true)

  ;; --- views -------------------------------------------------------------------
  (defun get-venue:object{venue} (venue-id:string) (read venues venue-id))
)
