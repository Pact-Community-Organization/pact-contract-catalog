;; nft.conventional-auction — ascending-bid auction as a registered sale
;; contract for the nft framework.
;;
;; The seller offers the token through the ledger's sale pact with a quote
;; naming this contract (price 0 — discovered here), then creates the auction
;; with its schedule and economics. Bidders escrow their bids in a per-sale
;; bid escrow owned by THIS contract; each higher bid refunds the previous
;; bidder in full. At settlement the policy-manager pulls exactly the winning
;; bid from the bid escrow (the escrow's guard requires the manager's
;; FUNDING-CALL for this sale) and runs the framework's single
;; conservation-asserted settlement — royalties and the marketplace fee bound
;; in the quote are carved from the winning bid like any other sale; an
;; auction is not a royalty bypass.
;;
;; PRICE INTEGRITY: the buy transaction carries only a CANDIDATE price; the
;; manager dispatches it to enforce-quote-update here, which enforces it
;; EQUALS the recorded highest bid, that the auction has ended, and that the
;; named buyer IS the recorded highest bidder. Nothing about the price or the
;; winner can be injected.
;;
;; WITHDRAWAL (the no-locked-funds rule): while the auction is live, or ended
;; with a winner still inside the settlement grace window, withdrawal is
;; refused. Ended with no bids -> withdrawal free. Ended with a winner but
;; unsettled past the grace window (e.g. a settlement made impossible by a
;; policy, or an absent winner) -> withdrawal is permitted AND this contract
;; refunds the winner's escrowed bid first, so no path strands funds. The
;; grace window is auction state every bidder can read before bidding.
;;
;; The settlement hooks are unreachable outside the manager's path (they
;; require the manager's QUOTE-CALL / WITHDRAWAL-CALL capabilities).

