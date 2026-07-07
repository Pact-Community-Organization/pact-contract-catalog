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

  ;; --- the quote: sale economics, bound at OFFER, read at BUY -----------------
  (defschema quote-spec
    @doc "What the seller signs at offer. All economics live HERE (state), never \
         \in the buy tx. fee-account/fee-guard/fee-bps are the marketplace fee \
         \the seller agreed to by signing the offer."
    fungible:module{fungible-v2}
    price:decimal
    seller-account:string
    seller-guard:guard
    fee-account:string
    fee-guard:guard
    fee-bps:integer)

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
    fee-bps:integer)
  (deftable quotes:{quote-schema})

  (defconst QUOTE-MSG-KEY:string "quote"
    @doc "Offer-tx payload key carrying the quote-spec (SELLER's tx — safe).")
  (defconst BUYER-ACCT-KEY:string "buyer_fungible_account"
    @doc "Buy-tx payload key: the buyer's OWN paying account (not economics).")

  (defcap QUOTE:bool (sale-id:string token-id:string price:decimal fee-bps:integer) @event true)
  (defcap SETTLED:bool (sale-id:string price:decimal fee:decimal proceeds:decimal) @event true)

  ;; --- the fungible escrow (one per sale-id, capability-guarded) --------------
  (defcap ESCROW:bool (sale-id:string)
    @doc "Spend authority over the sale's fungible escrow. Acquired ONLY inside \
         \this manager's single settlement routine."
    true)
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
        , 'fee-bps: (at 'fee-bps q) })
      (emit-event (QUOTE sale-id (at 'id token) (at 'price q) (at 'fee-bps q))))
    ;; run policy enforce-offer hooks
    (map (lambda (p:module{token-policy}) (p::enforce-offer token seller amount timeout sale-id)) (at 'policies token))
    true)

  (defun validate-quote:bool (q:object{quote-spec})
    (let ((fungible:module{fungible-v2} (at 'fungible q))
          (price:decimal (at 'price q))
          (fee-bps:integer (at 'fee-bps q)))
      (enforce (> price 0.0) "price must be positive")
      (fungible::enforce-unit price)
      (enforce (and (>= fee-bps 0) (<= fee-bps MAX-FEE-BPS))
        (format "fee-bps must be in [0, {}]" [MAX-FEE-BPS]))
      (enforce (validate-principal (at 'seller-guard q) (at 'seller-account q))
        "seller-account must be a principal")
      (if (> fee-bps 0)
        (enforce (validate-principal (at 'fee-guard q) (at 'fee-account q))
          "fee-account must be a principal when a fee is charged")
        true)))

  ;; --- WITHDRAW: no fungible moved (the NFT returns via the ledger) -----------
  (defun enforce-withdraw:bool (token:object{token-info} seller:string amount:decimal timeout:integer sale-id:string)
    (let ((l:module{ledger-iface} (retrieve-ledger)))
      (require-capability (l::WITHDRAW-CALL (at 'id token) seller amount timeout sale-id)))
    (map (lambda (p:module{token-policy}) (p::enforce-withdraw token seller amount timeout sale-id)) (at 'policies token))
    true)

  ;; --- BUY: the SINGLE conservation-asserted settlement -----------------------
  (defun enforce-buy:bool (token:object{token-info} seller:string buyer:string buyer-guard:guard amount:decimal sale-id:string)
    (let ((l:module{ledger-iface} (retrieve-ledger)))
      (require-capability (l::BUY-CALL (at 'id token) seller buyer amount sale-id)))
    (with-read quotes sale-id
      { 'fungible := fungible:module{fungible-v2}, 'price := price
      , 'seller-account := seller-account, 'seller-guard := seller-guard
      , 'fee-account := fee-account, 'fee-guard := fee-guard, 'fee-bps := fee-bps }
      (let ((prec (fungible::precision))
            (escrow (escrow-account sale-id))
            (buyer-account:string (read-msg BUYER-ACCT-KEY)))  ;; buyer's OWN account
        ;; INTERACTION 1: buyer funds the escrow with EXACTLY the state price.
        (fungible::transfer-create buyer-account escrow (escrow-guard sale-id) price)
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
