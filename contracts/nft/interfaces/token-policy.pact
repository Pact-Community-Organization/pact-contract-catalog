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
         \policy rejects this. (Account guards are immutable in this ledger: \
         \there is no rotate path for a policy to govern.)")

  ;; --- uri-update stance + authorization (attachment-authoritative) -----------
  ;; Both hooks are on the BASE interface so the manager evaluates them over
  ;; EVERY attached policy — a policy can never be bypassed by being absent from
  ;; an out-of-band registry. (This replaces the separate updatable-uri-policy
  ;; interface, whose optional-ness was the bypass.)
  (defun uri-decision:string (token:object{token-info})
    @doc "This policy's stance on updating TOKEN's uri, evaluated over every \
         \attached policy. Return one of: \
         \\"veto\"    — the uri must never change (final: one veto beats any stack); \
         \\"permit\"  — this policy authorizes updates (the manager then calls \
         \             enforce-update-uri on it for the specific new uri); \
         \\"abstain\" — no opinion. \
         \Pure: no guard/signature check (it is read for every policy). The uri \
         \is immutable unless some policy permits AND none vetoes — so a token \
         \with no uri-aware policy is immutable by default.")

  (defun enforce-update-uri:bool (token:object{token-info} new-uri:string)
    @doc "Run ONLY on a policy that returned \"permit\": authorize this specific \
         \update to NEW-URI (e.g. enforce the token's uri-update guard). A \
         \non-permitting policy is never called here; implement it to reject.")

  ;; --- cross-chain relocation (the policy passport) ---------------------------
  (defun enforce-xchain-send:object
    ( token:object{token-info} sender:string receiver:string receiver-guard:guard
      target-chain:string amount:decimal )
    @doc "Run on the SOURCE chain when SENDER relocates AMOUNT of TOKEN to \
         \RECEIVER on TARGET-CHAIN. The policy validates the move against its \
         \rules (e.g. sale-only permits only self-relocation) and RETURNS its \
         \serialized per-token state — the PASSPORT — which the ledger yields \
         \with the token so the policy can re-bind it on the target chain. \
         \Return {} if the policy keeps no per-token state.")

  (defun enforce-xchain-receive:bool
    ( token:object{token-info} receiver:string receiver-guard:guard
      amount:decimal state:object )
    @doc "Run on the TARGET chain when the relocation completes (SPV-continued \
         \defpact step). STATE is this policy's own passport from the source \
         \chain: bind it into local state exactly once (insert if absent; if \
         \the token has been on this chain before, verify the immutable parts \
         \match instead). Fail closed on anything malformed.")
)
