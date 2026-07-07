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
;; Quote rows are permanent: a settled or withdrawn sale keeps its quote row
;; (Pact has no row deletion; the one-shot sale defpact steps make replay
;; impossible). Treat `quotes` as the immutable sale-economics history.

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
  (defconst MAX-FEE-BPS:integer 1000
    @doc "Cap on the marketplace fee a quote may set: 10%.")

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

  ;; --- registered updatable-uri handlers (permissionless, type-verified) ------
  ;; Pact has no on-chain interface introspection, so an updatable-uri policy
  ;; REGISTERS itself: the parameter type makes the runtime verify the module
  ;; implements BOTH token-policy and updatable-uri-policy, and the key is
  ;; derived from the modref itself — registration cannot lie about identity.
  ;; An updatable-uri implementation only participates in update-uri routing
  ;; once registered (the framework's own uri policies are registered at
  ;; deploy; third-party policies self-register with one call).
  (defschema uri-handler-ref
    handler-name:string   ;; mirrors the row key; "" is the never-stored sentinel
    handler:module{updatable-uri-policy})
  (deftable uri-handlers:{uri-handler-ref})

  (defun register-uri-handler:bool (handler:module{token-policy,updatable-uri-policy})
    @doc "Self-registration for a policy that gates uri updates. Permissionless \
         \and safe: the type check proves the implementation, the derived key \
         \proves the identity."
    (let ((k:string (format "{}" [handler])))
      (enforce (!= "" k) "handler name required")
      (insert uri-handlers k { 'handler-name: k, 'handler: handler }))
    true)

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
    fee-account:string
    fee-guard:guard
    fee-bps:integer
    sale-contract:string)

  (defschema quote-schema
    token-id:string
    seller:string
    amount:decimal
    fungible:module{fungible-v2}
    price:decimal
    seller-account:string
    seller-guard:guard
    fee-account:string
    fee-guard:guard
    fee-bps:integer
    sale-contract:string)
  (deftable quotes:{quote-schema})

  (defconst QUOTE-MSG-KEY:string "quote"
    @doc "Offer-tx payload key carrying the quote-spec (SELLER's tx — safe).")
  (defconst BUYER-ACCT-KEY:string "buyer_fungible_account"
    @doc "Buy-tx payload key: the buyer's OWN paying account (not economics).")
  (defconst QUOTED-PRICE-MSG-KEY:string "quoted_price"
    @doc "Buy-tx payload key for a quoted sale: the CANDIDATE final price. It \
         \is only a carrier — the sale contract must validate it against its \
         \own on-chain state (recorded bids / the price curve) before the \
         \manager binds and settles it.")

  (defcap QUOTE:bool (sale-id:string token-id:string price:decimal fee-bps:integer sale-contract:string) @event true)
  (defcap SETTLED:bool (sale-id:string price:decimal fee:decimal proceeds:decimal) @event true)

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
    (map (lambda (p:module{token-policy})
           { 'policy: (format "{}" [p])
           , 'state: (p::enforce-xchain-send token sender receiver receiver-guard target-chain amount) })
         (at 'policies token)))

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
    true)

  ;; --- UPDATE-URI: fail closed — immutable unless a registered handler permits
  (defun enforce-update-uri:bool (token:object{token-info} new-uri:string)
    @doc "Dispatches the uri update to every attached policy that is a \
         \REGISTERED updatable-uri handler. No handler attached -> the uri is \
         \immutable (reject). Every dispatched handler must pass, so one veto \
         \(e.g. non-updatable-uri-policy) is final regardless of the stack."
    (let ((l:module{ledger-iface} (retrieve-ledger)))
      (require-capability (l::UPDATE-URI-CALL (at 'id token) new-uri)))
    (let ((handled:integer
            (fold (lambda (n:integer p:module{token-policy})
                    (let ((k:string (format "{}" [p])))
                      (with-default-read uri-handlers k
                        { 'handler-name: "" } { 'handler-name := hn }
                        (if (= "" hn)
                          n
                          (with-read uri-handlers k { 'handler := h:module{updatable-uri-policy} }
                            (h::enforce-update-uri token new-uri)
                            (+ n 1))))))
                  0 (at 'policies token))))
      (enforce (> handled 0) "the token uri is immutable (no updatable-uri policy attached)"))
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
    ;; the quote comes from the SELLER's offer tx and is STORED (not the buyer's)
    (let ((q:object{quote-spec} (read-msg QUOTE-MSG-KEY)))
      (validate-quote q)
      (insert quotes sale-id
        { 'token-id: (at 'id token), 'seller: seller, 'amount: amount
        , 'fungible: (at 'fungible q), 'price: (at 'price q)
        , 'seller-account: (at 'seller-account q), 'seller-guard: (at 'seller-guard q)
        , 'fee-account: (at 'fee-account q), 'fee-guard: (at 'fee-guard q)
        , 'fee-bps: (at 'fee-bps q), 'sale-contract: (at 'sale-contract q) })
      (emit-event (QUOTE sale-id (at 'id token) (at 'price q) (at 'fee-bps q) (at 'sale-contract q))))
    ;; run policy enforce-offer hooks
    (map (lambda (p:module{token-policy}) (p::enforce-offer token seller amount timeout sale-id)) (at 'policies token))
    true)

  (defun validate-quote:bool (q:object{quote-spec})
    (let ((fungible:module{fungible-v2} (at 'fungible q))
          (price:decimal (at 'price q))
          (fee-bps:integer (at 'fee-bps q))
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
      (enforce (and (>= fee-bps 0) (<= fee-bps MAX-FEE-BPS))
        (format "fee-bps must be in [0, {}]" [MAX-FEE-BPS]))
      (enforce (validate-principal (at 'seller-guard q) (at 'seller-account q))
        "seller-account must be a principal")
      (if (> fee-bps 0)
        (enforce (validate-principal (at 'fee-guard q) (at 'fee-account q))
          "fee-account must be a principal when a fee is charged")
        true)))

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
    true)

  ;; --- BUY: the SINGLE conservation-asserted settlement -----------------------
  (defun enforce-buy:bool (token:object{token-info} seller:string buyer:string buyer-guard:guard amount:decimal sale-id:string)
    (let ((l:module{ledger-iface} (retrieve-ledger)))
      (require-capability (l::BUY-CALL (at 'id token) seller buyer amount sale-id)))
    (with-read quotes sale-id
      { 'fungible := fungible:module{fungible-v2}, 'price := stored-price
      , 'seller-account := seller-account, 'seller-guard := seller-guard
      , 'fee-account := fee-account, 'fee-guard := fee-guard, 'fee-bps := fee-bps
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
        (let ((funded (fungible::get-balance escrow)))
          ;; policies DECLARE their cuts (computed from their own state); they
          ;; move no money. (Phase 3's royalty policy returns the creator's cut.)
          (let* ((policy-payouts:[object{payout}]
                   (fold (lambda (acc:[object{payout}] pol:module{token-policy})
                           (+ acc (pol::enforce-buy token seller buyer buyer-guard amount sale-id)))
                         [] (at 'policies token)))
                 (fee:decimal (if (> fee-bps 0) (floor (/ (* price (dec fee-bps)) (dec BPS-DENOM)) prec) 0.0))
                 (cuts-total:decimal (fold (+) 0.0 (map (at 'amount) policy-payouts)))
                 (proceeds:decimal (- price (+ cuts-total fee))))
            (enforce (>= proceeds 0.0) "policy cuts + fee exceed the price")
            ;; the full payout set: policy cuts + marketplace fee + seller remainder
            (let* ((fee-leg (if (> fee 0.0) [{ 'account: fee-account, 'guard: fee-guard, 'amount: fee }] []))
                   (seller-leg [{ 'account: seller-account, 'guard: seller-guard, 'amount: proceeds }])
                   (raw (+ policy-payouts (+ fee-leg seller-leg)))
                   (merged (fold (merge-payout) [] raw)))
              ;; INTERACTION 2: pay every leg from the escrow, once each
              (with-capability (ESCROW sale-id)
                (map (pay-from-escrow fungible sale-id) merged)))
            ;; CONSERVATION: exactly `price` left the escrow (dust-robust)
            (let ((final (fungible::get-balance escrow)))
              (enforce (= final (- funded price)) "escrow not fully settled — conservation failed"))
            (emit-event (SETTLED sale-id price fee proceeds)))))
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
    @doc "Pay one merged leg from the sale escrow. Requires ESCROW in scope."
    (require-capability (ESCROW sale-id))
    (let ((escrow (escrow-account sale-id)))
      (install-capability (fungible::TRANSFER escrow (at 'account p) (at 'amount p)))
      (fungible::transfer-create escrow (at 'account p) (at 'guard p) (at 'amount p))))

  ;; --- views ------------------------------------------------------------------
  (defun get-quote:object{quote-schema} (sale-id:string) (read quotes sale-id))
  (defun get-quote-price:decimal (sale-id:string) (at 'price (read quotes sale-id)))
)
