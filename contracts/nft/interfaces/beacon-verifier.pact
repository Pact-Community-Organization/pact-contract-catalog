;; nft.beacon-verifier — what the pack engine needs from a public randomness beacon.
;;
;; A verifier proves that a beacon value for a given round was published by the
;; beacon network (here: drand's BN254 chain), and derives a seed from it that is
;; bound to a caller-chosen key. It ABORTS on a bad signature; it never returns a
;; boolean a caller could ignore. The pack engine holds the verifier as a
;; governance-registered modref of this interface (ADR-NFT-012), so the engine's
;; code names no namespace and the same engine runs on every chain where a
;; conforming verifier is deployed.

(namespace (read-string 'ns))

(interface beacon-verifier

  (defun round-at:integer (t:time)
    @doc "The beacon round published at or before T. Pass a FUTURE time to pin \
         \a round that does not exist yet.")

  (defun time-of-round:time (rnd:integer)
    @doc "When the beacon publishes RND (the inverse of round-at).")

  (defun verified-seed:integer (rkey:string rnd:integer sig-hex:string)
    @doc "Verify SIG-HEX as the beacon for RND and return a seed bound to RKEY. \
         \Aborts unless the signature verifies.")
)
