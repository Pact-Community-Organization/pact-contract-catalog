;; kaddex.supply-control-v1
;; Deployed on Kadena mainnet01 (KDA Community Edition)
;; Module hash : ivxd6zuoClxyYCv_h9OjNHwAXlY1LdJfz7y-U2NDTLc
;; Tx hash     : 
;; Interfaces  : none
;; Source fetched from chain 1 via (describe-module "kaddex.supply-control-v1")
;; Fetch date  : 2026-03-02

(interface supply-control-v1
  (defun burn:decimal (purpose:string account:string amount:decimal))
  (defun mint:decimal (purpose:string account:string guard:guard amount:decimal))
  (defun total-supply:decimal ())
)
