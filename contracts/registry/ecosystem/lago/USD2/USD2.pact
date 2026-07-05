;; lago.USD2
;; Deployed on Kadena mainnet01 (KDA Community Edition)
;; Module hash : gx8dwzIfbuiqHtZ9km0W0bp1p7zAPYmrxfBmO7696S0
;; Tx hash     : 
;; Interfaces  : none
;; Source fetched from chain 2 via (describe-module "lago.USD2")
;; Fetch date  : 2026-03-02

(module USD2 GOVERNANCE

    (defcap GOVERNANCE
        ()
    
        @doc " Give the admin full access to call and upgrade the module. "
    
        (enforce-keyset 'lago-ns-user)
      )
)