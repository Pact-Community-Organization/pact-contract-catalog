;; games.arena — the reference "connect your game" contract (ADR-NFT-009 §4).
;;
;; A card battle game that USES the nft framework without owning anything:
;;   * it reads a card's game stats from `attributes-policy` with one call;
;;   * it proves a player holds a card by the player's OWN signature on the
;;     card account's guard — no custody, the card never leaves the wallet;
;;   * it writes the keys the studio assigned to it (level, wins) through a
;;     capability-guard WRITER that only this module can satisfy;
;;   * it mints one BOUND trophy per match through a capability-guard MINTER,
;;     serial = the match id, so every trophy is a distinct token with one look.
;;
;; Deploy data: `arena-ns` (the namespace this module lives in), `arena-admin-ks`
;; (the keyset name its governance enforces) and that keyset's definition. The
;; framework is referenced as `nft.*`; a deployment under another namespace
;; substitutes that prefix textually (the devnet driver does).
;;
;; A game module, not framework core: forking it is the point.

(namespace (read-string 'arena-ns))

(module arena GOVERNANCE
  @doc "Reference game: reads on-chain card stats, battles two signed-in \
       \holders, levels the winner's card, mints a bound trophy. No custody."

  (defconst ADMIN-KS:string (read-string 'arena-admin-ks))
  (defcap GOVERNANCE () (enforce-keyset ADMIN-KS))

  ;; the game's two on-chain identities: attribute WRITER and trophy MINTER.
  ;; Weak-bodied by design: acquired ONLY inside `battle`, after both players'
  ;; guards passed (static-gate WARN reviewed).
  (defcap WRITER:bool () true)
  (defcap MINTER:bool () true)
  (defun writer-guard:guard () (create-capability-guard (WRITER)))
  (defun minter-guard:guard () (create-capability-guard (MINTER)))

  (defcap BATTLE:bool (match-id:string card-a:string card-b:string winner-card:string winner:string trophy:string)
    @event true)

  (defconst TROPHY-URI:string "ipfs://arena/trophy")

  (defschema match-row
    card-a:string card-b:string winner-card:string winner:string power-a:integer power-b:integer trophy:string)
  (deftable matches:{match-row})

  ;; --- reading the card the useful way: one call per stat, typed ----------------
  (defun stat:integer (card:string key:string)
    @doc "An integer attribute; 0 when the key was never written."
    (str-to-int (nft.attributes-policy.get-attribute-or card key "0")))

  (defun power:integer (card:string)
    @doc "2*atk + def + hp + 5*level, from the on-chain sheet."
    (+ (+ (* 2 (stat card "atk")) (+ (stat card "def") (stat card "hp"))) (* 5 (stat card "level"))))

  (defun enforce-player-holds:bool (card:string player:string)
    @doc "Ownership without custody: the card is in PLAYER's wallet and PLAYER \
         \signed this transaction with the card account's own guard."
    (enforce (> (try 0.0 (nft.ledger.get-balance card player)) 0.0) "player does not hold the card")
    (enforce-guard (nft.ledger.account-guard card player)))

  (defun trophy-policies:[module{nft.token-policy}] ()
    [nft.transfer-mode-policy nft.issuance-policy])

  (defun trophy-id:string (match-id:string)
    (nft.ledger.create-token-id
      { 'uri: TROPHY-URI, 'precision: 0, 'policies: (trophy-policies), 'serial: match-id }
      (minter-guard)))

  (defun battle:string (match-id:string card-a:string player-a:string card-b:string player-b:string)
    @doc "Both players sign. The higher power wins (A on a tie); the winner's card \
         \gains a level and a win; the winner receives a bound trophy unique to \
         \this match. The tx payload carries the trophy's creation spec: \
         \transfer_mode \"bound\" and issuance_spec {max-issued 1, min-mint 1}."
    (enforce (!= card-a card-b) "a card cannot battle itself")
    (enforce-player-holds card-a player-a)
    (enforce-player-holds card-b player-b)
    (let* ((pa (power card-a)) (pb (power card-b))
           (wcard (if (>= pa pb) card-a card-b))
           (winner (if (>= pa pb) player-a player-b))
           (tid (trophy-id match-id)))
      (insert matches match-id
        { 'card-a: card-a, 'card-b: card-b, 'winner-card: wcard, 'winner: winner
        , 'power-a: pa, 'power-b: pb, 'trophy: tid })
      (with-capability (WRITER)
        (nft.attributes-policy.set-attribute wcard "level" (int-to-str 10 (+ 1 (stat wcard "level"))))
        (nft.attributes-policy.set-attribute wcard "wins" (int-to-str 10 (+ 1 (stat wcard "wins")))))
      (with-capability (MINTER)
        (nft.ledger.create-token tid 0 TROPHY-URI (trophy-policies) match-id (minter-guard))
        (nft.ledger.mint tid winner (nft.ledger.account-guard wcard winner) 1.0))
      (emit-event (BATTLE match-id card-a card-b wcard winner tid))
      winner))

  (defun get-match:object{match-row} (match-id:string) (read matches match-id))
)
