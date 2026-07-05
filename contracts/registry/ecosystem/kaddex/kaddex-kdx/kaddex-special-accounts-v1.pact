;; kaddex.special-accounts-v1
;; Deployed on Kadena mainnet01 (KDA Community Edition)
;; Module hash : 0AfwHi9fs-CemtSBLgpM6MVjHl_av4HrKDZBkZgK6oI
;; Tx hash     : 
;; Interfaces  : none
;; Source fetched from chain 1 via (describe-module "kaddex.special-accounts-v1")
;; Fetch date  : 2026-03-02

(interface special-accounts-v1
  (defun assign-special:string (name:string account:string))
  (defun resolve-special:string (name:string))
  (defun wrap-transfer:string (type:string sender:string receiver:string amount:decimal))
  (defun unwrap-transfer:string (type:string sender:string receiver:string receiver-guard:guard amount:decimal))

  (defcap WRAP:bool
    ( type:string
      sender:string
      receiver:string
      amount:decimal
    )
    @managed amount WRAP-mgr)

  (defun WRAP-mgr:decimal
    ( managed:decimal
      requested:decimal
    )
  )
  (defcap UNWRAP:bool
    ( type:string
      sender:string
      receiver:string
      amount:decimal
    )
    @managed amount UNWRAP-mgr)

  (defun UNWRAP-mgr:decimal
    ( managed:decimal
      requested:decimal
    )
  )
)
