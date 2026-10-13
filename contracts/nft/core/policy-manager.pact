;; nft.policy-manager — the HARDENED policy dispatcher + settlement engine.
;;
;; This is the module where the Marmalade architecture's real flaws are fixed
;; (our Marmalade V2 analysis: ARCH-1, ARCH-2):
;;
;;  ARCH-2 (economics-from-the-buyer's-tx): the sale QUOTE — price, fungible,
;;  seller payout account, and the marketplace fee (rate + payee) — is bound in
;;  STATE at OFFER time, from the seller's signed offer, and read from state at
;;  buy. The buyer supplies only their own paying account; they cannot set or
;;  zero any economic parameter.
;;
;;  ARCH-1 (shared-escrow sweep-what's-left): settlement is ONE routine. Each
;;  policy DECLARES its payout(s) (computed from the policy's own state) but
;;  moves no money; the manager pays every declared payout + the marketplace fee
;;  + the seller remainder from a single capability-guarded escrow and ASSERTS
;;  escrow-in = Σ payouts to the fungible's full precision. No policy hook holds
;;  spend authority over the escrow.
;;
;; Same-payee legs are merged (creator==seller, fee==seller, …) so a collision
;; can never brick a managed-transfer install.
;;
;; TRUST BOUNDARY — the quote's fungible: settlement necessarily executes the
;; quote fungible's own code while the per-sale ESCROW capability is in scope.
;; That capability is scoped to THIS sale-id (its escrow principal is
;; sale-unique and holds only this sale's funds) and the conservation assert
;; closes the ledger over exactly the quoted price — so a hostile fungible can
;; only misbehave inside the sale its own participants opted into. Policy hooks
;; run BEFORE the escrow capability is acquired, never inside it.
;;
;; Note: the `module{fungible-v2}` annotation on the PAYLOAD-sourced quote
;; fungible checks the tx-supplied `refSpec` interface list, not the named
;; module's real `implements` list, and dynamic dispatch is name-based — the
;; annotation is a shape check, never an interface-conformance guarantee. The
;; containment above (sale-scoped escrow + conservation assert) is what
;; actually bounds a hostile fungible; that is why the quote's fungible is a
;; documented trust boundary rather than a validated input.
;;
;; Quote rows are permanent: a settled or withdrawn sale keeps its quote row
;; (Pact has no row deletion; the one-shot sale defpact steps make replay
;; impossible). Treat `quotes` as the immutable sale-economics history — so the
;; EXISTENCE of a quote row is NOT evidence that its sale is still live.
;;
;; SALE LIVENESS: Pact exposes no builtin that reads defpact completion, so a
;; registered sale contract cannot ask the engine whether the ledger's sale
;; defpact for a sale-id is still running. This manager is the only party that
;; can answer: EVERY terminal transition of that defpact routes through it —
;; step-0 rollback through enforce-withdraw, step 1 through enforce-buy — so it
;; records the answer in the quote row's `active` flag (true at offer, false at
;; withdraw and at buy) and publishes it as `sale-live`. A sale contract that
;; takes on obligations or escrows money for a sale-id MUST gate on
;; `enforce-sale-live`: without it an auction can be attached to a corpse and
;; every bid escrowed into it is unrecoverable (nothing can settle or refund
;; once the defpact is complete).

(namespace (read-string 'ns))

(module policy-manager GOVERNANCE
  @doc "Hardened policy dispatcher + conservation-asserted settlement for the \
       \nft framework."

  (use token-policy [token-info payout])

  (defconst ADMIN-KS:string (read-string 'admin-ks)
    @doc "Admin keyset name, captured ONCE at deploy — never read from a \
         \caller's payload at enforcement time.")

  (defcap GOVERNANCE ()
    (enforce-keyset ADMIN-KS))

  (defconst BPS-DENOM:integer 10000)

  ;; --- the protocol leg (ADR-NFT-006): one governance-set rate, every sale -------
  ;; Founder, 2026-10-12: the PCO protocol fee is fixed (0.5% at launch); every
  ;; other fee is a free market bounded only by the 100% rule below. The rate
  ;; and payee live in state, never in a quote or a buy payload. Unset = 0.
  (defschema protocol-params
    bps:integer
    account:string
    guard:guard)
  (deftable params:{protocol-params})
  (defconst PARAMS-KEY:string "protocol")

  (defun set-protocol-fee:bool (bps:integer account:string guard:guard)
    @doc "Governance sets the protocol leg: rate in bps and the payee, whose \
         \name must be the principal of its guard."
    (enforce (and (>= bps 0) (<= bps BPS-DENOM)) "protocol bps must be in [0, 10000]")
    (if (> bps 0)
      (util.enforce-binding-payee account guard)   ;; ADR-NFT-016
      true)
    (with-capability (GOVERNANCE)
      (write params PARAMS-KEY { 'bps: bps, 'account: account, 'guard: guard }))
    true)

  (defun protocol-bps:integer ()
    (with-default-read params PARAMS-KEY { 'bps: 0 } { 'bps := b } b))
  (defun get-protocol:object{protocol-params} ()
    (with-default-read params PARAMS-KEY
      { 'bps: 0, 'account: "", 'guard: (create-capability-guard (GOVERNANCE)) }
      { 'bps := b, 'account := a, 'guard := g } { 'bps: b, 'account: a, 'guard: g }))

  ;; --- the creation venue (ADR-NFT-011): the workshop's two rates, per token ----
  ;; A creator who creates through a venue names its id in the creation payload;
  ;; the venue's primary and resale rates are COPIED here at that moment and never
  ;; change for this token, whatever the venue does to its rates later.
  (defschema creation-venue
    venue-id:string
    account:string
    guard:guard
    primary-bps:integer
    resale-bps:integer)
  (deftable creation-venues:{creation-venue})
  (defconst CREATION-VENUE-MSG-KEY:string "creation_venue"
    @doc "Optional create-token-tx payload key: the id of the venue (workshop) \
         \the token is created through. Absent = no creation-venue leg.")

  (defun get-creation-venue:object{creation-venue} (token-id:string)
    (with-default-read creation-venues token-id
      { 'venue-id: "", 'account: "", 'guard: (create-capability-guard (GOVERNANCE)), 'primary-bps: 0, 'resale-bps: 0 }
      { 'venue-id := v, 'account := a, 'guard := g, 'primary-bps := p, 'resale-bps := r }
      { 'venue-id: v, 'account: a, 'guard: g, 'primary-bps: p, 'resale-bps: r }))

  (defun creation-venue-bps:integer (token-id:string seller:string author:string)
    @doc "The creation venue's rate for THIS sale: primary when the seller is \
         \the token's author, resale otherwise."
    (let ((cv (get-creation-venue token-id)))
      (if (= seller author) (at 'primary-bps cv) (at 'resale-bps cv))))

  (defun policies-bps:integer (token:object{token-info})
    @doc "Σ payout-bps over every attached policy: the most the policies will \
         \ever claim from a sale of TOKEN."
    (fold (+) 0 (map (lambda (p:module{token-policy}) (p::payout-bps token)) (at 'policies token))))

  ;; --- the registered ledger (set once at init) -------------------------------
  (defschema ledger-ref ledger:module{ledger-iface})
  (deftable ledgers:{ledger-ref})
  (defconst LEDGER-KEY:string "l")

  (defun init:bool (ledger:module{ledger-iface})
    @doc "One-time registration of the ledger this manager serves. Gov-gated."
    (with-capability (GOVERNANCE)
      (insert ledgers LEDGER-KEY { 'ledger: ledger }))
    true)

  (defun retrieve-ledger:module{ledger-iface} ()
    (at 'ledger (read ledgers LEDGER-KEY)))

  ;; --- registered sale contracts (price-discovery sales; gov-gated) -----------
  ;; A quote may name a sale contract (auction, timed sale, ...) that finalizes
  ;; the price at settlement from ITS OWN on-chain state. Only governance-
  ;; registered contracts participate — a seller cannot route settlement
  ;; through arbitrary code.
  (defschema sale-ref
    contract:module{sale}
    enabled:bool)
  (deftable sale-contracts:{sale-ref})

  (defun register-sale-contract:bool (contract:module{sale})
    @doc "Register a sale contract under its own fully-qualified name (the key \
         \is derived from the modref — a name cannot be claimed for foreign \
         \code). Gov-gated; insert makes registration one-time."
    (with-capability (GOVERNANCE)
      (insert sale-contracts (format "{}" [contract])
        { 'contract: contract, 'enabled: true }))
    true)

  (defun set-sale-contract-enabled:bool (name:string enabled:bool)
    @doc "Gov kill-switch for a registered sale contract. Disabling blocks NEW \
         \offers and settlements through it; withdrawal (the escape hatch) \
         \still consults the contract."
    (with-capability (GOVERNANCE)
      (update sale-contracts name { 'enabled: enabled }))
    true)

  (defun get-sale-contract:object{sale-ref} (name:string)
    (read sale-contracts name))

  ;; NOTE: uri-update routing needs no registry. Every attached policy declares
  ;; its stance through the base token-policy uri-decision hook, so the manager
  ;; evaluates ALL of them at update time (see enforce-update-uri below) — a
  ;; policy cannot be bypassed by omission, which the old global registry
  ;; allowed (an attached-but-unregistered veto was silently skipped).

  ;; --- the quote: sale economics, bound at OFFER, read at BUY -----------------
  (defschema quote-spec
    @doc "What the seller signs at offer. All economics live HERE (state), never \
         \in the buy tx. fee-account/fee-guard/fee-bps are the marketplace fee \
         \the seller agreed to by signing the offer. sale-contract is \"\" for a \
         \fixed-price sale (price > 0), or the fully-qualified name of a \
         \REGISTERED sale contract that finalizes the price at settlement from \
         \its own state (then price MUST be 0 — discovered, never pre-set)."
    fungible:module{fungible-v2}
    price:decimal
    seller-account:string
    seller-guard:guard
    venue-id:string
    fee-account:string
    fee-guard:guard
    fee-bps:integer
    buyer-share-bps:integer
    sale-contract:string)

  (defschema quote-schema
    token-id:string
    seller:string
    amount:decimal
    fungible:module{fungible-v2}
    price:decimal
    seller-account:string
    seller-guard:guard
    venue-id:string
    fee-account:string
    fee-guard:guard
    fee-bps:integer
    buyer-share-bps:integer
    sale-contract:string
    active:bool)
  (deftable quotes:{quote-schema})

  ;; LISTING EXPIRY (founder 2026-10-13, "expiry"): an optional deadline after which the listing can
  ;; no longer be bought. Kept in a SIDECAR table keyed by sale-id rather than a quote field: a field
  ;; added to `quotes` would break every row written before it at first access (an upgrade creates no
  ;; migration), while a missing sidecar ROW defaults cleanly to "no expiry". The seller's offer tx
  ;; carries it under `quote_expires` (unix seconds; absent or 0 = none). Withdrawal is the ledger's
  ;; timeout rule, unchanged; an expired listing is simply unbuyable until withdrawn.
  (defschema quote-expiry-row expires:integer)
  (deftable quote-expiry:{quote-expiry-row})
  (defconst QUOTE-EXPIRES-MSG-KEY:string "quote_expires")
  (defcap LISTING-EXPIRY:bool (sale-id:string expires:integer) @event true)

  (defun now-seconds:integer ()
    (floor (diff-time (at 'block-time (chain-data)) (time "1970-01-01T00:00:00Z"))))

  (defun listing-expires:integer (sale-id:string)
    @doc "The listing's deadline in unix seconds, 0 when it has none."
    (with-default-read quote-expiry sale-id { 'expires: 0 } { 'expires := e } e))

  (defconst QUOTE-MSG-KEY:string "quote"
    @doc "Offer-tx payload key carrying the quote-spec (SELLER's tx — safe). \
         \venue-id \"\" means the raw fee-account/fee-guard/fee-bps apply; a \
         \registered venue id means the registry's listing rate, account and \
         \guard are COPIED into the quote at offer (the raw fields are \
         \ignored). buyer-share-bps (≤ fee-bps) is the part of the listing fee \
         \the listing venue agrees to hand to a buyer-side venue named in the \
         \buy tx (ADR-NFT-011).")
  (defconst BUYER-ACCT-KEY:string "buyer_fungible_account"
    @doc "Buy-tx payload key: the buyer's OWN paying account (not economics).")
  (defconst BUYER-VENUE-KEY:string "buyer_venue_id"
    @doc "Optional buy-tx payload key: the registered venue that brought the \
         \buyer. It can only RECEIVE the share the seller's quote already \
         \granted; it changes no other leg.")
  (defconst QUOTED-PRICE-MSG-KEY:string "quoted_price"
    @doc "Buy-tx payload key for a quoted sale: the CANDIDATE final price. It \
         \is only a carrier — the sale contract must validate it against its \
         \own on-chain state (recorded bids / the price curve) before the \
         \manager binds and settles it.")

  (defcap QUOTE:bool (sale-id:string token-id:string price:decimal venue-id:string fee-bps:integer sale-contract:string) @event true)
  (defcap SETTLED:bool (sale-id:string price:decimal protocol:decimal creation-venue:decimal fee:decimal proceeds:decimal) @event true)
  (defcap CREATION-VENUE:bool (token-id:string venue-id:string primary-bps:integer resale-bps:integer) @event true)

  ;; --- the fungible escrow (one per sale-id, capability-guarded) --------------
  (defcap ESCROW:bool (sale-id:string)
    @doc "Spend authority over the sale's fungible escrow. Acquired ONLY inside \
         \this manager's single settlement routine."
    true)

  ;; --- sale-contract handshake caps (weak bodies by design) -------------------
  ;; Acquired only by this manager at the exact points below; a sale contract
  ;; require-capability's them so its hooks and its bid escrow are unreachable
  ;; outside the manager's settlement/withdrawal path.
  (defcap FUNDING-CALL:bool (sale-id:string)
    @doc "In scope exactly while the manager pulls the sale price into the \
         \sale escrow (a bid-escrow's guard requires it)." true)
  (defcap QUOTE-CALL:bool (sale-id:string price:decimal)
    @doc "Scopes a sale contract's enforce-quote-update to this manager's \
         \settlement." true)
  (defcap WITHDRAWAL-CALL:bool (sale-id:string)
    @doc "Scopes a sale contract's enforce-withdrawal to this manager's \
         \withdraw path." true)
  (defun escrow-guard:guard (sale-id:string) (create-capability-guard (ESCROW sale-id)))
  (defun escrow-account:string (sale-id:string) (create-principal (escrow-guard sale-id)))

  ;; --- lifecycle hooks (each verifies the ledger handshake, then dispatches) ---
  (defun enforce-init:bool (token:object{token-info})
    (let ((l:module{ledger-iface} (retrieve-ledger)))
      (require-capability (l::INIT-CALL (at 'id token) (at 'precision token) (at 'uri token))))
    (map (lambda (p:module{token-policy}) (p::enforce-init token)) (at 'policies token))
    ;; the CREATION VENUE (optional): copy the named venue's two rates into
    ;; this token, now and forever (ADR-NFT-011)
    (let ((venue-id:string (try "" (read-string CREATION-VENUE-MSG-KEY))))
      (if (= "" venue-id)
        true
        (let ((v (venue-registry.get-venue venue-id)))
          (insert creation-venues (at 'id token)
            { 'venue-id: venue-id, 'account: (at 'account v), 'guard: (at 'guard v)
            , 'primary-bps: (at 'primary-bps v), 'resale-bps: (at 'resale-bps v) })
          (emit-event (CREATION-VENUE (at 'id token) venue-id (at 'primary-bps v) (at 'resale-bps v))))))
    ;; THE ONE RULE (founder, 2026-10-12): the total can never exceed 100%.
    ;; At creation: protocol + the creation venue's LARGER rate + every
    ;; policy's declared maximum must fit, so the token is always sellable by
    ;; its own creator. The listing venue is checked against the remainder at
    ;; offer (validate-quote).
    (let* ((cv (get-creation-venue (at 'id token)))
           (venue-max (if (> (at 'primary-bps cv) (at 'resale-bps cv)) (at 'primary-bps cv) (at 'resale-bps cv)))
           (total (+ (protocol-bps) (+ venue-max (policies-bps token)))))
      (enforce (<= total BPS-DENOM)
        (format "payout plans exceed 100%: protocol {} + creation venue {} + policies {} bps"
          [(protocol-bps) venue-max (policies-bps token)])))
    true)

  (defun enforce-mint:bool (token:object{token-info} account:string guard:guard amount:decimal)
    (let ((l:module{ledger-iface} (retrieve-ledger)))
      (require-capability (l::MINT-CALL (at 'id token) account amount)))
    (map (lambda (p:module{token-policy}) (p::enforce-mint token account guard amount)) (at 'policies token))
    true)

  (defun enforce-burn:bool (token:object{token-info} account:string amount:decimal)
    (let ((l:module{ledger-iface} (retrieve-ledger)))
      (require-capability (l::BURN-CALL (at 'id token) account amount)))
    (map (lambda (p:module{token-policy}) (p::enforce-burn token account amount)) (at 'policies token))
    true)

  (defun enforce-transfer:bool (token:object{token-info} sender:string guard:guard receiver:string amount:decimal)
    (let ((l:module{ledger-iface} (retrieve-ledger)))
      (require-capability (l::TRANSFER-CALL (at 'id token) sender receiver amount)))
    (map (lambda (p:module{token-policy}) (p::enforce-transfer token sender guard receiver amount)) (at 'policies token))
    true)

  ;; --- CROSS-CHAIN: collect + re-bind the policy passports ---------------------
  (defun enforce-xchain-send:[object] (token:object{token-info} sender:string receiver:string receiver-guard:guard target-chain:string amount:decimal)
    @doc "Source chain: every policy validates the relocation and returns its \
         \passport. The result rides the ledger's yield to the target chain."
    (let ((l:module{ledger-iface} (retrieve-ledger)))
      (require-capability (l::XCHAIN-SEND-CALL (at 'id token) sender receiver target-chain amount)))
    ;; the manager's OWN passport first: the creation venue (ADR-NFT-011) is manager state that was
    ;; born on the creating chain only; it travels so the publisher's resale rate holds everywhere
    ;; (finding F2, 2026-10-12)
    (let ((mine:[object] [{ 'policy: "policy-manager", 'state: (get-creation-venue (at 'id token)) }])
          (theirs:[object] (map (lambda (p:module{token-policy})
                                  { 'policy: (format "{}" [p])
                                  , 'state: (p::enforce-xchain-send token sender receiver receiver-guard target-chain amount) })
                                (at 'policies token))))
      (+ mine theirs)))

  (defun enforce-xchain-receive:bool (token:object{token-info} receiver:string receiver-guard:guard amount:decimal passports:[object])
    @doc "Target chain: every attached policy gets ITS OWN passport back and \
         \re-binds it. A missing or duplicated passport fails closed."
    (let ((l:module{ledger-iface} (retrieve-ledger)))
      (require-capability (l::XCHAIN-RECEIVE-CALL (at 'id token) receiver amount)))
    (map (lambda (p:module{token-policy})
           (let* ((k:string (format "{}" [p]))
                  (matches:[object] (filter (lambda (pp:object) (= k (at 'policy pp))) passports)))
             (enforce (= 1 (length matches)) (format "passport missing for policy {}" [k]))
             (p::enforce-xchain-receive token receiver receiver-guard amount (at 'state (at 0 matches)))))
         (at 'policies token))
    ;; the manager's passport: re-bind the creation venue here (first arrival), or check it (a return)
    (let ((mine:[object] (filter (lambda (pp:object) (= "policy-manager" (at 'policy pp))) passports)))
      (if (= 1 (length mine))
        (let ((cv:object{creation-venue} (at 'state (at 0 mine))))
          (if (= "" (at 'venue-id cv))
            true
            (with-default-read creation-venues (at 'id token) { 'venue-id: "" } { 'venue-id := existing }
              (if (= "" existing)
                (let ((_ (insert creation-venues (at 'id token) cv)))
                  (emit-event (CREATION-VENUE (at 'id token) (at 'venue-id cv) (at 'primary-bps cv) (at 'resale-bps cv))))
                (enforce (= existing (at 'venue-id cv)) "creation-venue passport mismatch")))))
        true))
    true)

  (defun mint-delegated:bool (token:object{token-info} account:string amount:decimal)
    @doc "ATTACHMENT-AUTHORITATIVE mint stance — the same shape as the uri \
         \stance below. True when SOME policy attached to TOKEN returned \
         \\"permit\" from mint-decision: that policy takes over mint \
         \authorization and its own enforce-mint decides who may issue \
         \supply. False means nobody took over, and the ledger enforces the \
         \token's own creation-guard (author-only). The stance is read from \
         \EVERY attached policy, so it cannot be bypassed by omission, and \
         \the attached set is committed in the token id. Pure view: no guard \
         \check and no state write — but, like every other hook dispatch here, \
         \it is reachable ONLY from the ledger's mint path (the MINT-CALL \
         \handshake), so no external caller can drive a policy's \
         \mint-decision with a fabricated token-info."
    (let ((l:module{ledger-iface} (retrieve-ledger)))
      (require-capability (l::MINT-CALL (at 'id token) account amount)))
    (contains "permit"
      (map (lambda (p:module{token-policy}) (p::mint-decision token)) (at 'policies token))))

  ;; --- UPDATE-URI: fail closed, ATTACHMENT-authoritative ----------------------
  ;; Every attached policy declares its uri stance via the base token-policy
  ;; uri-decision hook — so a policy can NEVER be bypassed by being absent from
  ;; an out-of-band registry (the design flaw a global handler registry had).
  ;; A permitter additionally authorizes the specific update in its own
  ;; enforce-update-uri body. Rule: one veto is final; the
  ;; uri is immutable unless some policy permits AND none vetoes; a token with
  ;; no uri-aware policy (all abstain) is immutable by default.
  (defun enforce-update-uri:bool (token:object{token-info} new-uri:string)
    (let ((l:module{ledger-iface} (retrieve-ledger)))
      (require-capability (l::UPDATE-URI-CALL (at 'id token) new-uri)))
    (let* ((decisions:[string]
             (map (lambda (p:module{token-policy}) (p::uri-decision token)) (at 'policies token)))
           (vetoed:bool (contains "veto" decisions))
           (permitted:bool (contains "permit" decisions)))
      (enforce (not vetoed) "the token uri is immutable (a policy vetoes updates)")
      (enforce permitted "the token uri is immutable (no policy permits updates)")
      ;; run each permitter's own authorization (the guard check lives there)
      (map (lambda (p:module{token-policy})
             (if (= "permit" (p::uri-decision token))
               (p::enforce-update-uri token new-uri)
               false))
           (at 'policies token)))
    true)

  ;; --- OFFER: bind the quote in state --------------------------------------
  ;; The fungible escrow account is NOT pre-created here: its principal + guard
  ;; are publicly computable from the mempool-visible offer, so a pre-create
  ;; could be front-run into a duplicate-insert abort of the seller's offer.
  ;; The buy step's transfer-create creates the account (or enforces the guard
  ;; of a pre-existing one) — same fail-closed guarantee, no grief surface.
  (defun enforce-offer:bool (token:object{token-info} seller:string amount:decimal timeout:integer sale-id:string)
    (let ((l:module{ledger-iface} (retrieve-ledger)))
      (require-capability (l::OFFER-CALL (at 'id token) seller amount timeout sale-id)))
    ;; the quote comes from the SELLER's offer tx and is STORED (not the buyer's);
    ;; a registered listing venue's rate, account and guard are COPIED in now
    (let* ((raw:object{quote-spec} (read-msg QUOTE-MSG-KEY))
           (q:object{quote-spec} (resolve-venue raw)))
      (validate-quote q token seller)
      (insert quotes sale-id
        { 'token-id: (at 'id token), 'seller: seller, 'amount: amount
        , 'fungible: (at 'fungible q), 'price: (at 'price q)
        , 'seller-account: (at 'seller-account q), 'seller-guard: (at 'seller-guard q)
        , 'venue-id: (at 'venue-id q)
        , 'fee-account: (at 'fee-account q), 'fee-guard: (at 'fee-guard q)
        , 'fee-bps: (at 'fee-bps q), 'buyer-share-bps: (at 'buyer-share-bps q)
        , 'sale-contract: (at 'sale-contract q)
        , 'active: true })
      (emit-event (QUOTE sale-id (at 'id token) (at 'price q) (at 'venue-id q) (at 'fee-bps q) (at 'sale-contract q)))
      (let ((expires:integer (try 0 (read-integer QUOTE-EXPIRES-MSG-KEY))))
        (enforce (or (= expires 0) (> expires (now-seconds))) "listing expiry must be in the future")
        (if (> expires 0)
          (let ((_ (insert quote-expiry sale-id { 'expires: expires })))
            (emit-event (LISTING-EXPIRY sale-id expires)))
          true)))
    ;; run policy enforce-offer hooks
    (map (lambda (p:module{token-policy}) (p::enforce-offer token seller amount timeout sale-id)) (at 'policies token))
    true)

  (defun resolve-venue:object{quote-spec} (q:object{quote-spec})
    @doc "A quote naming a registered venue takes the venue's listing rate, \
         \account and guard from the registry (snapshot at offer); the raw fee \
         \fields are ignored. \"\" keeps the raw fields."
    (if (= "" (at 'venue-id q))
      q
      (let ((v (venue-registry.get-venue (at 'venue-id q))))
        (+ { 'fee-account: (at 'account v), 'fee-guard: (at 'guard v), 'fee-bps: (at 'listing-bps v) } q))))

  (defun validate-quote:bool (q:object{quote-spec} token:object{token-info} seller:string)
    (let ((fungible:module{fungible-v2} (at 'fungible q))
          (price:decimal (at 'price q))
          (fee-bps:integer (at 'fee-bps q))
          (share-bps:integer (at 'buyer-share-bps q))
          (sale-contract:string (at 'sale-contract q)))
      (if (= "" sale-contract)
        ;; fixed price: bound now, forever
        (enforce (> price 0.0) "price must be positive")
        ;; quoted sale: the price is DISCOVERED at settlement — it must start 0
        ;; and the named contract must be governance-registered and enabled
        (let ((sc (get-sale-contract sale-contract)))
          (enforce (at 'enabled sc) "sale contract is disabled")
          (enforce (= price 0.0) "a quoted sale's price must start at 0")))
      (fungible::enforce-unit price)
      (enforce (>= fee-bps 0) "fee-bps must not be negative")
      (enforce (and (>= share-bps 0) (<= share-bps fee-bps))
        "buyer-share-bps must be in [0, fee-bps]")
      (enforce (validate-principal (at 'seller-guard q) (at 'seller-account q))
        "seller-account must be a principal")
      (if (> fee-bps 0)
        (util.enforce-binding-payee (at 'fee-account q) (at 'fee-guard q))   ;; ADR-NFT-016
        true)
      ;; THE ONE RULE at offer: protocol + this sale's creation-venue rate +
      ;; the policies' maximum + the listing fee must fit in 100%. A venue whose
      ;; fee does not fit cannot list this token; the message says the headroom.
      (let* ((committed (+ (protocol-bps)
                           (+ (creation-venue-bps (at 'id token) seller (at 'author token))
                              (policies-bps token))))
             (headroom (- BPS-DENOM committed)))
        (enforce (<= fee-bps headroom)
          (format "listing fee {} bps exceeds the headroom {} bps left by protocol, creation venue and policies"
            [fee-bps headroom])))))

  ;; --- WITHDRAW: no manager fungible moved (the NFT returns via the ledger) ---
  ;; A quoted sale's contract must CONSENT (e.g. an auction refuses while live,
  ;; and refunds its bid escrow when it permits a post-deadline withdrawal).
  ;; The consent hook runs regardless of the contract's enabled flag —
  ;; withdrawal is the escape hatch.
  (defun enforce-withdraw:bool (token:object{token-info} seller:string amount:decimal timeout:integer sale-id:string)
    (let ((l:module{ledger-iface} (retrieve-ledger)))
      (require-capability (l::WITHDRAW-CALL (at 'id token) seller amount timeout sale-id)))
    (with-read quotes sale-id { 'sale-contract := sale-contract }
      (if (= "" sale-contract)
        true
        (let ((s:module{sale} (at 'contract (get-sale-contract sale-contract))))
          (with-capability (WITHDRAWAL-CALL sale-id)
            (s::enforce-withdrawal sale-id)))))
    (map (lambda (p:module{token-policy}) (p::enforce-withdraw token seller amount timeout sale-id)) (at 'policies token))
    ;; the sale defpact completes on this rollback — record it so no sale
    ;; contract can attach to, or escrow into, a dead sale afterwards
    (update quotes sale-id { 'active: false })
    true)

  ;; --- BUY: the SINGLE conservation-asserted settlement -----------------------
  (defun enforce-buy:bool (token:object{token-info} seller:string buyer:string buyer-guard:guard amount:decimal sale-id:string)
    (let ((l:module{ledger-iface} (retrieve-ledger)))
      (require-capability (l::BUY-CALL (at 'id token) seller buyer amount sale-id)))
    (let ((expires (listing-expires sale-id)))
      (enforce (or (= expires 0) (<= (now-seconds) expires)) "listing has expired"))
    (with-read quotes sale-id
      { 'fungible := fungible:module{fungible-v2}, 'price := stored-price
      , 'seller-account := seller-account, 'seller-guard := seller-guard
      , 'fee-account := fee-account, 'fee-guard := fee-guard, 'fee-bps := fee-bps
      , 'buyer-share-bps := share-bps
      , 'sale-contract := sale-contract }
      (let ((prec (fungible::precision))
            (escrow (escrow-account sale-id))
            (buyer-account:string (read-msg BUYER-ACCT-KEY))  ;; buyer's OWN account
            ;; a quoted sale finalizes its price NOW: the buy tx carries only a
            ;; CANDIDATE; the registered sale contract must validate it against
            ;; its own on-chain state (recorded bids / the price curve), then
            ;; the manager binds it into the quote before any money moves.
            (price:decimal
              (if (= "" sale-contract)
                stored-price
                (let ((sc (get-sale-contract sale-contract)))
                  (enforce (at 'enabled sc) "sale contract is disabled")
                  (let ((s:module{sale} (at 'contract sc))
                        (candidate:decimal (read-msg QUOTED-PRICE-MSG-KEY)))
                    (enforce (> candidate 0.0) "quoted price must be positive")
                    (fungible::enforce-unit candidate)
                    (with-capability (QUOTE-CALL sale-id candidate)
                      (s::enforce-quote-update sale-id candidate))
                    (update quotes sale-id { 'price: candidate })
                    candidate)))))
        ;; INTERACTION 1: the escrow is funded with EXACTLY the state price —
        ;; from the buyer's account, or from a sale contract's bid escrow
        ;; (whose guard requires FUNDING-CALL for this sale).
        (with-capability (FUNDING-CALL sale-id)
          (fungible::transfer-create buyer-account escrow (escrow-guard sale-id) price))
        ;; ...and it must have landed under OUR guard. The escrow principal is
        ;; publicly computable from the mempool-visible offer, so on a fungible
        ;; that does not enforce reserved account-name protocols a stranger can
        ;; hold that name first; the deposit would then either brick the sale or
        ;; (if the fungible also skips the credit-time guard match) be swept by
        ;; the squatter. Checked AFTER the transfer so no `try` is needed — see
        ;; enforce-account-custody. An abort rolls back the funding with it.
        (enforce-account-custody fungible escrow (escrow-guard sale-id))
        (let ((funded (fungible::get-balance escrow)))
          ;; policies DECLARE their cuts (computed from their own state); they
          ;; move no money. (Phase 3's royalty policy returns the creator's cut.)
          (let* ((policy-payouts:[object{payout}]
                   (fold (lambda (acc:[object{payout}] pol:module{token-policy})
                           (+ acc (pol::enforce-buy token seller buyer buyer-guard amount sale-id)))
                         [] (at 'policies token)))
                 ;; every declared cut MUST be strictly positive: a zero leg is
                 ;; noise, a negative leg would count against cuts-total (shrinking
                 ;; it) while merge-payout drops it from the paid set — the two
                 ;; must agree, so reject non-positive legs outright (fail closed)
                 (checked:[bool] (map (lambda (p:object{payout})
                                        (enforce (> (at 'amount p) 0.0)
                                          "a policy declared a non-positive payout"))
                                      policy-payouts))
                 (bps-cut (lambda (bps:integer) (if (> bps 0) (floor (/ (* price (dec bps)) (dec BPS-DENOM)) prec) 0.0)))
                 ;; the PROTOCOL leg (governance-set, ADR-NFT-006)
                 (proto (get-protocol))
                 (protocol:decimal (bps-cut (at 'bps proto)))
                 ;; the CREATION VENUE leg: primary rate when the seller is the
                 ;; author, resale rate otherwise (ADR-NFT-011)
                 (cv (get-creation-venue (at 'id token)))
                 (cv-fee:decimal (bps-cut (creation-venue-bps (at 'id token) seller (at 'author token))))
                 ;; the LISTING VENUE leg, optionally split with the venue that
                 ;; brought the buyer (named in the buy tx; it can only RECEIVE
                 ;; the share the seller's quote already granted)
                 (fee:decimal (bps-cut fee-bps))
                 (buyer-venue-id:string (try "" (read-string BUYER-VENUE-KEY)))
                 (share:decimal (if (and (> share-bps 0) (!= "" buyer-venue-id)) (bps-cut share-bps) 0.0))
                 (listing-fee:decimal (- fee share))
                 (cuts-total:decimal (fold (+) 0.0 (map (at 'amount) policy-payouts)))
                 (proceeds:decimal (- price (+ protocol (+ cv-fee (+ cuts-total fee))))))
            (enforce (>= proceeds 0.0) "protocol + venues + policy cuts exceed the price")
            ;; the full payout set, in commitment order: protocol -> creation
            ;; venue -> policy cuts -> listing venue (split) -> seller remainder
            (let* ((protocol-leg (if (> protocol 0.0) [{ 'account: (at 'account proto), 'guard: (at 'guard proto), 'amount: protocol }] []))
                   (cv-leg (if (> cv-fee 0.0) [{ 'account: (at 'account cv), 'guard: (at 'guard cv), 'amount: cv-fee }] []))
                   (fee-leg (if (> listing-fee 0.0) [{ 'account: fee-account, 'guard: fee-guard, 'amount: listing-fee }] []))
                   (share-leg (if (> share 0.0)
                                (let ((bv (venue-registry.get-venue buyer-venue-id)))
                                  [{ 'account: (at 'account bv), 'guard: (at 'guard bv), 'amount: share }])
                                []))
                   (seller-leg (if (> proceeds 0.0) [{ 'account: seller-account, 'guard: seller-guard, 'amount: proceeds }] []))
                   (raw (+ protocol-leg (+ cv-leg (+ policy-payouts (+ fee-leg (+ share-leg seller-leg))))))
                   (merged (fold (merge-payout) [] raw)))
              ;; INTERACTION 2: pay every leg from the escrow, once each
              (with-capability (ESCROW sale-id)
                (map (pay-from-escrow fungible sale-id) merged)))
            ;; CONSERVATION: exactly `price` left the escrow (dust-robust)
            (let ((final (fungible::get-balance escrow)))
              (enforce (= final (- funded price)) "escrow not fully settled — conservation failed"))
            (emit-event (SETTLED sale-id price protocol cv-fee fee proceeds)))))
      ;; the sale defpact completes on this step — record it (see SALE LIVENESS)
      (update quotes sale-id { 'active: false })
      true))

  ;; --- payout helpers (the merged, conservation-safe settlement) --------------
  (defun merge-payout:[object] (acc:[object] p:object)
    @doc "Merge P into ACC, summing amounts for a payee that already appears so \
         \no two legs collide on the managed-transfer install; drops zero legs."
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

  (defun pay-from-escrow:string (fungible:module{fungible-v2} sale-id:string p:object)
    @doc "Pay one merged leg from the sale escrow. Requires ESCROW in scope. \
         \THIS IS THE ONE PATH EVERY PAYOUT TAKES — the seller's proceeds, the \
         \marketplace fee and every policy cut — so the destination check \
         \belongs here rather than at any caller. A payee principal is as \
         \publicly computable as an escrow's (a creator's k: account is just \
         \their public key), so on a non-conforming fungible a stranger can \
         \hold the name first and be paid instead. That loss lands on someone \
         \who did not act in this transaction — the royalty creator is not a \
         \party to the sale — so the module refuses rather than leaving it to \
         \them. Refusing turns a silent theft into an aborted sale, which is \
         \a state the seller can see and act on."
    (require-capability (ESCROW sale-id))
    (let ((escrow (escrow-account sale-id)))
      (install-capability (fungible::TRANSFER escrow (at 'account p) (at 'amount p)))
      (let ((res (fungible::transfer-create escrow (at 'account p) (at 'guard p) (at 'amount p))))
        (enforce-account-custody fungible (at 'account p) (at 'guard p))
        res)))

  ;; --- destination-account integrity -------------------------------------------
  (defun enforce-account-custody:bool (fungible:module{fungible-v2} account:string expected:guard)
    @doc "POST-CONDITION on a transfer this module just made: ACCOUNT must be \
         \held in FUNGIBLE under exactly EXPECTED. Call it AFTER the \
         \transfer-create, never before. \
         \WHY AFTER, AND WHY NO `try`. Every destination here — both escrows \
         \and every payout leg — has a principal computable from the \
         \mempool-visible offer, so on a fungible that does not enforce \
         \reserved account-name protocols (coin does; fungible-v2 requires \
         \nothing) a stranger can create it first under their OWN guard. The \
         \obvious shape, a `try`-guarded read BEFORE the transfer so that a \
         \not-yet-created account passes, is FAIL-OPEN and cannot be made \
         \safe: `try` yields its catch expression on ANY execution error \
         \(Pact/Core/IR/Eval/CEK/Evaluator.hs, CTry -> CEKHandler), so if the \
         \catch value is the guard we are about to require, a fungible whose \
         \`details` merely throws passes the check — and \"the fungible does \
         \not conform\" is this check's entire threat model. Reading AFTER the \
         \transfer needs no `try` at all: the account now exists, so a throw \
         \is a real fault and aborts the transaction. \
         \Nothing is lost by refusing late: an abort rolls the whole \
         \transaction back, so the money never moved. This is a refusal, not \
         \a reversal."
    (let ((actual:guard (at 'guard (fungible::details account))))
      (enforce (= actual expected)
        "destination account is squatted: its on-chain guard is not the one declared"))
    true)

  ;; --- views ------------------------------------------------------------------
  (defun get-quote:object{quote-schema} (sale-id:string) (read quotes sale-id))
  (defun get-quote-price:decimal (sale-id:string) (at 'price (read quotes sale-id)))

  (defun sale-live:bool (sale-id:string)
    @doc "True while the ledger's sale defpact for SALE-ID can still be bought \
         \or withdrawn; false once it has settled or been withdrawn. This is \
         \the ONLY readable answer to that question (see SALE LIVENESS) — a \
         \bidder should check it before escrowing anything."
    (at 'active (read quotes sale-id)))

  (defun enforce-sale-live:bool (sale-id:string)
    @doc "Abort unless SALE-ID's sale defpact is still live. Registered sale \
         \contracts gate every obligation- and escrow-taking entry point on \
         \this."
    (let ((live:bool (sale-live sale-id)))
      (enforce live "the sale is no longer live"))
    true)
)
