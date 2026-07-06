;; REPL TEST SUPPORT ONLY — NOT a registry snapshot.
;;
;; On-chain, `kip.updatable-uri-policy-v1` is pre-deployed; the registry has
;; not snapshotted it yet. The single member signature below is derived from
;; its call site in the registry's marmalade-v2 policy-manager
;; (`(policy::enforce-update-uri token new-uri)`). Do not deploy this file.

(namespace (read-string 'ns))

(interface updatable-uri-policy-v1

  (defun enforce-update-uri:bool
    ( token:object{kip.token-policy-v2.token-info}
      new-uri:string )
    @doc "Policy hook for updating a token's URI.")
)
