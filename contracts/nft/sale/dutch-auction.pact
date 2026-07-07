;; nft.dutch-auction — declining-price (Dutch) auction as a registered sale
;; contract for the nft framework.
;;
;; The seller offers the token through the ledger's sale pact with a quote
;; naming this contract (price 0 — discovered here), then creates the auction:
;; a start price stepping DOWN to a floor price over fixed intervals. The
;; first buyer to settle at the current interval price wins; there is no bid
;; escrow — the buyer pays from their own fungible account exactly like a
;; fixed-price sale, and the framework's single conservation-asserted
;; settlement carves the quote-bound royalties and marketplace fee from the
;; accepted price (a Dutch sale is not a royalty bypass).
;;
;; PRICE INTEGRITY: the buy transaction carries only a CANDIDATE price; the
;; manager dispatches it to enforce-quote-update here, which enforces it
;; EQUALS the current curve price for the executing block. The price is
;; constant within an interval, so an honest buyer's candidate matches
;; deterministically; nothing about the price can be injected.
;;
;; The curve is monotonically non-increasing: each full elapsed interval
;; drops the price by (start-price - floor-price)/intervals, quantized to the
;; quote fungible's precision, never below the floor. Purchasable only inside
;; [start, end); withdrawal is free before start, blocked while live, free
;; after end if unsold (nothing is ever escrowed here, so no funds can
;; strand).
;;
;; The settlement hooks are unreachable outside the manager's path (they
;; require the manager's QUOTE-CALL / WITHDRAWAL-CALL capabilities).

