;; nft.updatable-uri-policy — the hook a policy implements to gate token-uri
;; updates. A token whose policy set does NOT include an updatable-uri policy has
;; an immutable uri (the manager rejects update-uri). Part of the PCO `nft`
;; framework.

(namespace (read-string 'ns))

(interface updatable-uri-policy

  (defun enforce-update-uri:bool
    (token:object{token-policy.token-info} new-uri:string)
    @doc "Run when the token's uri is updated to NEW-URI. A policy that permits \
         \updates authorizes the updater here (fail-closed); absence of this \
         \policy means the uri is immutable.")
)