(namespace (read-string 'ns))

(module conventional-auction GOVERNANCE
  @doc "Ascending-bid auction sale contract for the nft framework: escrowed \
       \bids, increment-enforced outbidding with full refunds, winner-only \
       \state-validated settlement, grace-windowed withdrawal."

  (implements sale)

  (defconst ADMIN-KS:string (read-string 'admin-ks)
    @doc "Admin keyset name, captured ONCE at deploy — never read from a \
         \caller's payload at enforcement time. Governance upgrades the \
         \module and nothing else: auctions belong to their sellers.")

  (defcap GOVERNANCE ()
    (enforce-keyset ADMIN-KS))

  (defconst SELF-NAME:string (format "{}.conventional-auction" [(read-string 'ns)])
    @doc "This contract's fully-qualified name, captured at deploy — the name \
         \a quote must carry to route its sale here.")

  (defschema auction
    @doc "One auction per sale-id. Times are unix seconds. highest-bid 0 = \
         \no bids yet. settlement-grace is the winner's exclusive window (in \
         \seconds after end) before the seller may withdraw with a refund."
    token-id:string
    start:integer
    end:integer
    reserve:decimal
    increment:decimal
    settlement-grace:integer
    highest-bid:decimal
    bidder:string
    bidder-guard:guard)
  (deftable auctions:{auction})

  (defcap AUCTION-CREATED:bool (sale-id:string token-id:string reserve:decimal increment:decimal start:integer end:integer)
    @event true)
  (defcap AUCTION-UPDATED:bool (sale-id:string reserve:decimal increment:decimal start:integer end:integer)
    @event true)
  (defcap BID:bool (sale-id:string bidder:string bid:decimal)
    @event true)
  (defcap BID-REFUNDED:bool (sale-id:string bidder:string amount:decimal)
    @event true)

  (defcap MANAGE-AUCTION:bool (sale-id:string)
    @doc "The seller manages their auction: authorized by the seller-guard \
         \bound in the sale's quote (this module's own read of manager state)."
    (let ((q (policy-manager.get-quote sale-id)))
      (enforce-guard (at 'seller-guard q))))

  (defcap PLACE-BID:bool (bidder-guard:guard)
    @doc "The bidder proves control of the guard their refund goes back to."
    (enforce-guard bidder-guard))

  (defcap REFUND:bool (sale-id:string)
    @doc "Internal refund token. Weak body by design: acquired only around \
         \this module's own refund transfers out of the bid escrow (outbid, \
         \or a grace-window withdrawal); never acquirable externally."
    true)

  ;; --- the bid escrow (one per sale-id) ----------------------------------------
  ;; Its guard passes in exactly two dynamic contexts: this module refunding
  ;; (REFUND in scope) and the manager pulling the winning bid at settlement
  ;; (FUNDING-CALL in scope). Both checks are scope tests, not acquisitions.
  (defun bid-escrow-auth:bool (sale-id:string)
    (enforce (or (try false (require-capability (REFUND sale-id)))
                 (try false (require-capability (policy-manager.FUNDING-CALL sale-id))))
      "bid escrow: unauthorized"))

  (defun bid-escrow-guard:guard (sale-id:string)
    (create-user-guard (bid-escrow-auth sale-id)))

  (defun bid-escrow-account:string (sale-id:string)
    (create-principal (bid-escrow-guard sale-id)))

  ;; --- views -------------------------------------------------------------------
  (defun get-auction:object{auction} (sale-id:string)
    (read auctions sale-id))

  (defun curr-time:integer ()
    (round (diff-time (at 'block-time (chain-data)) (time "1970-01-01T00:00:00Z"))))

  ;; --- auction lifecycle (seller-driven) ----------------------------------------
  (defun validate-schedule:bool (start:integer end:integer reserve:decimal increment:decimal settlement-grace:integer)
    (enforce (> start (curr-time)) "start must be in the future")
    (enforce (> end start) "end must be after start")
    (enforce (> reserve 0.0) "reserve must be positive")
    (enforce (> increment 0.0) "increment must be positive")
    (enforce (>= settlement-grace 0) "settlement grace must be >= 0"))

  (defun create-auction:bool
    ( sale-id:string token-id:string start:integer end:integer
      reserve:decimal increment:decimal settlement-grace:integer )
    @doc "Attach an auction to an offered sale. Seller-only; the sale's quote \
         \must name THIS contract and carry the 0 discovery price."
    (with-capability (MANAGE-AUCTION sale-id)
      (validate-schedule start end reserve increment settlement-grace)
      (let ((q (policy-manager.get-quote sale-id)))
        (enforce (= 0.0 (at 'price q)) "quote price must be 0 (discovered here)")
        (enforce (= (at 'sale-contract q) SELF-NAME)
          "the quote does not name this sale contract")
        (enforce (= token-id (at 'token-id q)) "token-id does not match the quote")
        (let ((fungible:module{fungible-v2} (at 'fungible q)))
          (fungible::enforce-unit reserve)
          (fungible::enforce-unit increment)))
      (insert auctions sale-id
        { 'token-id: token-id, 'start: start, 'end: end
        , 'reserve: reserve, 'increment: increment
        , 'settlement-grace: settlement-grace
        , 'highest-bid: 0.0, 'bidder: "", 'bidder-guard: (bid-escrow-guard sale-id) })
      (emit-event (AUCTION-CREATED sale-id token-id reserve increment start end)))
    true)

  (defun update-auction:bool
    ( sale-id:string start:integer end:integer
      reserve:decimal increment:decimal settlement-grace:integer )
    @doc "Reschedule/reprice an auction BEFORE it starts. Seller-only."
    (with-capability (MANAGE-AUCTION sale-id)
      (validate-schedule start end reserve increment settlement-grace)
      (with-read auctions sale-id { 'start := curr-start }
        (enforce (> curr-start (curr-time)) "auction already started"))
      (update auctions sale-id
        { 'start: start, 'end: end, 'reserve: reserve
        , 'increment: increment, 'settlement-grace: settlement-grace })
      (emit-event (AUCTION-UPDATED sale-id reserve increment start end)))
    true)

  ;; --- bidding -------------------------------------------------------------------
  (defun place-bid:bool (sale-id:string bidder:string bidder-guard:guard bid:decimal)
    @doc "Escrow BID for SALE-ID. Must be inside the window, at least the \
         \reserve, and at least increment above the previous bid; the previous \
         \bidder is refunded in full first. Principal bidders only (the \
         \refund target must be un-squattable)."
    (with-read auctions sale-id
      { 'start := start, 'end := end, 'reserve := reserve
      , 'increment := increment, 'highest-bid := prev-bid, 'bidder := prev-bidder }
      (enforce (>= (curr-time) start) "auction has not started")
      (enforce (< (curr-time) end) "auction has ended")
      (enforce (>= bid reserve) "bid below the reserve price")
      (if (> prev-bid 0.0)
        (enforce (>= bid (+ prev-bid increment)) "bid below the required increment")
        true)
      (enforce (validate-principal bidder-guard bidder) "bidder must be a principal account")
      (let* ((q (policy-manager.get-quote sale-id))
             (fungible:module{fungible-v2} (at 'fungible q)))
        (fungible::enforce-unit bid)
        (with-capability (PLACE-BID bidder-guard)
          ;; refund the previous bidder in full before accepting the new bid
          (if (> prev-bid 0.0)
            (with-capability (REFUND sale-id)
              (refund-escrow sale-id fungible prev-bidder))
            true)
          ;; escrow the new bid with this module's per-sale guard
          (fungible::transfer-create bidder (bid-escrow-account sale-id) (bid-escrow-guard sale-id) bid)
          (update auctions sale-id
            { 'highest-bid: bid, 'bidder: bidder, 'bidder-guard: bidder-guard })
          (emit-event (BID sale-id bidder bid)))))
    true)

  (defun refund-escrow:bool (sale-id:string fungible:module{fungible-v2} to:string)
    @doc "Return the FULL bid-escrow balance to TO. Internal only: callable \
         \solely inside a REFUND scope this module itself acquired (outbid \
         \refund, grace-window withdrawal refund)."
    (require-capability (REFUND sale-id))
    (let ((escrow (bid-escrow-account sale-id)))
      (let ((bal (fungible::get-balance escrow)))
        (if (> bal 0.0)
          (let ((_ (install-capability (fungible::TRANSFER escrow to bal))))
            (fungible::transfer escrow to bal)
            (emit-event (BID-REFUNDED sale-id to bal)))
          true)))
    true)

  ;; --- sale interface (manager-gated settlement hooks) --------------------------
  (defun enforce-quote-update:bool (sale-id:string price:decimal)
    @doc "Settlement validation: the auction ended, the candidate price IS the \
         \recorded highest bid, and the buy names the recorded winner. The \
         \manager pulls the funds from this contract's bid escrow."
    (require-capability (policy-manager.QUOTE-CALL sale-id price))
    (with-read auctions sale-id
      { 'end := end, 'highest-bid := highest-bid
      , 'bidder := bidder, 'bidder-guard := bidder-guard }
      (enforce (>= (curr-time) end) "auction is still ongoing")
      (enforce (> highest-bid 0.0) "no bids were placed")
      (enforce (= price highest-bid) "price does not match the winning bid")
      (let ((buyer:string (read-msg "buyer"))
            (buyer-guard:guard (read-msg "buyer-guard"))
            (paying:string (read-msg "buyer_fungible_account")))
        (enforce (= buyer bidder) "buyer is not the winning bidder")
        (enforce (= buyer-guard bidder-guard) "buyer-guard is not the winning bidder's")
        (enforce (= paying (bid-escrow-account sale-id))
          "the paying account must be this auction's bid escrow")))
    true)

  (defun enforce-withdrawal:bool (sale-id:string)
    @doc "Withdrawal consent. No auction row -> free (nothing at stake). Live \
         \-> refused. Ended, no bids -> free. Ended with a winner -> refused \
         \during the settlement grace window; after it, permitted WITH the \
         \winner's escrowed bid refunded first (no path strands funds)."
    (require-capability (policy-manager.WITHDRAWAL-CALL sale-id))
    (with-default-read auctions sale-id
      { 'end: -1, 'highest-bid: 0.0, 'settlement-grace: 0, 'bidder: "" }
      { 'end := end, 'highest-bid := highest-bid
      , 'settlement-grace := grace, 'bidder := bidder }
      (if (= end -1)
        true
        (let ((now (curr-time)))
          (enforce (>= now end) "auction is still ongoing")
          (if (> highest-bid 0.0)
            (let ((deadline (+ end grace)))
              (enforce (> now deadline)
                "the winner's settlement grace window is still open")
              (let* ((q (policy-manager.get-quote sale-id))
                     (fungible:module{fungible-v2} (at 'fungible q)))
                (with-capability (REFUND sale-id)
                  (refund-escrow sale-id fungible bidder))))
            true))))
    true)
)
