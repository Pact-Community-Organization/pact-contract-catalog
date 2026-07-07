;; nft.poly-fungible — the multi-token (poly-fungible) accounting standard the
;; ledger implements: per-(token-id, account) balances, managed transfers,
;; reconciliation events, and the offer/buy sale defpact hook. The PCO `nft`
;; framework's token standard (functionally the poly-fungible surface every
;; conforming ledger exposes; our own code).

(namespace (read-string 'ns))

(interface poly-fungible

  (defschema account-details
    @doc "Balance record for (id, account)."
    @model [ (invariant (!= id "")) (invariant (!= account "")) (invariant (>= balance 0.0)) ]
    id:string
    account:string
    balance:decimal
    guard:guard)

  (defschema sender-balance-change
    @doc "RECONCILE event leg for the sender."
    account:string previous:decimal current:decimal)

  (defschema receiver-balance-change
    @doc "RECONCILE event leg for the receiver."
    account:string previous:decimal current:decimal)

  (defcap TRANSFER:bool (id:string sender:string receiver:string amount:decimal)
    @doc "Manage transfer of AMOUNT of ID. As an event, notifies burn (\"\" \
         \receiver) and create/mint (\"\" sender)."
    @managed amount TRANSFER-mgr)

  (defcap XTRANSFER:bool (id:string sender:string receiver:string target-chain:string amount:decimal)
    @doc "Manage cross-chain transfer of AMOUNT of ID to TARGET-CHAIN."
    @managed amount TRANSFER-mgr)

  (defun TRANSFER-mgr:decimal (managed:decimal requested:decimal)
    @doc "Linear manager for the TRANSFER amount.")

  (defcap SUPPLY:bool (id:string supply:decimal)
    @doc "Emitted when the supply of ID changes." @event)

  (defcap ACCOUNT_GUARD:bool (id:string account:string guard:guard)
    @doc "Emitted when an account guard is set/updated." @event)

  (defcap RECONCILE:bool
    ( token-id:string amount:decimal
      sender:object{sender-balance-change} receiver:object{receiver-balance-change} )
    @doc "Accounting event: sender={\"\",0,0} for mint, receiver={\"\",0,0} for burn." @event)

  (defun precision:integer (id:string)
    @doc "Maximum decimal precision for ID.")

  (defun enforce-unit:bool (id:string amount:decimal)
    @doc "Enforce AMOUNT meets ID's minimum precision.")

  (defun mint:bool (id:string account:string guard:guard amount:decimal)
    @doc "Mint AMOUNT of ID to ACCOUNT with GUARD."
    @model [ (property (!= id "")) (property (!= account "")) (property (>= amount 0.0)) ])

  (defun burn:bool (id:string account:string amount:decimal)
    @doc "Burn AMOUNT of ID from ACCOUNT."
    @model [ (property (!= id "")) (property (!= account "")) (property (>= amount 0.0)) ])

  (defun create-account:bool (id:string account:string guard:guard)
    @doc "Create ACCOUNT for ID at 0.0 balance under GUARD."
    @model [ (property (!= id "")) (property (!= account "")) ])

  (defun get-balance:decimal (id:string account:string)
    @doc "Balance of ID for ACCOUNT; fails if the account does not exist.")

  (defun details:object{account-details} (id:string account:string)
    @doc "Details of ACCOUNT under ID; fails if the account does not exist.")

  (defun transfer:bool (id:string sender:string receiver:string amount:decimal)
    @doc "Transfer AMOUNT of ID SENDER -> RECEIVER (managed by TRANSFER)."
    @model [ (property (> amount 0.0)) (property (!= id "")) (property (!= sender ""))
             (property (!= receiver "")) (property (!= sender receiver)) ])

  (defun transfer-create:bool (id:string sender:string receiver:string receiver-guard:guard amount:decimal)
    @doc "Transfer AMOUNT of ID SENDER -> RECEIVER, creating RECEIVER if absent \
         \(else RECEIVER-GUARD must match). Managed by TRANSFER."
    @model [ (property (> amount 0.0)) (property (!= id "")) (property (!= sender ""))
             (property (!= receiver "")) (property (!= sender receiver)) ])

  (defpact transfer-crosschain:bool
    ( id:string sender:string receiver:string receiver-guard:guard target-chain:string amount:decimal )
    @doc "Cross-chain transfer of AMOUNT of ID to RECEIVER on TARGET-CHAIN."
    @model [ (property (> amount 0.0)) (property (!= id "")) (property (!= sender ""))
             (property (!= receiver "")) (property (!= target-chain "")) ])

  (defun total-supply:decimal (id:string)
    @doc "Total quantity of ID (0.0 if unsupported).")

  (defun get-uri:string (id:string)
    @doc "The uri for ID.")

  ;; --- sale API ---
  (defcap SALE:bool (id:string seller:string amount:decimal timeout:integer sale-id:string)
    @doc "Wrapper cap/event for a sale of ID by SELLER until TIMEOUT." @event)

  (defpact sale:string (id:string seller:string amount:decimal timeout:integer)
    @doc "Offer -> buy escrow defpact. Step 0 offer (with withdraw rollback after \
         \TIMEOUT); step 1 buy, completed with 'buyer / 'buyer-guard payload.")
)