(namespace (read-string 'ns))

(module dutch-auction GOVERNANCE
  @doc "Declining-price auction sale contract for the nft framework: interval-\
       \stepped price curve from start-price down to floor-price, first \
       \settlement at the current price wins."

  (implements sale)

  (defconst ADMIN-KS:string (read-string 'admin-ks)
    @doc "Admin keyset name, captured ONCE at deploy — never read from a \
         \caller's payload at enforcement time. Governance upgrades the \
         \module and nothing else: auctions belong to their sellers.")

  (defcap GOVERNANCE ()
    (enforce-keyset ADMIN-KS))

  (defconst SELF-NAME:string (format "{}.dutch-auction" [(read-string 'ns)])
    @doc "This contract's fully-qualified name, captured at deploy — the name \
         \a quote must carry to route its sale here.")

  (defschema auction
    @doc "One auction per sale-id. Times are unix seconds; the price steps \
         \down once per interval-seconds from start-price to floor-price."
    token-id:string
    start:integer
    end:integer
    start-price:decimal
    floor-price:decimal
    interval-seconds:integer)
  (deftable auctions:{auction})

  (defcap AUCTION-CREATED:bool (sale-id:string token-id:string start-price:decimal floor-price:decimal start:integer end:integer interval-seconds:integer)
    @event true)
  (defcap AUCTION-UPDATED:bool (sale-id:string start-price:decimal floor-price:decimal start:integer end:integer interval-seconds:integer)
    @event true)

  (defcap MANAGE-AUCTION:bool (sale-id:string)
    @doc "The seller manages their auction: authorized by the seller-guard \
         \bound in the sale's quote."
    (let ((q (policy-manager.get-quote sale-id)))
      (enforce-guard (at 'seller-guard q))))

  ;; --- views -------------------------------------------------------------------
  (defun get-auction:object{auction} (sale-id:string)
    (read auctions sale-id))

  (defun curr-time:integer ()
    (round (diff-time (at 'block-time (chain-data)) (time "1970-01-01T00:00:00Z"))))

  (defun current-price:decimal (sale-id:string)
    @doc "The curve price for the CURRENT block time: start-price minus one \
         \equal step per full elapsed interval, quantized to the quote \
         \fungible's precision, clamped to the floor. Fails outside \
         \[start, end)."
    (with-read auctions sale-id
      { 'start := start, 'end := end, 'start-price := start-price
      , 'floor-price := floor-price, 'interval-seconds := interval }
      (let ((now (curr-time)))
        (enforce (>= now start) "auction has not started")
        (enforce (< now end) "auction has ended")
        (let* ((q (policy-manager.get-quote sale-id))
               (fungible:module{fungible-v2} (at 'fungible q))
               (prec:integer (fungible::precision))
               (total-intervals:integer (/ (- end start) interval))
               (elapsed-intervals:integer (/ (- now start) interval))
               (price-step:decimal (if (> total-intervals 0)
                                       (/ (- start-price floor-price) (dec total-intervals))
                                       0.0))
               (raw:decimal (- start-price (* (dec elapsed-intervals) price-step)))
               (quantized:decimal (floor raw prec)))
          (if (< quantized floor-price) floor-price quantized)))))

  ;; --- auction lifecycle (seller-driven) ----------------------------------------
  (defun validate-schedule:bool (start:integer end:integer start-price:decimal floor-price:decimal interval-seconds:integer)
    (enforce (> start (curr-time)) "start must be in the future")
    (enforce (> end start) "end must be after start")
    (enforce (> floor-price 0.0) "floor price must be positive")
    (enforce (> start-price floor-price) "start price must exceed the floor price")
    (enforce (> interval-seconds 0) "interval must be positive")
    (enforce (>= (- end start) interval-seconds) "duration must cover at least one interval"))

  (defun create-auction:bool
    ( sale-id:string token-id:string start:integer end:integer
      start-price:decimal floor-price:decimal interval-seconds:integer )
    @doc "Attach a Dutch auction to an offered sale. Seller-only; the sale's \
         \quote must name THIS contract and carry the 0 discovery price."
    (with-capability (MANAGE-AUCTION sale-id)
      (validate-schedule start end start-price floor-price interval-seconds)
      (let ((q (policy-manager.get-quote sale-id)))
        (enforce (= 0.0 (at 'price q)) "quote price must be 0 (discovered here)")
        (enforce (= (at 'sale-contract q) SELF-NAME)
          "the quote does not name this sale contract")
        (enforce (= token-id (at 'token-id q)) "token-id does not match the quote")
        (let ((fungible:module{fungible-v2} (at 'fungible q)))
          (fungible::enforce-unit start-price)
          (fungible::enforce-unit floor-price)))
      (insert auctions sale-id
        { 'token-id: token-id, 'start: start, 'end: end
        , 'start-price: start-price, 'floor-price: floor-price
        , 'interval-seconds: interval-seconds })
      (emit-event (AUCTION-CREATED sale-id token-id start-price floor-price start end interval-seconds)))
    true)

  (defun update-auction:bool
    ( sale-id:string start:integer end:integer
      start-price:decimal floor-price:decimal interval-seconds:integer )
    @doc "Reschedule/reprice an auction BEFORE it starts. Seller-only."
    (with-capability (MANAGE-AUCTION sale-id)
      (validate-schedule start end start-price floor-price interval-seconds)
      (with-read auctions sale-id { 'start := curr-start }
        (enforce (> curr-start (curr-time)) "auction already started"))
      (update auctions sale-id
        { 'start: start, 'end: end, 'start-price: start-price
        , 'floor-price: floor-price, 'interval-seconds: interval-seconds })
      (emit-event (AUCTION-UPDATED sale-id start-price floor-price start end interval-seconds)))
    true)

  ;; --- sale interface (manager-gated settlement hooks) --------------------------
  (defun enforce-quote-update:bool (sale-id:string price:decimal)
    @doc "Settlement validation: the candidate price must EQUAL the current \
         \curve price (current-price itself enforces the [start, end) window). \
         \Any buyer may settle; they pay from their own account."
    (require-capability (policy-manager.QUOTE-CALL sale-id price))
    (let ((current:decimal (current-price sale-id)))
      (enforce (= price current) "price does not match the current curve price"))
    true)

  (defun enforce-withdrawal:bool (sale-id:string)
    @doc "Withdrawal consent. No auction row -> free. Before start -> free. \
         \Live -> refused (buyers are relying on the posted curve). After end \
         \unsold -> free. Nothing is escrowed here, so no refund is owed."
    (require-capability (policy-manager.WITHDRAWAL-CALL sale-id))
    (with-default-read auctions sale-id
      { 'start: -1, 'end: -1 }
      { 'start := start, 'end := end }
      (if (= end -1)
        true
        (let ((now (curr-time)))
          (enforce (or (< now start) (>= now end))
            "auction is live — cannot withdraw"))))
    true)
)
