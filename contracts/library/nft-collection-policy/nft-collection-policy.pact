(module nft-collection-policy GOV

  @doc "PCO library template: a marmalade-v2 CONCRETE POLICY for NFT            \
  \collections with creator-gated creation/minting, a collection size cap,     \
  \one-of-one NFT shape, and opt-in burning.                                   \
  \                                                                              \
  \This is the artifact an NFT project on Kadena actually writes: a module     \
  \implementing kip.token-policy-v2, attached to tokens at create-token time   \
  \and driven by the marmalade-v2 ledger through the policy-manager. It does   \
  \NOT custody tokens or funds - the marmalade ledger does; this policy only   \
  \decides what is allowed.                                                    \
  \                                                                              \
  \Rules enforced:                                                              \
  \  - Tokens join a COLLECTION (created here) at create-token time via the    \
  \    'collection_id' field in tx data. Only the collection creator (its      \
  \    enrolled guard) can add tokens, up to max-size (0 = unbounded).         \
  \  - NFT shape: precision 0, minted exactly once, amount exactly 1.0.        \
  \    A burned NFT cannot be re-minted (mint is once per token, ever).        \
  \  - Burning is a per-collection opt-in (the ledger additionally enforces    \
  \    the owner's guard).                                                     \
  \  - Transfers and sales are permitted by this policy (the ledger enforces   \
  \    ownership); stack marmalade concrete policies (e.g. royalty) for        \
  \    economics.                                                              \
  \                                                                              \
  \SECURITY: every policy hook is gated by require-capability on the           \
  \policy-manager's *-CALL capability, so hooks CANNOT be called directly -    \
  \only through the real ledger flow.                                          \
  \                                                                              \
  \Deployment checklist (see README.md):                                        \
  \  1. Wrap in your namespace; replace the 'nft-collection-gov' keyset.        \
  \  2. Deploy and create-table; no init step - collections are self-serve.    \
  \  3. Validate on devnet against the real marmalade-v2 deployment before     \
  \     mainnet."

  (implements kip.token-policy-v2)
  (use kip.token-policy-v2 [token-info])

  ;; -----------------------------
  ;; Governance
  ;; -----------------------------

  (defconst GOV_KEYSET:string "nft-collection-gov"
    @doc "Governance keyset name. Replace with your deployed, namespace- \
         \qualified keyset (multi-sig recommended). Governance can upgrade \
         \the module and nothing else: collections belong to their creators, \
         \and no function under GOV touches collection or token state.")

  (defcap GOV ()
    @doc "Module governance: upgrade only."
    (enforce-guard (keyset-ref-guard GOV_KEYSET)))

  ;; -----------------------------
  ;; Identity of this policy (for the policy-manager's *-CALL caps)
  ;; -----------------------------

  (defconst POLICY:string (format "{}" [nft-collection-policy])
    @doc "This policy's fully-qualified name as the policy-manager renders it \
         \in its *-CALL capabilities.")

  ;; -----------------------------
  ;; Schemas & tables
  ;; -----------------------------

  (defschema collection-row
    @doc "A creator-owned NFT collection."
    name:string
    creator-guard:guard   ;; authorizes create-token and mint for this collection
    max-size:integer      ;; max tokens in the collection; 0 = unbounded
    size:integer          ;; tokens created so far
    burnable:bool)        ;; whether owners may burn tokens of this collection

  (deftable collections:{collection-row})

  (defschema token-row
    @doc "Per-token policy state. MINTED is one-way: a burned NFT cannot be \
         \re-minted."
    collection-id:string
    minted:bool)

  (deftable tokens:{token-row})

  ;; -----------------------------
  ;; Events & auth
  ;; -----------------------------

  (defcap COLLECTION (id:string name:string max-size:integer burnable:bool)
    @event true)

  (defcap TOKEN-ADDED (collection-id:string token-id:string)
    @event true)

  (defcap CREATOR-AUTH (guard:guard)
    @doc "Authenticate a collection creator. As a capability, a creator can \
         \scope their create-collection signature to it."
    (enforce-guard guard))

  ;; -----------------------------
  ;; Collections (self-serve, creator-owned)
  ;; -----------------------------

  (defun create-collection:string (id:string name:string max-size:integer
                                   burnable:bool creator-guard:guard)
    @doc "Create a collection owned by CREATOR-GUARD. The caller must satisfy \
         \that guard (proves control of the enrolled authority). MAX-SIZE 0 \
         \means unbounded. ID must be unique."
    (enforce (!= id "") "collection id required")
    (enforce (!= name "") "collection name required")
    (enforce (>= max-size 0) "max-size must be >= 0 (0 = unbounded)")
    (with-capability (CREATOR-AUTH creator-guard)
      (insert collections id
        { 'name: name
        , 'creator-guard: creator-guard
        , 'max-size: max-size
        , 'size: 0
        , 'burnable: burnable })
      (emit-event (COLLECTION id name max-size burnable))
      id))

  ;; -----------------------------
  ;; kip.token-policy-v2 hooks
  ;; -----------------------------
  ;; Every hook is gated by require-capability on the policy-manager's
  ;; *-CALL capability: acquirable only inside the policy-manager, which is
  ;; itself gated by the ledger's own *-CALL capabilities. Direct calls to
  ;; these hooks always fail.

  (defun enforce-init:bool (token:object{token-info})
    @doc "Token creation: the tx data field 'collection_id' names the target \
         \collection; only the collection creator may add tokens; the \
         \collection must have room; NFT precision must be 0."
    (require-capability
      (marmalade-v2.policy-manager.INIT-CALL
        (at 'id token) (at 'precision token) (at 'uri token) POLICY))
    (enforce (= 0 (at 'precision token)) "NFT precision must be 0")
    (let* ((collection-id:string (read-msg "collection_id"))
           (col (read collections collection-id))
           (creator-guard (at 'creator-guard col))
           (max-size (at 'max-size col))
           (new-size (+ 1 (at 'size col)))
           (within-cap (or (= 0 max-size) (<= new-size max-size))))
      (enforce-guard creator-guard)
      (enforce within-cap "collection is full")
      (update collections collection-id { 'size: new-size })
      (insert tokens (at 'id token)
        { 'collection-id: collection-id, 'minted: false })
      (emit-event (TOKEN-ADDED collection-id (at 'id token)))
      true))

  (defun enforce-mint:bool (token:object{token-info} account:string
                            guard:guard amount:decimal)
    @doc "Minting: creator-authorized, exactly once per token, amount exactly \
         \1.0. The recipient (ACCOUNT/GUARD) may be anyone - the creator's \
         \guard authorizes the mint itself."
    (require-capability
      (marmalade-v2.policy-manager.MINT-CALL (at 'id token) account amount POLICY))
    (enforce (= amount 1.0) "NFT mint amount must be exactly 1.0")
    (with-read tokens (at 'id token)
      { 'collection-id := collection-id, 'minted := minted }
      (enforce (not minted) "NFT already minted")
      (let ((creator-guard (at 'creator-guard (read collections collection-id))))
        (enforce-guard creator-guard))
      (update tokens (at 'id token) { 'minted: true })
      true))

  (defun enforce-burn:bool (token:object{token-info} account:string amount:decimal)
    @doc "Burning: allowed only if the token's collection opted in. The \
         \ledger separately enforces the owner's guard (DEBIT). A burned \
         \NFT cannot be re-minted."
    (require-capability
      (marmalade-v2.policy-manager.BURN-CALL (at 'id token) account amount POLICY))
    (let* ((collection-id (at 'collection-id (read tokens (at 'id token))))
           (burnable (at 'burnable (read collections collection-id))))
      (enforce burnable "collection does not allow burning"))
    true)

  (defun enforce-offer:bool (token:object{token-info} seller:string
                             amount:decimal timeout:integer sale-id:string)
    @doc "Sales are permitted by this policy; the ledger/policy-manager \
         \enforce seller ownership and sale mechanics. Stack a royalty \
         \policy for economics."
    (require-capability
      (marmalade-v2.policy-manager.OFFER-CALL
        (at 'id token) seller amount sale-id timeout POLICY))
    true)

  (defun enforce-withdraw:bool (token:object{token-info} seller:string
                                amount:decimal timeout:integer sale-id:string)
    (require-capability
      (marmalade-v2.policy-manager.WITHDRAW-CALL
        (at 'id token) seller amount sale-id timeout POLICY))
    true)

  (defun enforce-buy:bool (token:object{token-info} seller:string buyer:string
                           buyer-guard:guard amount:decimal sale-id:string)
    (require-capability
      (marmalade-v2.policy-manager.BUY-CALL
        (at 'id token) seller buyer amount sale-id POLICY))
    true)

  (defun enforce-transfer:bool (token:object{token-info} sender:string
                                guard:guard receiver:string amount:decimal)
    @doc "Transfers are permitted by this policy (the ledger enforces the \
         \sender's guard). Also covers the ledger's rotate case (amount 0.0)."
    (require-capability
      (marmalade-v2.policy-manager.TRANSFER-CALL
        (at 'id token) sender receiver amount POLICY))
    true)

  ;; -----------------------------
  ;; Views
  ;; -----------------------------

  (defun get-collection:object{collection-row} (id:string)
    (read collections id))

  (defun get-token-collection:string (token-id:string)
    (at 'collection-id (read tokens token-id)))

  (defun is-minted:bool (token-id:string)
    (at 'minted (read tokens token-id)))
)
