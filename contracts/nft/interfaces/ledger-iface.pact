;; nft.ledger-iface — the ledger interface the policy-manager holds as a modref.
;;
;; These `-CALL` capabilities secure the modref handshake: the policy-manager can
;; only invoke a policy hook while the matching ledger `-CALL` cap is in scope,
;; proving the call originated from the ledger's own lifecycle path (not from an
;; arbitrary caller). Part of the PCO `nft` framework.

(namespace (read-string 'ns))

(interface ledger-iface

  (defcap INIT-CALL:bool (id:string precision:integer uri:string)
    @doc "Secures the modref call to a policy's enforce-init.")

  (defcap TRANSFER-CALL:bool (id:string sender:string receiver:string amount:decimal)
    @doc "Secures the modref call to a policy's enforce-transfer.")

  (defcap MINT-CALL:bool (id:string account:string amount:decimal)
    @doc "Secures the modref call to a policy's enforce-mint.")

  (defcap BURN-CALL:bool (id:string account:string amount:decimal)
    @doc "Secures the modref call to a policy's enforce-burn.")

  (defcap OFFER-CALL:bool (id:string seller:string amount:decimal timeout:integer sale-id:string)
    @doc "Secures the modref call to a policy's enforce-offer.")

  (defcap WITHDRAW-CALL:bool (id:string seller:string amount:decimal timeout:integer sale-id:string)
    @doc "Secures the modref call to a policy's enforce-withdraw.")

  (defcap BUY-CALL:bool (id:string seller:string buyer:string amount:decimal sale-id:string)
    @doc "Secures the modref call to a policy's enforce-buy.")

  (defcap UPDATE-URI-CALL:bool (id:string new-uri:string)
    @doc "Secures the modref call to a policy's enforce-update-uri.")
)
