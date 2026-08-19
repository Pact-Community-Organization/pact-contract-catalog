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
;; THE BIDDER'S OWN EXIT (reclaim-bid): the withdrawal refund above needs the
;; SELLER to act, and an offer made with timeout 0 can only be withdrawn by the
;; seller — so a seller who simply walks away would otherwise freeze the
;; winner's escrow forever. reclaim-bid is the bidder-walkable exit: past
;; end+settlement-grace — the same instant the seller's refunding withdrawal
;; opens — the recorded bidder, signing with the guard they already bound to
;; their bid, takes their own escrow back and the bid is struck from the
;; auction (settlement then refuses, and withdrawal becomes the bidless case).
;; It is not a reversal and grants no new power to anyone: the only account it
;; can pay is the bidder's own recorded refund target.
;; The deadline it keys on cannot be moved by the seller: update-auction is
;; refused once the stored start is in the past, and no bid can exist before
;; start — so from the first instant a bid is possible, `end` and
;; `settlement-grace` are frozen. settlement-grace is additionally capped at
;; MAX-SETTLEMENT-GRACE so the seller cannot post a deadline beyond reach.
;;
;; A sale contract cannot ask the engine whether its sale defpact is still
;; alive (there is no such builtin), and a quote row outlives its sale — so
;; create-auction and place-bid gate on policy-manager.enforce-sale-live.
;; Without that gate an auction can be attached to an already-terminated sale
;; and every bid escrowed into it is permanently unrecoverable: no
;; continuation exists to settle it or to refund it.
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

  (defconst MAX-SETTLEMENT-GRACE:integer 604800
    @doc "Upper bound (7 days) on the winner's exclusive settlement window. \
         \The grace window is the one interval in which a bidder's escrow is \
         \locked with no exit of their own; capping it bounds how long a \
         \seller can hold a winner's funds after the auction ends. Long \
         \enough for anyone to land one continuation transaction.")

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

  (defcap RECLAIM-BID:bool (bidder-guard:guard)
    @doc "The bidder proves control of the guard their escrowed bid returns \
         \to — the same guard they bound when they placed it."
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
    (enforce (>= settlement-grace 0) "settlement grace must be >= 0")
    (enforce (<= settlement-grace MAX-SETTLEMENT-GRACE)
      "settlement grace exceeds the maximum"))

  (defun create-auction:bool
    ( sale-id:string token-id:string start:integer end:integer
      reserve:decimal increment:decimal settlement-grace:integer )
    @doc "Attach an auction to an offered sale. Seller-only; the sale's quote \
         \must name THIS contract and carry the 0 discovery price, and that \
         \sale must still be LIVE — a quote row outlives its sale, and an \
         \auction on a terminated sale can never settle or refund."
    (policy-manager.enforce-sale-live sale-id)
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
         \refund target must be un-squattable). Refused once the sale itself \
         \is dead: escrow taken after that has no settlement and no refund."
    (policy-manager.enforce-sale-live sale-id)
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
          ;; ...and prove it landed under OUR guard. The bid escrow's principal
          ;; is publicly computable from the offer, so on a fungible that does
          ;; not enforce reserved account-name protocols a stranger can hold
          ;; that name before the first bid arrives and sweep what lands there.
          ;; This escrow holds a third party's money ACROSS transactions, so a
          ;; squat here is theft, not merely a brick. Checked AFTER the transfer
          ;; so the check is fail-closed — see enforce-account-custody.
          (policy-manager.enforce-account-custody fungible
            (bid-escrow-account sale-id) (bid-escrow-guard sale-id))
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

  (defun reclaim-bid:bool (sale-id:string)
    @doc "The BIDDER's own exit. Past end+settlement-grace — the same instant \
         \the seller's refunding withdrawal opens — the recorded bidder takes \
         \their escrowed bid back with the guard they already hold, without \
         \the seller and without any privileged party. The bid is struck from \
         \the auction before the money moves, so settlement afterwards refuses \
         \(no bids) and withdrawal falls to the bidless case. Not a reversal: \
         \the only account it can pay is the bidder's own recorded target, and \
         \a settled sale left nothing in the escrow to take. \
         \IT IS NOT POWER-NEUTRAL, AND THE ASYMMETRY IS DELIBERATE: past \
         \end+settlement-grace the bidder can void a won auction that nobody \
         \settled, which before was the seller's decision alone. That is the \
         \point — the alternative is the seller freezing the winner's money by \
         \doing nothing. The window is the seller's to use: anyone may settle \
         \for the whole of it, and it is capped at MAX-SETTLEMENT-GRACE, so a \
         \seller can buy at most that much settlement certainty. After it, \
         \reclaim and settlement race, and whichever transaction mines first \
         \wins."
    (with-read auctions sale-id
      { 'end := end, 'settlement-grace := grace
      , 'highest-bid := bid, 'bidder := bidder, 'bidder-guard := bidder-guard }
      (enforce (> bid 0.0) "no escrowed bid to reclaim")
      (enforce (> (curr-time) (+ end grace))
        "the winner's settlement grace window is still open")
      (let* ((q (policy-manager.get-quote sale-id))
             (fungible:module{fungible-v2} (at 'fungible q)))
        (with-capability (RECLAIM-BID bidder-guard)
          (update auctions sale-id
            { 'highest-bid: 0.0, 'bidder: "", 'bidder-guard: (bid-escrow-guard sale-id) })
          (with-capability (REFUND sale-id)
            (refund-escrow sale-id fungible bidder)))))
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
