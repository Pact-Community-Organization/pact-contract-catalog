;; nft.royalty-policy — genuinely enforced on-chain creator payouts.
;;
;; The creator's payout plan is REQUIRED in the create-token transaction and
;; bound into this policy's OWN state at init — fail closed: a missing or
;; partial spec aborts token creation (the POL-1 fix), and nothing about the
;; plan is ever read from a buy transaction (the ARCH-2 fix).
;;
;; ADR-NFT-011: the plan names up to MAX-BENEFICIARIES payees, each with its own
;; rate (artist, co-author, charity, …), and may name a DIFFERENT list for the
;; first sale (the sale whose seller is the token's author) than for resales.
;; There is no per-leg cap: the only rule is the manager's — the total of every
;; leg on a sale can never exceed 100% — which it enforces at creation through
;; payout-bps and again at offer. A creator who sets 95% simply cannot be listed
;; by a venue charging more than 4.5% (plus protocol); that is the free market
;; the founder asked for, made visible before anyone buys.
;;
;; At settlement this policy DECLARES the payees' cuts — computed from its
;; stored plan and the manager's state-bound quote price — and moves no money;
;; the policy-manager's single conservation-asserted settlement pays them (the
;; ARCH-1 / POL-3 fix). The dust-price guard at offer rejects a price whose
;; floored total royalty would be zero, closing the round-to-zero evasion path.
;;
;; HOW the token may change hands is transfer-mode-policy's business
;; (ADR-NFT-007). CURRENCY: the cuts are denominated in the QUOTE's fungible.
;;
;; Every hook requires the ledger's matching -CALL capability in scope, so no
;; hook is reachable outside the real ledger lifecycle path.

