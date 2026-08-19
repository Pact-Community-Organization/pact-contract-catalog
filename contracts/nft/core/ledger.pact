;; nft.ledger — the shared NFT ledger: the single source of truth for token
;; identity, ownership balances, and supply, for the PCO `nft` framework.
;;
;; IDENTITY (the part of the Marmalade architecture that is correct, kept
;; verbatim in behavior): a token id is `n:{hash([token-details, chain-id,
;; creation-guard])}` — DERIVED from the creator's creation-guard. `create-token`
;; re-derives the id and enforces equality (enforce-token-reserved), and inserts
;; the token row (insert fails on a duplicate id). Therefore:
;;   * FORGERY is impossible — you cannot create a token with a given id unless
;;     you control the creation-guard that hashes to it (CREATE-TOKEN enforces
;;     that guard), and a fabricated id fails the protocol re-derivation.
;;   * DOUBLE-MINT is impossible — one id, one row, forever.
;; This is the anchor a self-sovereign per-NFT module could never provide.
;;
;; Lifecycle mutations route through nft.policy-manager.enforce-* (the extension
;; point where royalty/guard/sale-only policies run), secured by the -CALL
;; capability handshake: the manager verifies mid-call that the matching -CALL
;; cap is in scope, proving the call originated in this ledger's lifecycle path.
;;
;; Phase 1 ships identity + accounting; offer/buy settlement is Phase 2 (the
;; hardened, conservation-asserted manager). Until then the sale defpact and the
;; manager's offer/buy hooks reject.

