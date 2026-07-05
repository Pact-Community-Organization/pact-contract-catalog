;; lago.kwBTC
;; Deployed on Kadena mainnet01 (KDA Community Edition)
;; Module hash : eMK6d8w17TqILbIYcbvhOWsMX49r5W5jqHdpRCLsDJY
;; Tx hash     : 
;; Interfaces  : none
;; Source fetched from chain 2 via (describe-module "lago.kwBTC")
;; Fetch date  : 2026-03-02

(module kwBTC GOVERNANCE

    (defcap GOVERNANCE
        ()
    
        @doc " Give the admin full access to call and upgrade the module. "
    
        (enforce-keyset 'lago-ns-user)
      )
)