(namespace (read-string 'ns))

(module royalty-policy GOVERNANCE
  @doc "Hardened creator-payout policy for the nft framework: plan bound at \
       \create, cuts declared from state at settlement."

  (implements token-policy)
  (use token-policy [token-info payout])

  (defconst ADMIN-KS:string (read-string 'admin-ks)
    @doc "Admin keyset name, captured ONCE at deploy — never read from a \
         \caller's payload at enforcement time.")

  (defcap GOVERNANCE ()
    (enforce-keyset ADMIN-KS))

  (defconst BPS-DENOM:integer 10000)
  (defconst MAX-BENEFICIARIES:integer 8
    @doc "Bound on the payees per list: keeps every settlement and every \
         \passport a known size.")
  (defconst ROYALTY-SPEC-MSG-KEY:string "royalty_spec"
    @doc "Create-token-tx payload key carrying the plan (the CREATOR's tx — \
         \economics are never read from a buy tx).")

  (defschema beneficiary
    account:string
    guard:guard
    bps:integer
    label:string)

  (defschema royalty-spec
    @doc "The creator's payout plan, bound once at token creation, immutable \
         \after. `beneficiaries` applies to every resale; `primary` applies to \
         \a sale whose seller is the token's author, or, when empty, the resale \
         \list applies to that sale too."
    beneficiaries:[object{beneficiary}]
    primary:[object{beneficiary}])
  (deftable royalties:{royalty-spec})

  (defcap ROYALTY:bool (token-id:string beneficiaries:[object{beneficiary}] primary:[object{beneficiary}])
    @doc "Emitted once, when the plan binds at token creation."
    @event true)

  ;; --- views -------------------------------------------------------------------
  (defun get-royalty:object{royalty-spec} (token-id:string)
    (read royalties token-id))

  (defun total-bps:integer (bs:[object{beneficiary}])
    (fold (+) 0 (map (at 'bps) bs)))

  (defun enforce-valid-list:bool (label:string bs:[object{beneficiary}])
    (enforce (<= (length bs) MAX-BENEFICIARIES)
      (format "{}: at most {} beneficiaries" [label MAX-BENEFICIARIES]))
    (map (lambda (b:object{beneficiary})
           (enforce (>= (at 'bps b) 0) (format "{}: bps must not be negative" [label]))
           ;; ADR-NFT-016: k:/w:/c:, or r: in a principal namespace (never a name a stranger could define elsewhere)
           (util.enforce-binding-payee (at 'account b) (at 'guard b)))
         bs)
    (enforce (<= (total-bps bs) BPS-DENOM) (format "{}: total exceeds 100%" [label])))

  (defun plan-for-sale:[object{beneficiary}] (token:object{token-info} seller:string)
    @doc "The list that applies: `primary` when the seller is the author and a \
         \primary list was given, else `beneficiaries`."
    (with-read royalties (at 'id token) { 'beneficiaries := bs, 'primary := ps }
      (if (and (= seller (at 'author token)) (> (length ps) 0)) ps bs)))

  ;; --- the cuts, computed from STATE --------------------------------------------
  (defun cut:decimal (price:decimal prec:integer bps:integer)
    (floor (/ (* price (dec bps)) (dec BPS-DENOM)) prec))

  (defun cuts-for:[object{payout}] (sale-id:string bs:[object{beneficiary}])
    @doc "One payout per beneficiary, floor(price * bps / 10000) at the quote \
         \fungible's precision; zero cuts are dropped. The price comes from the \
         \manager's state-bound quote, never a payload."
    (let* ((q (policy-manager.get-quote sale-id))
           (fungible:module{fungible-v2} (at 'fungible q))
           (prec:integer (fungible::precision))
           (price:decimal (at 'price q)))
      (filter (lambda (p:object{payout}) (> (at 'amount p) 0.0))
        (map (lambda (b:object{beneficiary})
               { 'account: (at 'account b), 'guard: (at 'guard b), 'amount: (cut price prec (at 'bps b)) })
             bs))))

  ;; --- token-policy hooks --------------------------------------------------------
  ;; Each hook first requires the ledger's matching -CALL capability (via the
  ;; manager's registered ledger modref), so it is unreachable outside the real
  ;; ledger lifecycle path — direct calls with fabricated token-info fail.

  (defun enforce-init:bool (token:object{token-info})
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::INIT-CALL (at 'id token) (at 'precision token) (at 'uri token))))
    ;; the plan is REQUIRED (typed read: absent or partial -> abort, fail closed)
    (let ((spec:object{royalty-spec} (read-msg ROYALTY-SPEC-MSG-KEY)))
      (enforce-valid-list "beneficiaries" (at 'beneficiaries spec))
      (enforce-valid-list "primary" (at 'primary spec))
      (insert royalties (at 'id token) spec)
      (emit-event (ROYALTY (at 'id token) (at 'beneficiaries spec) (at 'primary spec))))
    true)

  (defun payout-bps:integer (token:object{token-info})
    @doc "The larger of the two lists' totals: the most this plan claims on any sale."
    (with-read royalties (at 'id token) { 'beneficiaries := bs, 'primary := ps }
      (let ((a (total-bps bs)) (b (total-bps ps)))
        (if (> a b) a b))))

  (defun enforce-mint:bool (token:object{token-info} account:string guard:guard amount:decimal)
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::MINT-CALL (at 'id token) account amount)))
    true)

  (defun enforce-burn:bool (token:object{token-info} account:string amount:decimal)
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::BURN-CALL (at 'id token) account amount)))
    true)

  (defun enforce-offer:bool (token:object{token-info} seller:string amount:decimal timeout:integer sale-id:string)
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::OFFER-CALL (at 'id token) seller amount timeout sale-id)))
    ;; dust guard: a price whose floored total royalty is zero would evade the
    ;; plan — reject it at offer (only when a royalty is actually set).
    ;; A QUOTED sale's price is 0 at offer (discovered at settlement); its
    ;; dust guard fires in enforce-buy against the finalized price instead.
    (let ((bs (plan-for-sale token seller)))
      (if (> (total-bps bs) 0)
        (let ((price:decimal (policy-manager.get-quote-price sale-id)))
          (if (> price 0.0)
            (enforce (> (length (cuts-for sale-id bs)) 0) "price too low: the royalty would floor to zero")
            true))
        true))
    true)

  (defun enforce-withdraw:bool (token:object{token-info} seller:string amount:decimal timeout:integer sale-id:string)
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::WITHDRAW-CALL (at 'id token) seller amount timeout sale-id)))
    true)

  (defun enforce-buy:[object{payout}] (token:object{token-info} seller:string buyer:string buyer-guard:guard amount:decimal sale-id:string)
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::BUY-CALL (at 'id token) seller buyer amount sale-id)))
    (let* ((bs (plan-for-sale token seller))
           (cuts (cuts-for sale-id bs)))
      ;; settlement-time dust guard: for a quoted sale (price finalized at
      ;; buy) this is where round-to-zero evasion is caught
      (if (> (total-bps bs) 0)
        (enforce (> (length cuts) 0) "price too low: the royalty would floor to zero")
        true)
      cuts))

  (defun enforce-transfer:bool (token:object{token-info} sender:string guard:guard receiver:string amount:decimal)
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::TRANSFER-CALL (at 'id token) sender receiver amount)))
    ;; whether a free transfer is allowed is transfer-mode-policy's decision
    true)

  ;; --- cross-chain passport (policy state travels with the token) ---------------
  (defun enforce-xchain-send:object (token:object{token-info} sender:string receiver:string receiver-guard:guard target-chain:string amount:decimal)
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::XCHAIN-SEND-CALL (at 'id token) sender receiver target-chain amount)))
    (read royalties (at 'id token)))

  (defun enforce-xchain-receive:bool (token:object{token-info} receiver:string receiver-guard:guard amount:decimal state:object)
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::XCHAIN-RECEIVE-CALL (at 'id token) receiver amount)))
    (let ((spec:object{royalty-spec}
            { 'beneficiaries: (at 'beneficiaries state), 'primary: (at 'primary state) }))
      (enforce-valid-list "beneficiaries" (at 'beneficiaries spec))
      (enforce-valid-list "primary" (at 'primary spec))
      ;; a plan may legitimately be two empty lists, so row EXISTENCE (not a
      ;; default read) decides between first arrival and return; `try` only
      ;; reads here, which Pact 5 permits inside it
      (let ((exists:bool (try false (let ((r (read royalties (at 'id token)))) true))))
        (if exists
          ;; a RETURNING token: the immutable plan must be identical
          (enforce (= (read royalties (at 'id token)) spec) "royalty passport mismatch")
          (insert royalties (at 'id token) spec))))
    true)

  ;; --- stances: a payout plan is an economic term, not an issuance or uri right -
  (defun mint-decision:string (token:object{token-info}) (identity "abstain"))

  (defun uri-decision:string (token:object{token-info}) (identity "abstain"))
  (defun enforce-update-uri:bool (token:object{token-info} new-uri:string)
    (enforce false "this policy does not permit uri updates"))
)
