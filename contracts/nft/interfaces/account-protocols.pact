;; nft.account-protocols — account-name validity + reserved-name (k:/w:/…)
;; protocol enforcement, implemented by nft.util and used by the ledger for
;; transfer/account validation. Part of the PCO `nft` framework (our own code;
;; the fungible-account-protocol surface every conforming util module exposes).

(namespace (read-string 'ns))

(interface account-protocols

  (defun enforce-valid-amount:bool (precision:integer amount:decimal)
    @doc "Enforce AMOUNT is positive and respects PRECISION.")

  (defun enforce-valid-account:bool (account:string)
    @doc "Enforce minimum account-name validity (non-empty, charset, length).")

  (defun enforce-precision:bool (precision:integer amount:decimal)
    @doc "Enforce AMOUNT respects PRECISION (no excess decimals).")

  (defun enforce-valid-transfer:bool
    (sender:string receiver:string precision:integer amount:decimal)
    @doc "Enforce SENDER/RECEIVER validity, AMOUNT>0 at PRECISION, sender!=receiver.")

  (defun check-reserved:string (account:string)
    @doc "Return the reserved-name protocol char of ACCOUNT (e.g. \"k\" for \
         \k:...), or \"\" if unreserved.")

  (defun enforce-reserved:bool (account:string guard:guard)
    @doc "Enforce reserved account-name protocols: a k:/w: principal account \
         \name MUST match its GUARD. Authored fail-closed.")
)
