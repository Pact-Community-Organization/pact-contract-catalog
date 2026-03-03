;; lago.kwUSDC
;; Deployed on Kadena mainnet01 (KDA Community Edition)
;; Module hash : ZYJ-acaoNxTNtgiShBi7q-OakMCdQkKFJLwGtLjEtSQ
;; Tx hash     : 
;; Interfaces  : none
;; Source fetched from chain 2 via (describe-module "lago.kwUSDC")
;; Fetch date  : 2026-03-02

(module kwUSDC GOVERNANCE

    (defcap GOVERNANCE
        ()
    
        @doc " Give the admin full access to call and upgrade the module. "
    
        (enforce-keyset 'lago-ns-user)
      )
)