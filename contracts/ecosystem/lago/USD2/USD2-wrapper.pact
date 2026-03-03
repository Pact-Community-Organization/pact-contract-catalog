;; lago.USD2-wrapper
;; Deployed on Kadena mainnet01 (KDA Community Edition)
;; Module hash : 5xX6H-mYx4N2RvXskbM4HxMkMg6mHMY9cIsm7PgLDEY
;; Tx hash     : 
;; Interfaces  : none
;; Source fetched from chain 1 via (describe-module "lago.USD2-wrapper")
;; Fetch date  : 2026-03-02

(module USD2-wrapper MINTER-ADMIN


    (defcap MINTER-ADMIN () "Admin-only." (enforce-keyset 'lago-ns-user))
)