;; lago.bridge
;; Deployed on Kadena mainnet01 (KDA Community Edition)
;; Module hash : TEO9_LEZwxJ159A8ByHlKDmB6-25JKauVfylg9oDy1U
;; Tx hash     : 
;; Interfaces  : none
;; Source fetched from chain 1 via (describe-module "lago.bridge")
;; Fetch date  : 2026-03-02

(module bridge BRIDGE-ADMIN


    (defcap BRIDGE-ADMIN () "Admin-only." (enforce-keyset 'lago-ns-user))
)