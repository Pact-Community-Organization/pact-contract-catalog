;; nft.collection-policy — operator-curated, size-capped collections.
;;
;; Collections are self-serve: anyone may create one, proving control of its
;; OPERATOR guard at creation. The collection ID is DERIVED from (name,
;; operator-guard) — the same anti-forgery shape the ledger uses for token ids
;; — so a collection id can only ever be claimed by the operator whose guard it
;; hashes over. That matters most OFF the creating chain: this policy is a
;; "permit" for mint-decision, so for a collection token the collection
;; operator IS the mint authority; if ids were hand-picked, a stranger on a
;; chain that had never seen the collection could claim the id, become its
;; operator, and issue supply under an ARRIVED token's identity. The derivation
;; carries no chain id, so the same collection has the same id everywhere and
;; only its operator can ever establish it.
;;
;; Tokens join a collection at create-token time via the 'collection_id'
;; payload field — only the operator may add tokens (fail closed: a missing or
;; unknown collection id aborts creation), up to max-size (0 = unbounded, and
;; counted per chain: joining is a creation-time act on the chain the token is
;; created on). Minting a collection token is likewise operator-authorized:
;; curation covers both what enters the collection and when it is issued.
;; Ownership, sale economics and the NFT shape are the other policies'
;; concerns — stack them.
;;
;; Every hook requires the ledger's matching -CALL capability in scope, so no
;; hook is reachable outside the real ledger lifecycle path.

