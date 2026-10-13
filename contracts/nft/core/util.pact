;; nft.util — account-name validity + reserved-name protocol enforcement for the
;; NFT framework. Implements nft.account-protocols. Used by the ledger to
;; validate transfers and account names. The reserved-name check is what makes a
;; principal (k:/w:/…) account un-squattable: the account name must match its
;; guard. PCO `nft` framework; our own code.

(namespace (read-string 'ns))

(module util GOVERNANCE
  @doc "Account-protocol helpers for the nft framework: amount/precision/account \
       \validity and principal reserved-name enforcement."

  (implements account-protocols)

  (defconst ADMIN-KS:string (read-string 'admin-ks)
    @doc "Admin keyset name, captured ONCE at deploy — never read from a \
         \caller's payload at enforcement time.")

  (defcap GOVERNANCE ()
    (enforce-keyset ADMIN-KS))

  (defun enforce-valid-amount:bool (precision:integer amount:decimal)
    (enforce (> amount 0.0) "amount must be positive")
    (enforce-precision precision amount))

  (defun enforce-valid-account:bool (account:string)
    (enforce (> (length account) 2) "account name below minimum length")
    (enforce (is-charset CHARSET_LATIN1 account) "account name must be latin-1"))

  (defun enforce-precision:bool (precision:integer amount:decimal)
    (enforce (= (floor amount precision) amount) "precision violation"))

  (defun enforce-valid-transfer:bool
    (sender:string receiver:string precision:integer amount:decimal)
    (enforce (!= sender receiver) "sender cannot be the receiver")
    (enforce-valid-amount precision amount)
    (enforce-valid-account sender)
    (enforce-valid-account receiver))

  (defun check-reserved:string (account:string)
    @doc "Return the reserved-name protocol char of ACCOUNT (single char + ':', \
         \e.g. 'k:...' -> \"k\"), or \"\" if unreserved."
    (let ((pfx (take 2 account)))
      (if (= ":" (take -1 pfx)) (take 1 pfx) "")))

  ;; --- payee accounts (ADR-NFT-016) ---------------------------------------------------
  ;; Every fee leg pays ONE account. Its name must be the principal of its guard AND bind that
  ;; authority: k:/w:/c:, or r: INSIDE A PRINCIPAL NAMESPACE (r:n_<40 hex>.name). An r: name in an
  ;; ordinary namespace is refused: on a chain where the namespace is not yet defined a stranger
  ;; could define the keyset and own the payee there; only the governing keyset can define n_….
  ;; (Holder accounts are stricter still: ledger.enforce-account-principal refuses every r:.)
  (defconst BINDING-PAYEE-PROTOCOLS:[string] ["k" "w" "c" "r"])
  (defconst PRINCIPAL-NS-LEN:integer 42
    @doc "ns.create-principal-namespace: \"n_\" + 40 hex chars of the guard hash.")

  (defun principal-namespace-r?:bool (account:string)
    @doc "True when ACCOUNT is r:n_<40 hex>.<keyset-name>."
    (and (= "r:n_" (take 4 account))
         (and (= "." (take 1 (drop (+ 2 PRINCIPAL-NS-LEN) account)))
              (> (length account) (+ 3 PRINCIPAL-NS-LEN)))))

  (defun enforce-binding-payee:bool (account:string guard:guard)
    @doc "A payee (royalty beneficiary, venue, protocol, listing fee) must be the principal \
         \of GUARD and use a binding name: k:, w:, c:, or r: in a principal namespace."
    (enforce (validate-principal guard account) "payee account must be the principal of its guard")
    (let ((p (check-reserved account)))
      (enforce (contains p BINDING-PAYEE-PROTOCOLS)
        "payee account must pin its authority (k:, w:, c:, or r: in a principal namespace)")
      (if (= p "r")
        (enforce (principal-namespace-r? account) "an r: payee must live in a principal namespace (r:n_…)")
        true)))

  (defun enforce-reserved:bool (account:string guard:guard)
    @doc "Enforce reserved account-name protocols. A k:/w: principal account \
         \name MUST validate against its GUARD (validate-principal); a k: name \
         \that is not a valid single-key principal is rejected. Fail-closed."
    (if (validate-principal guard account)
      true
      (let ((r (check-reserved account)))
        (if (= r "")
          true
          (if (= r "k")
            (enforce false "single-key account protocol violation")
            (enforce false (format "reserved protocol guard violation: {}" [r])))))))
)
