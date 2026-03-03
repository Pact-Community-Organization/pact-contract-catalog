(module p2p-escrow GOVERNANCE
  (defcap GOVERNANCE () true)
  (defconst VAULT_ACCOUNT "p2p-escrow-vault")
  (defconst PLATFORM_ARBITER "k:665976b8f985c0119c3afa74115fde19f71309cc85428a7104dc2648252b593e")
  (defconst T1_SECONDS 600)
  (defconst T2_SECONDS 600)
  (defconst T3_SECONDS 600)
  (defschema escrow
    creator:string
    buyer:string
    arbiter:string
    amount:decimal
    state:string
    side:string
    acceptedAt:string
    fundedAt:string
    paidAt:string)
  (defschema reputation-row
    totalTrades:integer
    successfulTrades:integer
    disputesCount:integer)
  (defschema config-row
    arbiter:string
    t1:integer
    t2:integer
    t3:integer)
  (deftable escrows:{escrow})
  (deftable reputation:{reputation-row})
  (deftable config:{config-row})
  (defun init-config ()
    (with-capability (GOVERNANCE)
      (insert config "global"
        { "arbiter": PLATFORM_ARBITER, "t1": T1_SECONDS, "t2": T2_SECONDS, "t3": T3_SECONDS })))
  (defun set-config (arbiter t1 t2 t3)
    (with-capability (GOVERNANCE)
      (enforce (> (length arbiter) 0) "Arbiter required")
      (enforce (> t1 0) "T1 must be > 0")
      (enforce (> t2 0) "T2 must be > 0")
      (enforce (> t3 0) "T3 must be > 0")
      (write config "global" { "arbiter": arbiter, "t1": t1, "t2": t2, "t3": t3 })))
  (defun get-arbiter ()
    (with-read config "global" { "arbiter" := a }
      (if (> (length a) 0) a PLATFORM_ARBITER)))
  (defun get-t1 ()
    (with-read config "global" { "t1" := t } t))
  (defun get-t2 ()
    (with-read config "global" { "t2" := t } t))
  (defun get-t3 ()
    (with-read config "global" { "t3" := t } t))
  (defun get-reputation (wallet)
    (if (contains wallet (keys reputation)) (read reputation wallet) {"totalTrades": 0, "successfulTrades": 0, "disputesCount": 0}))
  (defun get-escrow (id)
    (read escrows id))
  (defun list-escrow-ids ()
    (keys escrows))
)