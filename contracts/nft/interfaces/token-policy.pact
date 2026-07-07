;; nft.token-policy — the policy hook interface for the NFT framework.
;;
;; A concrete policy implements these hooks; the ledger (via the policy-manager)
;; maps them over every policy attached to a token at each lifecycle event. This
;; is the extension point where royalty, guard, collection, and sale-only
;; behavior live. Authored for the PCO `nft` framework (hardened successor to the
;; Marmalade v2 architecture); the framework's own original code, not a fork.

(namespace (read-string 'ns))

(interface token-policy

  (defschema token-info
    @doc "The token view passed to every policy hook. `policies` is the set of \
         \policies attached to the token (self-referential list of this iface)."
    id:string
    supply:decimal
    precision:integer
    uri:string
    policies:[module{token-policy}])

  (defun enforce-init:bool (token:object{token-info})
    @doc "Run at token creation. A hardened policy binds its economic terms \
         \(e.g. royalty rate + payee) into its OWN on-chain state HERE, from \
         \required (fail-closed) inputs — never defaulted, never read at buy.")

  (defun enforce-mint:bool
    ( token:object{token-info} account:string guard:guard amount:decimal )
    @doc "Run at mint of AMOUNT of TOKEN to ACCOUNT."
    @model [ (property (!= account "")) (property (> amount 0.0)) ])

  (defun enforce-burn:bool
    ( token:object{token-info} account:string amount:decimal )
    @doc "Run at burn of AMOUNT of TOKEN from ACCOUNT."
    @model [ (property (!= account "")) (property (> amount 0.0)) ])

  (defun enforce-offer:bool
    ( token:object{token-info} seller:string amount:decimal timeout:integer sale-id:string )
    @doc "Run when SELLER offers AMOUNT of TOKEN for sale SALE-ID.")

  (defun enforce-buy:bool
    ( token:object{token-info} seller:string buyer:string buyer-guard:guard
      amount:decimal sale-id:string )
    @doc "Run at settlement of SALE-ID (SELLER -> BUYER). A hardened policy \
         \DECLARES its cut of the price (read from its own state) for the \
         \single conservation-asserted settlement; it MUST NOT reach into a \
         \shared escrow itself, and MUST NOT read economics from the tx.")

  (defun enforce-withdraw:bool
    ( token:object{token-info} seller:string amount:decimal timeout:integer sale-id:string )
    @doc "Run when SELLER withdraws the offer SALE-ID.")

  (defun enforce-transfer:bool
    ( token:object{token-info} sender:string guard:guard receiver:string amount:decimal )
    @doc "Run on a free (no-sale) transfer SENDER -> RECEIVER. A sale-only \
         \policy rejects this; it governs rotate too (RECEIVER=SENDER, 0.0).")
)
