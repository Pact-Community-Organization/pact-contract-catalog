;; runonflux.fungible-util
;; Deployed on Kadena mainnet01 (KDA Community Edition)
;; Module hash : DDjNIG0RSYOdkCSGlIdhqd9zYTyr6eSKMm8lC8i41ck
;; Tx hash     : 
;; Interfaces  : none
;; Source fetched from chain 2 via (describe-module "runonflux.fungible-util")
;; Fetch date  : 2026-03-02

(module fungible-util GOVERNANCE

  (defcap GOVERNANCE ()
    (enforce-guard (keyset-ref-guard 'fluxteam)))

  (defun enforce-valid-amount
    ( precision:integer
      amount:decimal
    )
    (enforce (> amount 0.0) "Positive non-zero amount")
    (enforce-precision precision amount)
  )

  (defun enforce-valid-account (account:string)
    (enforce (> (length account) 2) "minimum account length")
  )

  (defun enforce-precision
    ( precision:integer
      amount:decimal
    )
    (enforce
      (= (floor amount precision) amount)
      "precision violation")
  )

  (defun enforce-valid-transfer
    ( sender:string
      receiver:string
      precision:integer
      amount:decimal)
    (enforce (!= sender receiver)
      "sender cannot be the receiver of a transfer")
    (enforce-valid-amount precision amount)
    (enforce-valid-account sender)
    (enforce-valid-account receiver)
  )
)
