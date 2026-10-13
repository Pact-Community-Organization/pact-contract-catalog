;; split — a shared payout account whose income is divided among payees by fixed shares.
;;
;; ADR-NFT-016. Every fee leg of the framework pays ONE account: a royalty beneficiary, a
;; venue, the protocol. A company that wants several people behind one of those addresses,
;; or wants to change who they are later, names a SPLIT instead: one transaction creates it,
;; the split owns a `c:` account only this module can debit, anyone may DISTRIBUTE whatever
;; sits in it (in any standard token) to the payees by their shares, and the owner may edit
;; the payees until they renounce — after which the split is as fixed as a royalty plan.
;;
;; Push, not pull: a transfer to a payee whose guard is stored here cannot be blocked by the
;; payee (transfer-create), so no balance ever waits to be claimed and no dust is stranded by
;; a missing claim. Rounding dust below the token's precision stays in the account for the
;; next distribution.
;;
;; An example module, not framework core: Smart Pacts deploys it on every chain the
;; framework lives on (a `c:` payee named in a token pays the same account on every chain),
;; and anyone may fork it. Deploy data: `split-ns`, `split-admin-ks` and that keyset.
;; The framework is referenced as `nft.*`.
(namespace (read-string 'split-ns))

(module split GOVERNANCE
  @doc "Shared payout accounts divided by fixed shares; any fungible-v2; push distribution by anyone."

  (defconst ADMIN-KS:string (read-string 'split-admin-ks))
  (defcap GOVERNANCE () (enforce-keyset ADMIN-KS))

  (defconst BPS-DENOM:integer 10000)
  (defconst MAX-PAYEES:integer 16)

  (defschema payee
    account:string
    guard:guard
    bps:integer
    label:string)

  (defschema split-row
    owner:guard
    payees:[object{payee}]
    mutable:bool)
  (deftable splits:{split-row})

  ;; --- capabilities -------------------------------------------------------------------
  (defcap SPLIT:bool (id:string)
    @doc "The split's account authority. Acquired only by distribute; never managed, never \
         \granted to a caller."
    true)
  (defcap OWNER:bool (id:string)
    (with-read splits id { 'owner := g } (enforce-guard g)))

  (defcap SPLIT-CREATED:bool (id:string owner:guard payees:[object{payee}]) @event true)
  (defcap SPLIT-PAYEES:bool (id:string payees:[object{payee}]) @event true)
  (defcap SPLIT-RENOUNCED:bool (id:string) @event true)
  (defcap DISTRIBUTED:bool (id:string fungible:string total:decimal) @event true)

  (defun split-guard:guard (id:string) (create-capability-guard (SPLIT id)))
  (defun account:string (id:string)
    @doc "The split's payout account: name it wherever the framework asks for a payee."
    (create-principal (split-guard id)))

  ;; --- validation -----------------------------------------------------------------------
  (defun enforce-valid-payees:bool (id:string ps:[object{payee}])
    (enforce (and (>= (length ps) 1) (<= (length ps) MAX-PAYEES))
      (format "1 to {} payees" [MAX-PAYEES]))
    (let ((accts (map (at 'account) ps)))
      (enforce (= (length accts) (length (distinct accts))) "payee accounts must be distinct")
      (enforce (not (contains (account id) accts)) "a split cannot pay itself"))
    (map (lambda (p:object{payee})
           (enforce (> (at 'bps p) 0) (format "{}: bps must be positive" [(at 'label p)]))
           (nft.util.enforce-binding-payee (at 'account p) (at 'guard p)))
         ps)
    (enforce (= (fold (+) 0 (map (at 'bps) ps)) BPS-DENOM) "shares must total exactly 100%"))

  ;; --- lifecycle ------------------------------------------------------------------------
  (defun create-split:string (id:string owner:guard payees:[object{payee}])
    @doc "Create split ID owned by OWNER with PAYEES whose shares total 100%. Returns the \
         \payout account. The id is the caller's choice and must be unused."
    (enforce (and (!= id "") (<= (length id) 64)) "id must be 1 to 64 characters")
    (enforce-valid-payees id payees)
    (insert splits id { 'owner: owner, 'payees: payees, 'mutable: true })
    (emit-event (SPLIT-CREATED id owner payees))
    (account id))

  (defun set-payees:bool (id:string payees:[object{payee}])
    @doc "The owner replaces the payees of a split that has not been renounced."
    (with-read splits id { 'mutable := m }
      (enforce m "this split is fixed for good")
      (with-capability (OWNER id)
        (enforce-valid-payees id payees)
        (update splits id { 'payees: payees })
        (emit-event (SPLIT-PAYEES id payees))
        true)))

  (defun renounce:bool (id:string)
    @doc "The owner fixes the payees for good. There is no way back."
    (with-read splits id { 'mutable := m }
      (enforce m "this split is already fixed")
      (with-capability (OWNER id)
        (update splits id { 'mutable: false })
        (emit-event (SPLIT-RENOUNCED id))
        true)))

  ;; --- distribution ---------------------------------------------------------------------
  (defun distribute:bool (id:string fungible:module{fungible-v2})
    @doc "ANYONE may push the split's whole balance of FUNGIBLE to the payees by their \
         \shares. Each share is floored to the token's precision; the dust stays for the \
         \next distribution. Payee accounts are created with their stored guard when absent."
    (with-read splits id { 'payees := ps }
      (let* ((acct (account id))
             (prec (fungible::precision))
             (bal (try 0.0 (fungible::get-balance acct))))
        (enforce (> bal 0.0) "nothing to distribute")
        (with-capability (SPLIT id)
          (map (lambda (p:object{payee})
                 (let ((amt (floor (/ (* bal (dec (at 'bps p))) (dec BPS-DENOM)) prec)))
                   (if (> amt 0.0)
                     (let ((_ (install-capability (fungible::TRANSFER acct (at 'account p) amt))))
                       (fungible::transfer-create acct (at 'account p) (at 'guard p) amt))
                     "")))
               ps))
        (emit-event (DISTRIBUTED id (format "{}" [fungible]) bal))
        true)))

  ;; --- reads ----------------------------------------------------------------------------
  (defun get-split:object{split-row} (id:string) (read splits id))
)