(namespace (read-string 'ns))

(module ledger GOVERNANCE
  @doc "The nft framework's shared poly-fungible token ledger + identity anchor."

  (implements ledger-iface)
  (implements poly-fungible)

  (use poly-fungible [account-details sender-balance-change receiver-balance-change])
  (use token-policy [token-info])

  (defconst ADMIN-KS:string (read-string 'admin-ks)
    @doc "Admin keyset name, captured ONCE at deploy from the deployer's tx — \
         \never read from a caller's payload at enforcement time.")

  (defcap GOVERNANCE ()
    (enforce-keyset ADMIN-KS))

  (defconst VERSION:integer 1)
  (defconst TOKEN-ID-PREFIX:string "n"
    @doc "Our token-id reserved protocol prefix (n:...).")
  (defconst URI-RESERVED-PREFIX:string "nft:"
    @doc "Reserved uri prefix nobody may self-assign.")
  (defconst VALID-CHAIN-IDS:[string] (map (int-to-str 10) (enumerate 0 19))
    @doc "Every Chainweb chain id. A relocation names its target chain in the \
         \yield; a target that is not one of these is a chain that will never \
         \resume the pact, so the token is destroyed and no later transaction \
         \can bring it back. coin-v6 refuses the same input (its \
         \VALID_CHAIN_IDS) — same house rule here.")
  (defconst BINDING-ACCOUNT-PROTOCOLS:[string] ["k" "w" "c"]
    @doc "The ONLY account-name protocols this ledger accepts. A name may hold \
         \an NFT only if the name itself pins the authority that may spend it, \
         \for all time and on every chain. Verified against the engine \
         \(Pact/Core/IR/Eval/Runtime/Utils.hs createPrincipalForGuard): \
         \  k: <key>            — the ed25519 key IS the name. Immutable. \
         \  w: <hash> <pred>    — a hash of the key set. Immutable. \
         \  c: <hash>           — a hash of a fully-qualified capability name, \
         \                        its args and the defpact id; required by \
         \                        this ledger's own per-sale NFT escrow. \
         \REFUSED, because their names bind a MUTABLE REFERENCE rather than an \
         \authority — validate-principal says yes both before and after the \
         \authority behind them changes: \
         \  r: <keyset-name>    — createPrincipalForGuard keeps only the NAME. \
         \                        define-keyset rotates the keys under it, and \
         \                        on a chain where the name is undefined a \
         \                        stranger defines it outright. That is what \
         \                        makes a name-equality read of ownership \
         \                        (royalty-policy's sale-only rule) false. \
         \  u: / m: / p:        — a module-qualified function or module name; \
         \                        the guard's BODY is never hashed, so the \
         \                        module's code decides what the name means.")

  ;; --- schemas / tables -----------------------------------------------------
  (deftable ledger-table:{account-details})

  (defschema token-schema
    @doc "The token row. `author-guard` is the creation-guard the id was \
         \derived from and enforced against at create-token — the ONE stored \
         \authorship fact. The author ADDRESS is not stored: it is derived \
         \(create-principal) at every read, so the two can never desync."
    id:string
    uri:string
    precision:integer
    supply:decimal
    policies:[module{token-policy}]
    author-guard:guard)
  (deftable tokens:{token-schema})

  (defschema token-details
    uri:string
    precision:integer
    policies:[module{token-policy}])

  ;; --- events -----------------------------------------------------------------
  (defcap TOKEN:bool (id:string precision:integer policies:[module{token-policy}] uri:string author:string creation-guard:guard)
    @doc "Emitted when a token id first becomes resident on THIS chain: at \
         \create-token, and again on the FIRST arrival of a relocated token \
         \(a token relocated to chain B was never created there, so without \
         \this an event-only indexer would never learn its author on B). \
         \`author` is the principal of `creation-guard` — index THAT; the raw \
         \guard is included only so a consumer can re-derive the id and check \
         \it, and a guard's key list is NOT an author."
    @event true)
  (defcap URI-UPDATED:bool (id:string uri:string)
    @doc "Emitted when a token's uri changes (policy-authorized)."
    @event true)
  (defcap SUPPLY:bool (id:string supply:decimal)
    @doc "Emitted when the supply of ID changes."
    @event true)
  (defcap ACCOUNT_GUARD:bool (id:string account:string guard:guard)
    @doc "Emitted when an account guard is enrolled."
    @event true)
  (defcap RECONCILE:bool
    (token-id:string amount:decimal sender:object{sender-balance-change} receiver:object{receiver-balance-change})
    @doc "Accounting event: sender={\"\",0,0} for mint, receiver={\"\",0,0} for burn."
    @event true)
  (defcap SALE:bool (id:string seller:string amount:decimal timeout:integer sale-id:string)
    @doc "Wrapper cap/event for a sale of ID by SELLER until TIMEOUT. Composes \
         \the seller-authorized OFFER and the sale-private token."
    @event
    (enforce (> amount 0.0) "amount must be positive")
    (compose-capability (OFFER id seller amount timeout))
    (compose-capability (SALE_PRIVATE sale-id)))

  (defcap OFFER:bool (id:string seller:string amount:decimal timeout:integer)
    @doc "Seller offers AMOUNT of ID until TIMEOUT: escrows the NFT into the \
         \sale-account. One-shot managed (installed by the seller's signature)."
    @managed
    (enforce (sale-active timeout) "invalid or expired timeout at offer")
    (compose-capability (DEBIT id seller))
    (compose-capability (CREDIT id (sale-account))))

  (defcap WITHDRAW:bool (id:string seller:string amount:decimal timeout:integer sale-id:string)
    @doc "Return the escrowed NFT to SELLER (rollback of an unsold offer, or an \
         \expired one). One-shot managed."
    @managed
    (compose-capability (SALE_PRIVATE sale-id))
    (if (= 0 timeout)
      (enforce-guard (at 'guard (details id seller)))
      (enforce (not (sale-active timeout)) "offer still active — cannot withdraw"))
    (compose-capability (DEBIT id (sale-account)))
    (compose-capability (CREDIT id seller)))

  (defcap BUY:bool (id:string seller:string buyer:string amount:decimal sale-id:string)
    @doc "Complete the sale: move the escrowed NFT to BUYER. One-shot managed."
    @managed
    (compose-capability (SALE_PRIVATE sale-id))
    (compose-capability (DEBIT id (sale-account)))
    (compose-capability (CREDIT id buyer)))

  (defcap SALE_PRIVATE:bool (sale-id:string)
    @doc "Guards the sale-account escrow: satisfied only inside the sale defpact."
    true)

  ;; --- auth caps --------------------------------------------------------------
  (defcap CREATE-TOKEN:bool (id:string creation-guard:guard)
    @doc "The creator proves control of the CREATION-GUARD the token id is \
         \derived from — the anti-forgery signature check."
    (enforce-guard creation-guard))

  (defcap MINT-AUTHOR:bool (id:string account:string amount:decimal)
    @doc "The author proves control of the CREATION-GUARD the token id is \
         \derived from, to issue supply under it. Scopable: a signer may \
         \restrict their signature to exactly this id/account/amount. \
         \Skipped only when an attached policy took over mint authorization \
         \(token-policy.mint-decision -> \"permit\")."
    (let ((cg:guard (get-author-guard id)))
      (enforce-guard cg)))

  (defcap TRANSFER:bool (id:string sender:string receiver:string amount:decimal)
    @managed amount TRANSFER-mgr
    (enforce (!= sender receiver) "same sender and receiver")
    (enforce-unit id amount)
    (enforce (> amount 0.0) "positive amount")
    (compose-capability (DEBIT id sender))
    (compose-capability (CREDIT id receiver)))

  (defun TRANSFER-mgr:decimal (managed:decimal requested:decimal)
    (let ((newbal (- managed requested)))
      (enforce (>= newbal 0.0) (format "TRANSFER exceeded for balance {}" [managed]))
      newbal))

  (defcap XTRANSFER:bool (id:string sender:string receiver:string target-chain:string amount:decimal)
    @doc "Relocate AMOUNT of ID to RECEIVER on TARGET-CHAIN (source-chain \
         \authority: the sender's guard + supply bookkeeping). One managed \
         \linear amount, installed by the sender's signature."
    @managed amount TRANSFER-mgr
    (enforce (> amount 0.0) "positive amount")
    (enforce-unit id amount)
    (enforce-xchain-target target-chain)
    (compose-capability (DEBIT id sender))
    (compose-capability (UPDATE_SUPPLY id)))

  (defcap XRECEIVE:bool (id:string receiver:string amount:decimal)
    @doc "Target-chain credit scope for a relocation. Weak body by design: \
         \the ONLY acquisition site is the SPV-continued receive step of \
         \transfer-crosschain — unreachable except through the pact machinery."
    (compose-capability (CREDIT id receiver))
    (compose-capability (UPDATE_SUPPLY id)))

  (defcap DEBIT:bool (id:string sender:string)
    @doc "Debit authority: the sender's account guard (bound in arg position — \
         \node-safe read)."
    (enforce-guard (account-guard id sender)))

  (defcap CREDIT:bool (id:string receiver:string)
    @doc "Internal credit token. Weak body by design: only composed into \
         \TRANSFER/MINT, never acquired externally."
    true)

  (defcap UPDATE_SUPPLY:bool (id:string)
    @doc "Internal supply-update token for ONE token id. Weak body by design: \
         \only composed into MINT/BURN/XTRANSFER/XRECEIVE, never acquired \
         \externally. It carries the id because a nullary supply cap \
         \authorizes a write on EVERY row of the table — a standing amplifier \
         \that turns any leak of it into a whole-ledger problem."
    true)

  (defcap MINT:bool (id:string account:string amount:decimal)
    @doc "Mint scope: composes CREDIT + UPDATE_SUPPLY for ID. Authorization is \
         \the AUTHOR's unless an attached policy permits (see mint-decision)."
    (enforce (> amount 0.0) "positive amount")
    (compose-capability (CREDIT id account))
    (compose-capability (UPDATE_SUPPLY id)))

  (defcap BURN:bool (id:string account:string amount:decimal)
    @doc "Burn scope: composes DEBIT (account-guard authorization) + UPDATE_SUPPLY."
    (enforce (> amount 0.0) "positive amount")
    (compose-capability (DEBIT id account))
    (compose-capability (UPDATE_SUPPLY id)))

  ;; --- ledger-iface -CALL caps (the modref handshake with the manager) --------
  ;; Weak bodies by design: each is acquired ONLY by this ledger around the
  ;; matching policy-manager.enforce-* call; the manager require-capability's it
  ;; through its stored ledger modref, proving the call came from this ledger's
  ;; lifecycle path and not from an arbitrary caller with fabricated token-info.
  (defcap INIT-CALL:bool (id:string precision:integer uri:string)
    @doc "Scopes policy enforce-init dispatch to create-token." true)
  (defcap TRANSFER-CALL:bool (id:string sender:string receiver:string amount:decimal)
    @doc "Scopes policy enforce-transfer dispatch to transfer/transfer-create." true)
  (defcap MINT-CALL:bool (id:string account:string amount:decimal)
    @doc "Scopes policy enforce-mint dispatch to mint." true)
  (defcap BURN-CALL:bool (id:string account:string amount:decimal)
    @doc "Scopes policy enforce-burn dispatch to burn." true)
  (defcap OFFER-CALL:bool (id:string seller:string amount:decimal timeout:integer sale-id:string)
    @doc "Scopes policy enforce-offer dispatch to the sale defpact (Phase 2)." true)
  (defcap WITHDRAW-CALL:bool (id:string seller:string amount:decimal timeout:integer sale-id:string)
    @doc "Scopes policy enforce-withdraw dispatch to the sale defpact (Phase 2)." true)
  (defcap BUY-CALL:bool (id:string seller:string buyer:string amount:decimal sale-id:string)
    @doc "Scopes policy enforce-buy dispatch to the sale defpact (Phase 2)." true)
  (defcap UPDATE-URI-CALL:bool (id:string new-uri:string)
    @doc "Scopes policy enforce-update-uri dispatch (updatable-uri policies)." true)
  (defcap XCHAIN-SEND-CALL:bool (id:string sender:string receiver:string target-chain:string amount:decimal)
    @doc "Scopes policy enforce-xchain-send dispatch to transfer-crosschain step 0." true)
  (defcap XCHAIN-RECEIVE-CALL:bool (id:string receiver:string amount:decimal)
    @doc "Scopes policy enforce-xchain-receive dispatch to transfer-crosschain step 1." true)

  ;; --- key / view helpers -----------------------------------------------------
  (defun key:string (id:string account:string) (format "{}:{}" [id account]))

  (defun account-guard:guard (id:string account:string)
    (at 'guard (read ledger-table (key id account))))

  (defun get-balance:decimal (id:string account:string)
    (at 'balance (read ledger-table (key id account))))

  (defun details:object{account-details} (id:string account:string)
    (read ledger-table (key id account)))

  (defun precision:integer (id:string) (at 'precision (read tokens id)))
  (defun get-uri:string (id:string) (at 'uri (read tokens id)))
  (defun total-supply:decimal (id:string)
    (with-default-read tokens id { 'supply: 0.0 } { 'supply := s } s))
  (defun get-version:integer () VERSION)

  (defun enforce-unit:bool (id:string amount:decimal)
    (let ((p (precision id)))
      (enforce (= (floor amount p) amount) "precision violation")))

  (defun enforce-account-principal:bool (account:string guard:guard)
    @doc "An account name must PIN its own authority. Two conditions, both \
         \necessary: the name must be the PRINCIPAL of the guard that holds it, \
         \AND it must use a protocol whose name binds that authority \
         \immutably (BINDING-ACCOUNT-PROTOCOLS). \
         \Without the first, a name certifies nothing: the first caller to \
         \claim it takes custody of everything sent there afterwards, and an \
         \in-flight relocation aimed at one is destroyed by a stranger who \
         \claims the row first (the arriving credit cannot match the \
         \squatter's guard, and step 0 has no rollback). \
         \Without the second, the name is the principal of a guard that can \
         \MEAN something else later or elsewhere — r:vault validates against \
         \keyset-ref-guard \"vault\" both before and after that keyset is \
         \rotated, and on a chain that has never defined it a stranger \
         \defines it. Only the second condition makes it sound to read \
         \(= sender receiver) as \"the same owner\" across a relocation, which \
         \is exactly what royalty-policy's sale-only rule does. \
         \Neither condition is an undo: both refuse the name at the point of \
         \the mistake, before anything moves."
    (enforce (validate-principal guard account)
      "account name must be the principal of its own guard")
    (enforce (contains (util.check-reserved account) BINDING-ACCOUNT-PROTOCOLS)
      "account name must pin its authority immutably (k:, w: or c:)"))

  (defun enforce-xchain-target:bool (target-chain:string)
    @doc "A relocation target must be a REAL chain. A token yielded to a chain \
         \id that does not exist is destroyed: nothing will ever resume the \
         \pact, step 0 has no rollback, and an undo must never be built."
    (enforce (!= "" target-chain) "target chain required")
    (let ((this-chain:string (at 'chain-id (chain-data))))
      (enforce (!= target-chain this-chain) "cannot relocate to the same chain"))
    (enforce (contains target-chain VALID-CHAIN-IDS)
      "target chain is not a valid chainweb chain id"))

  (defun get-author-guard:guard (id:string)
    @doc "The creation-guard TOKEN ID was derived from — the author. Written \
         \once by create-token from the guard CREATE-TOKEN enforced, never \
         \from a caller's payload; the id is a hash over it, so the row is \
         \self-certifying."
    (at 'author-guard (read tokens id)))

  (defun get-token-info:object{token-info} (id:string)
    (with-read tokens id { 'id := i, 'supply := s, 'precision := p, 'uri := u
                         , 'policies := pol, 'author-guard := ag }
      { 'id: i, 'supply: s, 'precision: p, 'uri: u, 'policies: pol
      , 'author: (create-principal ag), 'author-guard: ag }))

  (defun get-author:string (id:string)
    @doc "WHO MADE THIS: the author's address — the principal of the \
         \creation-guard the token id is derived from. This is the field a \
         \marketplace displays to tell an original from someone else's own \
         \version of the same artwork (a different author gets a different \
         \token id, never this one). It grants no authority."
    (create-principal (at 'author-guard (read tokens id))))

  ;; --- IDENTITY (behavior kept verbatim from the correct Marmalade model) -----
  (defun canonical-policies:[module{token-policy}] (policies:[module{token-policy}])
    @doc "The canonical policy list: sorted by the policy's fully-qualified \
         \name. Pact's plain `sort` is a NO-OP on module references, so the id \
         \derivation, the stored row, the TOKEN event and hook dispatch all use \
         \THIS order — the same policy SET derives the same token id no matter \
         \the order the creator passed."
    (map (lambda (o) (at 'p o))
      (sort ['k]
        (map (lambda (p:module{token-policy}) { 'k: (format "{}" [p]), 'p: p })
             policies))))

  (defun create-token-id:string (details:object{token-details} creation-guard:guard)
    @doc "The token id is a hash of the token details + chain + CREATION-GUARD, \
         \so the id is derived from the creator's key — forgery-proof. The \
         \policy list is canonicalized before hashing (order-independent id)."
    (let ((canon:object{token-details}
            { 'uri: (at 'uri details), 'precision: (at 'precision details)
            , 'policies: (canonical-policies (at 'policies details)) }))
      (format "{}:{}" [TOKEN-ID-PREFIX
        (hash [(format "{}" [canon]) (at 'chain-id (chain-data)) creation-guard])])))

  (defun check-reserved:string (token-id:string)
    (let ((pfx (take 2 token-id)))
      (if (= ":" (take -1 pfx)) (take 1 pfx) "")))

  (defun enforce-token-reserved:bool (token-id:string details:object{token-details} creation-guard:guard)
    @doc "The anti-forgery gate: the id MUST re-derive from the details + \
         \creation-guard."
    (let ((r (check-reserved token-id)))
      (if (= TOKEN-ID-PREFIX r)
        (enforce (= token-id (create-token-id details creation-guard)) "token protocol violation")
        (enforce false (format "unrecognized reserved protocol: {}" [r])))))

  (defun enforce-uri-reserved:bool (uri:string)
    (enforce (!= URI-RESERVED-PREFIX (take (length URI-RESERVED-PREFIX) uri))
      (format "reserved uri protocol: {}" [URI-RESERVED-PREFIX])))

  ;; --- create-token (anti-forgery / anti-double-mint entry) -------------------
  (defun create-token:bool
    ( id:string precision:integer uri:string
      policies:[module{token-policy}] creation-guard:guard )
    @doc "Create a token id. The id MUST re-derive from the details + \
         \CREATION-GUARD, the caller MUST satisfy that guard, and `insert` \
         \fails on a duplicate — one id, one token, exactly once. The policy \
         \list is canonicalized (name-sorted, duplicates rejected): storage, \
         \the TOKEN event and every hook dispatch use the canonical order."
    (enforce-uri-reserved uri)
    (let ((canon:[module{token-policy}] (canonical-policies policies)))
      (let ((names (map (lambda (p:module{token-policy}) (format "{}" [p])) canon)))
        (enforce (= (length names) (length (distinct names))) "duplicate policy"))
      (let ((details:object{token-details} { 'uri: uri, 'precision: precision, 'policies: canon }))
        (enforce-token-reserved id details creation-guard))
      (with-capability (INIT-CALL id precision uri)
        (policy-manager.enforce-init
          { 'id: id, 'supply: 0.0, 'precision: precision, 'uri: uri, 'policies: canon
          , 'author: (create-principal creation-guard), 'author-guard: creation-guard }))
      (with-capability (CREATE-TOKEN id creation-guard)
        (insert tokens id { 'id: id, 'uri: uri, 'precision: precision, 'supply: 0.0
                          , 'policies: canon, 'author-guard: creation-guard })
        (emit-event (TOKEN id precision canon uri (create-principal creation-guard) creation-guard))
        true)))

  ;; --- update-uri (fail closed: policy-mediated, immutable by default) --------
  (defun update-uri:bool (id:string new-uri:string)
    @doc "Update a token's uri. There is NO direct authorization here by \
         \design: the manager rejects unless an attached updatable-uri policy \
         \permits the update (and a non-updatable-uri veto is final), so a \
         \token without such a policy has an immutable uri."
    (enforce-uri-reserved new-uri)
    (with-capability (UPDATE-URI-CALL id new-uri)
      (policy-manager.enforce-update-uri (get-token-info id) new-uri))
    (update tokens id { 'uri: new-uri })
    (emit-event (URI-UPDATED id new-uri))
    true)

  ;; --- accounts ----------------------------------------------------------------
  (defun create-account:bool (id:string account:string guard:guard)
    @doc "Open an empty balance row for ACCOUNT under ID. The name must be the \
         \PRINCIPAL of GUARD: an unowned name would belong to whoever claims \
         \it first, and everything later sent there would land under their \
         \guard."
    (util.enforce-valid-account account)
    (util.enforce-reserved account guard)
    (enforce-account-principal account guard)
    ;; token must exist (a balance row for a non-token is meaningless)
    (precision id)
    (insert ledger-table (key id account)
      { 'id: id, 'account: account, 'balance: 0.0, 'guard: guard })
    (emit-event (ACCOUNT_GUARD id account guard))
    true)

  ;; --- mint / burn / transfer (routed through the manager handshake) ----------
  (defun mint:bool (id:string account:string guard:guard amount:decimal)
    @doc "Issue AMOUNT of ID to ACCOUNT. Supply under an id carries that id's \
         \authorship, so issuing it is the AUTHOR's call: MINT-AUTHOR \
         \enforces the creation-guard the id is derived from. The single \
         \exception is delegation the author chose AT CREATION — an attached \
         \policy whose mint-decision is \"permit\" (guard-policy's mint-guard, \
         \collection-policy's operator) takes over, and the policy set is \
         \part of the id. Fail closed: no mint-aware policy = author-only. \
         \This gates ISSUANCE ONLY; anyone may still create their own token \
         \(their own id, their own authorship) from the same details."
    (let ((token:object{token-info} (get-token-info id)))
      (with-capability (MINT-CALL id account amount)
        (if (policy-manager.mint-delegated token account amount)
          true
          (with-capability (MINT-AUTHOR id account amount) true))
        (policy-manager.enforce-mint token account guard amount)))
    (with-capability (MINT id account amount)
      (let ((receiver (credit id account guard amount))
            (sender:object{sender-balance-change} { 'account: "", 'previous: 0.0, 'current: 0.0 }))
        (emit-event (RECONCILE id amount sender receiver))
        (update-supply id amount)))
    true)

  (defun burn:bool (id:string account:string amount:decimal)
    (with-capability (BURN-CALL id account amount)
      (policy-manager.enforce-burn (get-token-info id) account amount))
    (with-capability (BURN id account amount)
      (let ((sender (debit id account amount))
            (receiver:object{receiver-balance-change} { 'account: "", 'previous: 0.0, 'current: 0.0 }))
        (emit-event (RECONCILE id amount sender receiver))
        (update-supply id (- amount))))
    true)

  (defun transfer:bool (id:string sender:string receiver:string amount:decimal)
    (util.enforce-valid-transfer sender receiver (precision id) amount)
    (with-capability (TRANSFER-CALL id sender receiver amount)
      (policy-manager.enforce-transfer (get-token-info id) sender (account-guard id sender) receiver amount))
    (with-capability (TRANSFER id sender receiver amount)
      (with-read ledger-table (key id receiver) { 'guard := g }
        (let ((s (debit id sender amount)) (r (credit id receiver g amount)))
          (emit-event (RECONCILE id amount s r)))))
    true)

  (defun transfer-create:bool (id:string sender:string receiver:string receiver-guard:guard amount:decimal)
    (util.enforce-valid-transfer sender receiver (precision id) amount)
    (with-capability (TRANSFER-CALL id sender receiver amount)
      (policy-manager.enforce-transfer (get-token-info id) sender (account-guard id sender) receiver amount))
    (with-capability (TRANSFER id sender receiver amount)
      (let ((s (debit id sender amount)) (r (credit id receiver receiver-guard amount)))
        (emit-event (RECONCILE id amount s r))))
    true)

  ;; --- cross-chain relocation (the policy passport) ----------------------------
  ;; Step 0 (source): policies validate the move and RETURN their per-token
  ;; state (passports); the sender is debited and the supply decremented; the
  ;; token metadata + passports YIELD to the target chain. Step 1 (target,
  ;; SPV-continued): the token row is materialized if this chain has never
  ;; seen it (its immutable identity is the SPV-proven yield — re-derivation
  ;; is impossible off the minting chain and unnecessary: `create-token` on
  ;; this chain can never mint a colliding id because its re-derivation uses
  ;; THIS chain's id); policies re-bind their passports; the receiver is
  ;; credited and the supply incremented. The uri is chain-local mutable
  ;; state (guarded policies), so a RETURNING token keeps this chain's uri.
  (defpact transfer-crosschain:bool (id:string sender:string receiver:string receiver-guard:guard target-chain:string amount:decimal)
    (step
      ;; ORDER: validate the request, THEN run the token's policies, THEN take
      ;; the value capabilities. A policy is a creator-written modref — third
      ;; party code — so it must never run while this ledger is holding DEBIT
      ;; or UPDATE_SUPPLY: `debit` and `update-supply` are public defuns gated
      ;; only by require-capability, so a hook that inherits those caps can
      ;; spend the sender past the amount they signed for and write the supply
      ;; of a token that has nothing to do with this transfer. This is the same
      ;; order `transfer` uses (hook inside TRANSFER-CALL, before TRANSFER) and
      ;; the same order the receive step below uses (hook inside
      ;; XCHAIN-RECEIVE-CALL, before XRECEIVE).
      (let ((token-info:object{token-info} (get-token-info id)))
        (util.enforce-valid-account receiver)
        (util.enforce-reserved receiver receiver-guard)
        ;; the receiver must be a PRINCIPAL: on the target chain a name that
        ;; certifies nothing can be claimed by a stranger, and the arriving
        ;; credit would then fail forever (step 0 has no rollback, so the token
        ;; is destroyed); and a policy reading (= sender receiver) as "the same
        ;; owner" would otherwise be wrong.
        (enforce-account-principal receiver receiver-guard)
        (enforce-xchain-target target-chain)
        (let ((passports:[object]
                (with-capability (XCHAIN-SEND-CALL id sender receiver target-chain amount)
                  (policy-manager.enforce-xchain-send token-info sender receiver receiver-guard target-chain amount))))
          (with-capability (XTRANSFER id sender receiver target-chain amount)
            (let ((sender-change (debit id sender amount))
                  (receiver-change:object{receiver-balance-change} { 'account: "", 'previous: 0.0, 'current: 0.0 }))
              (emit-event (RECONCILE id amount sender-change receiver-change))
              (update-supply id (- amount)))
            (yield { 'id: id, 'receiver: receiver, 'receiver-guard: receiver-guard, 'amount: amount
                   , 'uri: (at 'uri token-info), 'precision: (at 'precision token-info)
                   , 'policies: (at 'policies token-info), 'passports: passports
                   , 'author-guard: (get-author-guard id) }
              target-chain))
          true)))
    (step
      (resume { 'id := rid, 'receiver := rcv, 'receiver-guard := rg:guard, 'amount := amt
              , 'uri := ruri, 'precision := rprec:integer
              , 'policies := rpols:[module{token-policy}], 'passports := rpass:[object]
              , 'author-guard := rag:guard }
        ;; materialize the token on first arrival; on a RETURN verify the
        ;; immutable identity (precision + policy set); the local uri stands
        (with-default-read tokens rid { 'id: "" } { 'id := existing }
          (if (= "" existing)
            (let ((_ (insert tokens rid { 'id: rid, 'uri: ruri, 'precision: rprec, 'supply: 0.0
                                        , 'policies: rpols, 'author-guard: rag })))
              ;; the token was never CREATED on this chain, so no TOKEN event
              ;; ever fired here: emit it now, or an event-only indexer on this
              ;; chain never learns who made it.
              (emit-event (TOKEN rid rprec rpols ruri (create-principal rag) rag)))
            (with-read tokens rid { 'precision := lprec, 'policies := lpols, 'author-guard := lag }
              (enforce (= lprec rprec) "token precision mismatch on receive")
              (enforce (= lpols rpols) "token policy set mismatch on receive")
              (enforce (= lag rag) "token author mismatch on receive"))))
        (with-capability (XCHAIN-RECEIVE-CALL rid rcv amt)
          (policy-manager.enforce-xchain-receive (get-token-info rid) rcv rg amt rpass))
        (with-capability (XRECEIVE rid rcv amt)
          (let ((receiver-change (credit rid rcv rg amt))
                (sender-change:object{sender-balance-change} { 'account: "", 'previous: 0.0, 'current: 0.0 }))
            (emit-event (RECONCILE rid amt sender-change receiver-change))
            (update-supply rid amt)))
        true)))

  ;; --- internal debit / credit / supply ----------------------------------------
  (defun debit:object{sender-balance-change} (id:string account:string amount:decimal)
    @doc "Move AMOUNT out of ACCOUNT. The capability is not the last line of \
         \defence: anything that reaches here already holds it, so the \
         \ARGUMENT is checked here. enforce-unit only compares precision — \
         \(floor -1.0 0) is -1.0 — so without the sign check a negative \
         \amount would ADD to the balance and mint value out of nothing."
    (require-capability (DEBIT id account))
    (enforce (> amount 0.0) "positive amount")
    (enforce-unit id amount)
    (with-read ledger-table (key id account) { 'balance := bal }
      (enforce (<= amount bal) "insufficient funds")
      (let ((new-bal (- bal amount)))
        (update ledger-table (key id account) { 'balance: new-bal })
        { 'account: account, 'previous: bal, 'current: new-bal })))

  (defun credit:object{receiver-balance-change} (id:string account:string guard:guard amount:decimal)
    @doc "Move AMOUNT into ACCOUNT, opening the row on first credit. Same rule \
         \as `debit`: the capability got us here, the argument checks decide. \
         \A negative amount would drive a balance below zero; a name that is \
         \not its guard's principal would open a squattable row."
    (require-capability (CREDIT id account))
    (enforce (> amount 0.0) "positive amount")
    (enforce-unit id amount)
    (util.enforce-valid-account account)
    (util.enforce-reserved account guard)
    (enforce-account-principal account guard)
    (with-default-read ledger-table (key id account)
      { 'balance: -1.0, 'guard: guard }
      { 'balance := bal, 'guard := existing }
      (let ((is-new (= bal -1.0)))
        (enforce (= existing guard) "account guard does not match")
        (let ((prev (if is-new 0.0 bal)) (new-bal (if is-new amount (+ bal amount))))
          (write ledger-table (key id account) { 'id: id, 'account: account, 'balance: new-bal, 'guard: guard })
          (if is-new (emit-event (ACCOUNT_GUARD id account guard)) true)
          { 'account: account, 'previous: prev, 'current: new-bal }))))

  (defun update-supply:bool (id:string amount:decimal)
    @doc "Add AMOUNT (signed: mint/receive positive, burn/send negative) to \
         \ID's supply. The capability names the id, so it can never write \
         \another token's row; the floor is checked here because a negative \
         \supply is not a state this ledger has any meaning for."
    (require-capability (UPDATE_SUPPLY id))
    (with-default-read tokens id { 'supply: 0.0 } { 'supply := s }
      (let ((new-s (+ s amount)))
        (enforce (>= new-s 0.0) "supply cannot go negative")
        (update tokens id { 'supply: new-s })
        (emit-event (SUPPLY id new-s))
        true)))

  ;; --- sale defpact (offer -> buy, with withdraw rollback) --------------------
  ;; The NFT escrows into the sale-account (a capability-pact-guarded principal)
  ;; at offer, and moves to the buyer at buy. The FUNGIBLE settlement (payment +
  ;; the conservation-asserted split) is the hardened policy-manager's job — this
  ;; ledger only moves the token.
  ;;
  ;; TIMEOUT SEMANTICS (unix seconds): the timeout gates WITHDRAWAL, not buying.
  ;;   * 0 — the seller may withdraw anytime (guard-checked);
  ;;   * t>0 — the offer is withdraw-LOCKED until t; after t, ANYONE may trigger
  ;;     the withdraw rollback (the token can only return to the seller).
  ;; An offer that has not been withdrawn remains BUYABLE — also after t. A
  ;; seller who no longer wants the quoted price must withdraw; a policy may
  ;; impose stricter offer-expiry semantics via enforce-buy.
  ;;
  ;; For a QUOTED sale (auction), this timeout is a SEPARATE clock from the
  ;; sale contract's own schedule, and the contract must also consent to
  ;; withdrawal — set timeout 0 (or >= the auction's end) and let the sale
  ;; contract's rules govern.

  (defpact sale:string (id:string seller:string amount:decimal timeout:integer)
    (step-with-rollback
      ;; step 0: offer — run policy enforce-offer, then escrow the NFT
      (let ((token-info (get-token-info id)))
        (with-capability (OFFER-CALL id seller amount timeout (pact-id))
          (policy-manager.enforce-offer token-info seller amount timeout (pact-id)))
        (with-capability (SALE id seller amount timeout (pact-id))
          (offer id seller amount))
        (pact-id))
      ;; step 0 rollback: withdraw — run policy enforce-withdraw, return the NFT
      (let ((token-info (get-token-info id)))
        (with-capability (WITHDRAW-CALL id seller amount timeout (pact-id))
          (policy-manager.enforce-withdraw token-info seller amount timeout (pact-id)))
        (with-capability (WITHDRAW id seller amount timeout (pact-id))
          (withdraw id seller amount))
        (pact-id)))
    (step
      ;; step 1: buy — the buyer + guard come from the buy continuation payload
      (let ( (buyer:string (read-msg "buyer"))
             (buyer-guard:guard (read-msg "buyer-guard")) )
        (with-capability (BUY-CALL id seller buyer amount (pact-id))
          (policy-manager.enforce-buy (get-token-info id) seller buyer buyer-guard amount (pact-id)))
        (with-capability (BUY id seller buyer amount (pact-id))
          (buy id seller buyer buyer-guard amount))
        (pact-id))))

  (defun offer:bool (id:string seller:string amount:decimal)
    @doc "Escrow AMOUNT of the NFT from SELLER into the sale-account."
    (require-capability (SALE_PRIVATE (pact-id)))
    (let ((sender (debit id seller amount))
          (receiver (credit id (sale-account) (create-capability-pact-guard (SALE_PRIVATE (pact-id))) amount)))
      (emit-event (TRANSFER id seller (sale-account) amount))
      (emit-event (RECONCILE id amount sender receiver)))
    true)

  (defun withdraw:bool (id:string seller:string amount:decimal)
    @doc "Return the escrowed NFT to SELLER."
    (require-capability (SALE_PRIVATE (pact-id)))
    (let ((sender (debit id (sale-account) amount))
          (receiver (credit-account id seller amount)))
      (emit-event (TRANSFER id (sale-account) seller amount))
      (emit-event (RECONCILE id amount sender receiver)))
    true)

  (defun buy:bool (id:string seller:string buyer:string buyer-guard:guard amount:decimal)
    @doc "Move the escrowed NFT to BUYER (fungible settlement is the manager's)."
    (require-capability (SALE_PRIVATE (pact-id)))
    (let ((sender (debit id (sale-account) amount))
          (receiver (credit id buyer buyer-guard amount)))
      (emit-event (TRANSFER id (sale-account) buyer amount))
      (emit-event (RECONCILE id amount sender receiver)))
    true)

  (defun credit-account:object{receiver-balance-change} (id:string account:string amount:decimal)
    @doc "Credit AMOUNT to an EXISTING account using its stored guard (used by \
         \withdraw to return the NFT to the seller's account)."
    (require-capability (CREDIT id account))
    (credit id account (account-guard id account) amount))

  (defun sale-active:bool (timeout:integer)
    @doc "A sale is active until TIMEOUT (unix seconds; 0 = always active)."
    (if (= 0 timeout)
      true
      (< (at 'block-time (chain-data)) (add-time (time "1970-01-01T00:00:00Z") timeout))))

  (defun sale-account:string ()
    @doc "The per-sale NFT escrow principal (guarded by SALE_PRIVATE of this pact)."
    (create-principal (create-capability-pact-guard (SALE_PRIVATE (pact-id)))))
)
