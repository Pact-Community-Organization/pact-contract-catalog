;; REPL TEST SUPPORT ONLY — NOT a registry snapshot.
;;
;; On-chain, `kip.account-protocols-v1` is pre-deployed; this repo's registry
;; holds only verbatim chain snapshots, and this interface has not been
;; snapshotted yet. The member signatures below are derived mechanically from
;; the registry's `util.fungible-util` (which implements this interface), so
;; the real module loads against it unchanged. Do not deploy this file.

(namespace (read-string 'ns))

(interface account-protocols-v1

  (defun enforce-valid-amount (precision:integer amount:decimal)
    @doc "Enforce positive AMOUNT at PRECISION.")

  (defun enforce-valid-account (account:string)
    @doc "Enforce minimum account-name validity.")

  (defun enforce-precision (precision:integer amount:decimal)
    @doc "Enforce AMOUNT respects PRECISION.")

  (defun enforce-valid-transfer
    (sender:string receiver:string precision:integer amount:decimal)
    @doc "Enforce transfer validity of AMOUNT from SENDER to RECEIVER.")

  (defun check-reserved:string (account:string)
    @doc "Return the reserved-name protocol prefix of ACCOUNT, or empty.")

  (defun enforce-reserved:bool (account:string guard:guard)
    @doc "Enforce reserved account-name protocols for ACCOUNT/GUARD.")
)