(namespace (read-string 'ns))

(module collection-policy GOVERNANCE
  @doc "Collection membership policy for the nft framework: self-serve \
       \collections, operator-gated token creation + mint, size cap."

  (implements token-policy)
  (use token-policy [token-info payout])

  (defconst ADMIN-KS:string (read-string 'admin-ks)
    @doc "Admin keyset name, captured ONCE at deploy — never read from a \
         \caller's payload at enforcement time. Governance upgrades the \
         \module and nothing else: collections belong to their operators.")

  (defcap GOVERNANCE ()
    (enforce-keyset ADMIN-KS))

  (defconst COLLECTION-ID-MSG-KEY:string "collection_id"
    @doc "Create-token-tx payload key naming the target collection. REQUIRED \
         \for any token carrying this policy — fail closed.")

  (defconst COLLECTION-ID-PREFIX:string "collection"
    @doc "Reserved protocol prefix of a collection id (collection:<hash>).")

  (defconst BINDING-OPERATOR-PROTOCOLS:[string] ["k" "w"]
    @doc "A collection operator guard must be a key (k:) or a key set (w:) — \
         \the two guard forms whose principal contains the key material \
         \itself, so the derived collection id means the same operator on \
         \every chain. r: keeps only a keyset NAME (rotatable, and undefined \
         \on a fresh chain); u:/c:/m: keep a module-qualified name whose \
         \meaning is that module's code. Any of those would let a stranger \
         \re-derive this collection's id elsewhere and become its operator — \
         \and since mint-decision returns \"permit\", its mint authority.")

  (defschema collection
    @doc "An operator-owned collection."
    name:string
    operator-guard:guard
    max-size:integer
    size:integer)
  (deftable collections:{collection})

  (defschema token-collection
    @doc "Which collection a token belongs to (bound once at creation)."
    collection-id:string)
  (deftable collection-tokens:{token-collection})

  (defcap COLLECTION:bool (id:string name:string max-size:integer)
    @doc "Emitted once, when a collection is created."
    @event true)

  (defcap TOKEN-ADDED:bool (collection-id:string token-id:string)
    @doc "Emitted when a token joins a collection."
    @event true)

  (defcap OPERATOR:bool (collection-id:string operator-guard:guard)
    @doc "Authenticates the collection operator (a signer can scope their \
         \signature to it). The guard argument always comes from this \
         \module's own state or, at creation, the enrolling tx."
    (enforce-guard operator-guard))

  ;; --- collection identity (derived, so it cannot be claimed by a stranger) -----
  (defun create-collection-id:string (name:string operator-guard:guard)
    @doc "The collection id: \"collection:\" + a hash of the NAME and the \
         \OPERATOR GUARD. Derived from the operator's key, so nobody else can \
         \claim it; and derived WITHOUT a chain id, so the same collection \
         \has the same id on every chain — which is what keeps a relocated \
         \token's membership meaningful, and what stops a stranger on the \
         \destination chain from becoming its operator."
    (format "{}:{}" [COLLECTION-ID-PREFIX (hash [name operator-guard])]))

  (defun enforce-collection-reserved:bool (id:string name:string operator-guard:guard)
    @doc "The anti-squat gate, in two halves. \
         \(1) The OPERATOR GUARD must be one whose principal pins its \
         \authority immutably — k: (a key) or w: (a key set). The id is a \
         \hash of the guard OBJECT, and a keyset-ref-guard serialises to the \
         \keyset NAME only: two chains with different keysets behind the same \
         \name derive the SAME id, which is precisely the destination-chain \
         \squat this derivation exists to prevent. Refuse the guard rather \
         \than mint an id that does not certify anybody. \
         \(2) The id MUST re-derive from the name + operator guard, exactly as \
         \the ledger re-derives a token id from its creation-guard."
    (enforce (contains (util.check-reserved (create-principal operator-guard))
                       BINDING-OPERATOR-PROTOCOLS)
      "collection operator must be a key or keyset guard (k: or w:)")
    (enforce (= id (create-collection-id name operator-guard))
      "collection protocol violation"))

  ;; --- collections (self-serve, operator-owned) ---------------------------------
  (defun create-collection:bool (id:string name:string max-size:integer operator-guard:guard)
    @doc "Create a collection owned by OPERATOR-GUARD (the caller must satisfy \
         \it). ID is not a free choice: it must be (create-collection-id name \
         \operator-guard), so a collection id can never be squatted — here or \
         \on any other chain. MAX-SIZE 0 = unbounded, counted per chain."
    (enforce (!= name "") "collection name required")
    (enforce (>= max-size 0) "max-size must be >= 0 (0 = unbounded)")
    (enforce-collection-reserved id name operator-guard)
    (with-capability (OPERATOR id operator-guard)
      (insert collections id
        { 'name: name, 'operator-guard: operator-guard
        , 'max-size: max-size, 'size: 0 })
      (emit-event (COLLECTION id name max-size)))
    true)

  ;; --- views -------------------------------------------------------------------
  (defun get-collection:object{collection} (id:string)
    (read collections id))

  (defun get-token-collection:string (token-id:string)
    (at 'collection-id (read collection-tokens token-id)))

  ;; --- token-policy hooks --------------------------------------------------------
  ;; Each hook first requires the ledger's matching -CALL capability (via the
  ;; manager's registered ledger modref), so it is unreachable outside the real
  ;; ledger lifecycle path — direct calls with fabricated token-info fail.

  (defun enforce-init:bool (token:object{token-info})
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::INIT-CALL (at 'id token) (at 'precision token) (at 'uri token))))
    ;; the target collection is REQUIRED (fail closed) and must have room;
    ;; only its operator may add tokens
    (let ((collection-id:string (read-msg COLLECTION-ID-MSG-KEY)))
      (with-read collections collection-id
        { 'operator-guard := operator-guard, 'max-size := max-size, 'size := size }
        (let ((new-size:integer (+ 1 size)))
          (enforce (or (= 0 max-size) (<= new-size max-size)) "collection is full")
          (with-capability (OPERATOR collection-id operator-guard)
            (update collections collection-id { 'size: new-size })
            (insert collection-tokens (at 'id token) { 'collection-id: collection-id })
            (emit-event (TOKEN-ADDED collection-id (at 'id token)))))))
    true)

  (defun enforce-mint:bool (token:object{token-info} account:string guard:guard amount:decimal)
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::MINT-CALL (at 'id token) account amount)))
    ;; issuing a collection token is the operator's call (the recipient may be
    ;; anyone — the operator's guard authorizes the mint itself). The operator
    ;; is read from the collection row, and the row's id is derived from that
    ;; operator's guard, so on a chain where the collection has not been
    ;; established there is no row for a stranger to have claimed: the read
    ;; simply fails and nothing is issued.
    (let ((collection-id:string (at 'collection-id (read collection-tokens (at 'id token)))))
      (with-read collections collection-id { 'operator-guard := operator-guard }
        (with-capability (OPERATOR collection-id operator-guard) true)))
    true)

  (defun enforce-burn:bool (token:object{token-info} account:string amount:decimal)
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::BURN-CALL (at 'id token) account amount)))
    true)

  (defun enforce-offer:bool (token:object{token-info} seller:string amount:decimal timeout:integer sale-id:string)
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::OFFER-CALL (at 'id token) seller amount timeout sale-id)))
    true)

  (defun enforce-withdraw:bool (token:object{token-info} seller:string amount:decimal timeout:integer sale-id:string)
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::WITHDRAW-CALL (at 'id token) seller amount timeout sale-id)))
    true)

  (defun enforce-buy:[object{payout}] (token:object{token-info} seller:string buyer:string buyer-guard:guard amount:decimal sale-id:string)
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::BUY-CALL (at 'id token) seller buyer amount sale-id)))
    [])

  (defun enforce-transfer:bool (token:object{token-info} sender:string guard:guard receiver:string amount:decimal)
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::TRANSFER-CALL (at 'id token) sender receiver amount)))
    true)
  ;; --- cross-chain passport (policy state travels with the token) ---------------
  (defun enforce-xchain-send:object (token:object{token-info} sender:string receiver:string receiver-guard:guard target-chain:string amount:decimal)
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::XCHAIN-SEND-CALL (at 'id token) sender receiver target-chain amount)))
    ;; membership travels; the collection ROW (operator, size) is state of the
    ;; chain where the collection was created — the size cap is a creation-time
    ;; rule, already enforced when this token joined
    { 'collection-id: (at 'collection-id (read collection-tokens (at 'id token))) })

  (defun enforce-xchain-receive:bool (token:object{token-info} receiver:string receiver-guard:guard amount:decimal state:object)
    ;; only membership is re-bound here. The mint authority is NOT re-bound and
    ;; is not carried: it is whoever the collection id derives from, which the
    ;; id itself proves on every chain. A stranger on this chain cannot hold
    ;; that id, so an arrived token can never fall under a stranger's operator.
    (let ((l:module{ledger-iface} (policy-manager.retrieve-ledger)))
      (require-capability (l::XCHAIN-RECEIVE-CALL (at 'id token) receiver amount)))
    (let ((cid:string (at 'collection-id state)))
      (enforce (!= "" cid) "malformed collection passport")
      (with-default-read collection-tokens (at 'id token) { 'collection-id: "" } { 'collection-id := existing }
        (if (= "" existing)
          (insert collection-tokens (at 'id token) { 'collection-id: cid })
          (enforce (= existing cid) "collection passport mismatch"))))
    true)


  ;; --- uri stance: this policy has no uri concern (abstain) --------------------
  ;; mint stance: issuance is the collection operator's call (enforce-mint enforces the operator guard)
  (defun mint-decision:string (token:object{token-info}) (identity "permit"))

  (defun uri-decision:string (token:object{token-info}) (identity "abstain"))
  (defun enforce-update-uri:bool (token:object{token-info} new-uri:string)
    (enforce false "this policy does not permit uri updates"))
)
