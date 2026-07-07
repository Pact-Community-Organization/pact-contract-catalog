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

  (defschema payout
    @doc "A cut a policy DECLARES from a sale price. The policy computes the \
         \amount from its OWN on-chain state (never the buy tx) and names the \
         \payee; it does NOT move the money. The single settlement routine in \
         \the manager pays every declared payout + the marketplace fee + the \
         \seller remainder from one escrow and asserts conservation. This is the \
         \ARCH-1 fix: no policy hook holds spend authority over the escrow."
    account:string
    guard:guard
    amount:decimal)

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

  (defun enforce-buy:[object{payout}]
    ( token:object{token-info} seller:string buyer:string buyer-guard:guard
      amount:decimal sale-id:string )
    @doc "Run at settlement of SALE-ID (SELLER -> BUYER). A hardened policy \
         \authorizes the sale AND RETURNS the payout(s) it claims from the \
         \price — each amount computed from the policy's OWN on-chain state \
         \(never the buy tx). It MUST NOT move money or touch the escrow. The \
         \manager's single settlement routine pays every returned payout + the \
         \marketplace fee + the seller remainder and asserts escrow \
         \conservation. Return [] to claim nothing.")

  (defun enforce-withdraw:bool
    ( token:object{token-info} seller:string amount:decimal timeout:integer sale-id:string )
    @doc "Run when SELLER withdraws the offer SALE-ID.")

  (defun enforce-transfer:bool
    ( token:object{token-info} sender:string guard:guard receiver:string amount:decimal )
    @doc "Run on a free (no-sale) transfer SENDER -> RECEIVER. A sale-only \
         \policy rejects this; it governs rotate too (RECEIVER=SENDER, 0.0).")
)
