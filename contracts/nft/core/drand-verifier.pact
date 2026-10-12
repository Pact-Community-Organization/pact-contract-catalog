;; nft.drand-verifier — SNAPSHOT of the sealed drand (evmnet, BN254) beacon verifier
;; that runs under Smart Pacts' roulette and baccarat on mainnet01 chain 2.
;;
;; PROVENANCE (workspace rule: a snapshot is generated, never hand-edited):
;;   source repo   SmartPacts/roulette-public, pact/modules/drand.pact
;;   commit        e7be14a6443131771cd36aec1863c50313ef338b (2026-09-23)
;;   deployed as   n_48867b242317a0216a67f8c7ca26696b5878e0e3.drand, chain 2,
;;                 module hash Y07t-duJmkXkcGth0TfBRg3ThbNR-uh9PdNUd1MKHBQ
;;   changes here  exactly two: the namespace line reads the deploy namespace,
;;                 and the module is renamed drand-verifier and declares
;;                 (implements beacon-verifier) so pack-engine can hold it as a
;;                 typed modref. Nothing else differs; regenerate from source.
;; Governance stays SEALED (enforce false): a pure verifier has no upgrade path.
;;
;; drand.pact — verify a drand BN254 beacon on chain (Pact 5 / KDA-CE).
;;
;; WHAT THIS IS FOR. A banked, fixed-odds game cannot take its outcome from a
;; Kadena block hash. The miner of the deciding block sees the outcome before
;; publishing and can discard the block and keep mining — a free re-roll. With
;; hashrate share h and true win probability b the grinder wins with
;;   W = b / (1 - h(1-b))
;; and four accounts produce 100% of mainnet blocks, the largest holding 61.5%.
;; An even-money bet then wins 71.1% instead of 48.65%. Measured, not modelled:
;; roulette-ops docs/measurements/BLOCK-HISTORY-AS-THE-BEACON.md.
;;
;; Combining several future blocks does NOT fix it — the first N-1 hashes already
;; exist when the last block is mined, so its miner evaluates the outcome exactly
;; as before. Deriving per player from the player's own committed secret does not
;; fix it either, because the attacker is a miner WHO IS ALSO A PLAYER. Both were
;; tested and both failed. What fixes it is entropy that no Kadena miner produces.
;;
;; THE PROPERTY THAT MATTERS is not the cryptography, it is RETRIEVABILITY. Pact
;; can read a Kadena block hash only in the very next block, which is why the
;; fleet's beacon has a one-block capture window and forfeits a round that misses
;; it. A drand round stays fetchable and verifiable FOREVER, so there is no window
;; to miss, no forfeit-on-missed-capture, and no gain from staying silent: anyone
;; may submit the beacon at any later time and a forged one cannot verify.
;;
;; NO HOUSE INPUT. The house holds no secret and sends no per-round transaction.
;; The standing constraint (founder, 2026-08-31: "the house is never a human
;; input") is preserved. Submitting a beacon is permissionless and unprivileged.
;;
;; THIS MODULE IS SEALED AND HAS NO STATE. Governance is (enforce false): it can
;; never be upgraded, so a consumer that pins it by code hash is pinning it
;; forever. It holds no tables, no capabilities and no funds, and every function
;; is pure — Pact has no private functions, so everything here is callable by
;; anyone, and that is harmless precisely because nothing here has an effect.
;;
;; FAIL-CLOSED. The pairing equation binds the signature to H(message). A mistake
;; in the hash-to-curve makes GENUINE signatures fail to verify; it cannot make a
;; forgery pass. The failure mode is "nothing settles", never "wrong winner" —
;; provided the point-at-infinity check stays, which is a named test.
;;
;; THE CONSTRUCTION, each element pinned by a mutation test that goes red if wrong:
;;   message  keccak256(I2OSP(round, 8))            -- Keccak-256, NOT SHA-256
;;   DST      BLS_SIG_BN254G1_XMD:KECCAK-256_SVDW_RO_NUL_   (43 bytes)
;;   expand   RFC 9380 s5.3.1 expand_msg_xmd, H = keccak256, s_in_bytes = 136
;;            (the Keccak rate — NOT 64, which is the usual copy-paste error)
;;   field    hash_to_field count 2, m 1, L 48
;;   map      Shallue-van de Woestijne RO variant: 2 maps then point-add.
;;            BN254 G1 has cofactor 1, so there is NO cofactor clearing and
;;            on-curve already implies in-subgroup.
;;   check    e(H(m), pk) * e(sig, -g2) == 1
;;   G2 ORDER drand serialises c1-first; Pact wants c0-first. This is the trap.
;;            It was settled against the twist equation, not assumed.
;;
;; GAS. One verify measured 1,082 best case / 1,965 worst (which SvdW branch the
;; two field elements take). BUT the gas table charges pairing as MilliGas using
;; the same integers Pact 4 charged as whole Gas, under a source comment saying
;; the costs need re-benching (TableGasModel.hs:98-105 vs :116). If KDA-CE
;; re-benches, one verify is ~21,000 gas. BUDGET 21k, not 1,965. Still 7x under.
;;
;; THE DEPENDENCY, stated plainly. This pins drand's `evmnet` chain and its public
;; key. drand cannot steer an outcome and cannot forge one; it can only stop
;; publishing. If that chain is ever retired, a consumer pinned to this module
;; must be redeployed — an admin-swappable beacon key is NOT the answer, because
;; whoever can swap the key can choose the outcome.

(namespace (read-string 'ns))

(module drand-verifier G
  (implements beacon-verifier)
  ;; sealed: a pure verifier has no upgrade path and no admin
  (defcap G () (enforce false "drand verifier governance is sealed"))

  (defconst P:integer 21888242871839275222246405745257275088696311157297823662689037894645226208583)
  (defconst CURVE-B:integer 3)
  ;; RFC 9380 s6.6.1 SvdW constants for y^2 = x^3 + 3, A = 0, Z = 1:
  ;;   C1 = g(Z) = 4  (inlined)   C2 = -Z/2   C3 = sqrt(-g(Z)*(3Z^2+4A)) with sgn0 = 0   C4 = -4g(Z)/(3Z^2+4A)
  (defconst C2:integer (mod (* (- P 1) (modexp 2 (- P 2) 254)) P))
  (defconst C3:integer 8815841940592487685674414971303048083897117035520822607866)
  (defconst C4:integer (mod (* (- P 16) (modexp 3 (- P 2) 254)) P))

  ;; DST_prime = DST || I2OSP(len(DST), 1).  len(DST) = 43 = 0x2B = ASCII '+'.
  (defconst DST-PRIME:string (base64-encode "BLS_SIG_BN254G1_XMD:KECCAK-256_SVDW_RO_NUL_+"))
  ;; Z_pad = I2OSP(0, s_in_bytes); keccak256 block size s_in_bytes = 136 -> 182 base64url chars.
  (defconst ZPAD:string (concat (make-list 182 "A")))

  ;; --- square-and-multiply modexp (modulus fixed to P) ---
  (defun bits:[integer] (e:integer n:integer)
    (map (lambda (i:integer) (mod (shift e (- 0 i)) 2)) (enumerate (- n 1) 0)))
  (defun modexp:integer (b:integer e:integer n:integer)
    (fold (lambda (acc:integer bit:integer)
            (let ((sq (mod (* acc acc) P)))
              (if (= bit 1) (mod (* sq b) P) sq)))
          1 (bits e n)))
  (defconst BITS-INV:[integer]  (bits (- P 2) 254))
  (defconst BITS-SQRT:[integer] (bits (/ (+ P 1) 4) 252))
  (defun powbits:integer (b:integer bs:[integer])
    (fold (lambda (acc:integer bit:integer)
            (let ((sq (mod (* acc acc) P)))
              (if (= bit 1) (mod (* sq b) P) sq)))
          1 bs))
  (defun inv:integer  (a:integer) (powbits a BITS-INV))   ; a^(P-2)
  (defun sqrtc:integer (a:integer) (powbits a BITS-SQRT))  ; a^((P+1)/4), P = 3 mod 4

  ;; --- fixed-width unpadded base64url of the NBYTES big-endian encoding of V.
  ;;     int-to-str 64 drops leading zero bytes, so prepend 3 bytes (0x010101 = one whole
  ;;     base64 group = 4 chars) and drop those 4 chars back off. ---
  (defun b64f:string (v:integer nbytes:integer)
    (drop 4 (int-to-str 64 (+ (* 66051 (^ 2 (* 8 nbytes))) v))))
  (defun kec:integer (chunks:[string]) (str-to-int 64 (hash-keccak256 chunks)))

  ;; --- RFC 9380 s5.3.1 expand_msg_xmd, H = keccak256, len_in_bytes = 96 (ell = 3) ---
  (defun expand96:[integer] (msg:integer)
    (let* ( ;; b_0 = H(Z_pad || msg || I2OSP(96,2) || I2OSP(0,1) || DST_prime)
            ;;       msg||0x0060||0x00 packs into one 35-byte chunk: msg*2^24 + 0x006000
            (b0 (kec [ZPAD (b64f (+ (* msg 16777216) 24576) 35) DST-PRIME]))
            ;; b_1 = H(b_0 || I2OSP(1,1) || DST_prime)
            (b1 (kec [(b64f (+ (* b0 256) 1) 33) DST-PRIME]))
            ;; b_i = H(strxor(b_0, b_{i-1}) || I2OSP(i,1) || DST_prime)
            (b2 (kec [(b64f (+ (* (xor b0 b1) 256) 2) 33) DST-PRIME]))
            (b3 (kec [(b64f (+ (* (xor b0 b2) 256) 3) 33) DST-PRIME])) )
      [b1 b2 b3]))

  ;; --- hash_to_field(msg, 2), m = 1, L = 48 ---
  (defun hash-to-field:[integer] (msg:integer)
    (let* ( (bs (expand96 msg))
            (b1 (at 0 bs)) (b2 (at 1 bs)) (b3 (at 2 bs)) )
      [ (mod (+ (* b1 (^ 2 128)) (shift b2 -128)) P)          ; bytes  0..47
        (mod (+ (* (mod b2 (^ 2 128)) (^ 2 256)) b3) P) ]))   ; bytes 48..95

  (defun gx:integer (x:integer) (mod (+ (* x (mod (* x x) P)) CURVE-B) P))
  (defun mk:object (u:integer x:integer y:integer)
    ;; sgn0(u) == sgn0(y) else negate y   (sgn0 for a prime field = LSB)
    { "x": x, "y": (if (= (mod u 2) (mod y 2)) y (mod (- P y) P)) })

  ;; --- RFC 9380 s6.6.1 Shallue-van de Woestijne map to G1 (cofactor of BN254 G1 is 1) ---
  (defun map-to-curve:object (u:integer)
    (let* ( (t1a (mod (* (mod (* u u) P) 4) P))          ; u^2 * g(Z)
            (tv2 (mod (+ 1 t1a) P))
            (tv1 (mod (- 1 t1a) P))
            (tv3 (inv (mod (* tv1 tv2) P)))
            (tv4 (mod (* (mod (* (mod (* u tv1) P) tv3) P) C3) P))
            (x1  (mod (- C2 tv4) P))
            (g1v (gx x1))
            (y1  (sqrtc g1v)) )
      (if (= (mod (* y1 y1) P) g1v)
          (mk u x1 y1)
          (let* ( (x2 (mod (+ C2 tv4) P)) (g2v (gx x2)) (y2 (sqrtc g2v)) )
            (if (= (mod (* y2 y2) P) g2v)
                (mk u x2 y2)
                (let* ( (tt (mod (* (mod (* tv2 tv2) P) tv3) P))
                        (x3 (mod (+ (mod (* (mod (* tt tt) P) C4) P) 1) P))
                        (g3v (gx x3)) (y3 (sqrtc g3v)) )
                  (enforce (= (mod (* y3 y3) P) g3v) "SvdW x3 branch is not a square")
                  (mk u x3 y3)))))))

  (defun hash-to-g1:object (msg:integer)
    (let ((us (hash-to-field msg)))
      (point-add "g1" (map-to-curve (at 0 us)) (map-to-curve (at 1 us)))))

  (defun round-digest:integer (r:integer)
    ;; b64f encodes exactly 8 bytes and WRAPS SILENTLY above that, so without this
    ;; bound a signature for round r also verifies as round r + 2^64 -- and
    ;; verified-seed formats the raw round into the seed, giving a second seed
    ;; from one signature. Unreachable from a consumer whose round comes from
    ;; round-at, but this module is sealed and meant to be reused, so the bound
    ;; belongs here rather than in whoever calls it next.
    (enforce (and (>= r 1) (< r (^ 2 64))) "drand round out of range")
    (kec [(b64f r 8)]))                                   ; keccak256(I2OSP(round, 8))

  ;; --- G2 generator, negated ---
  (defconst G2Y0:integer 8495653923123431417604973247489272438418190587263600148770280649306958101930)
  (defconst G2Y1:integer 4082367875863433681332203403145435568316851327593401208105741076214120093531)
  (defconst NEG-G2
    { "x": [10857046999023057135944570762232829481370756359578518086990519993285655852781
           ,11559732032986387107991004021392285783925812861821192530917403151452391805634]
    , "y": [(- P G2Y0) (- P G2Y1)] })

  ;; --- wire decoding ---
  (defun g1-from-hex:object (h:string)          ; 128 hex chars = x || y, 32 bytes each
    (enforce (= 128 (length h)) "G1 must be 64 bytes")
    (let ((x (str-to-int 16 (take 64 h)))
          (y (str-to-int 16 (drop 64 h))))
      ;; 🔴 CANONICAL ONLY. A 32-byte coordinate holds values up to 2^256-1 while
      ;; the field modulus P is ~2^254, and the pairing native reduces its input
      ;; mod P -- so x, x+P, x+2P ... are the SAME curve point and every one of
      ;; them verifies. 2^256/P = 5, so one genuine beacon has ~30 verifying
      ;; encodings. A consumer deriving a value from the raw coordinates then gets
      ;; ~30 answers from one real signature, and if submitting the beacon is
      ;; permissionless the submitter picks which. MEASURED on a real beacon
      ;; before this check existed: wheel positions 33, 31, 30, 11, 22 and 32.
      (enforce (and (< x P) (< y P))
        "G1 coordinates must be canonical: each below the field modulus")
      { "x": x, "y": y }))
  (defun g2-from-hex:object (h:string)          ; 256 hex chars, c1-first on the wire
    (enforce (= 256 (length h)) "G2 must be 128 bytes")
    (let ( (w0 (str-to-int 16 (take 64 h)))
           (w1 (str-to-int 16 (take 64 (drop 64 h))))
           (w2 (str-to-int 16 (take 64 (drop 128 h))))
           (w3 (str-to-int 16 (drop 192 h))) )
      { "x": [w1 w0], "y": [w3 w2] }))

  ;; --- the whole verification ---
  (defun verify:bool (pk:object rnd:integer sig:object)
    (pairing-check [(hash-to-g1 (round-digest rnd)) sig] [pk NEG-G2]))

  ;;;;;;;;;;;;;;;;;;;;;;;;;; THE PINNED evmnet CHAIN ;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  ; drand chain hash, recorded so anyone can re-fetch the key and check it:
  ;   https://api.drand.sh/v2/chains/<CHAIN-HASH>/info
  (defconst CHAIN-HASH:string
    "04f1e9062b8a81f848fded9c12306733282b2727ecced50032187751166ec8c3")

  ; The evmnet group public key, a 128-byte uncompressed G2 point, decoded once.
  ; Fetched 2026-09-20; scheme bls-bn254-unchained-on-g1.
  (defconst PK-HEX:string
    "07e1d1d335df83fa98462005690372c643340060d205306a9aa8106b6bd0b3820557ec32c2ad488e4d4f6008f89a346f18492092ccc0d594610de2732c8b808f0095685ae3a85ba243747b1b2f426049010f6b73a0cf1d389351d5aaaa1047f6297d3a4f9749b33eb2d904c9d9ebf17224150ddd7abd7567a9bec6c74480ee0b")

  (defconst PK:object (g2-from-hex PK-HEX))

  ; genesis_time 1727521075 = 2024-09-28T10:57:55Z, period 3 s. Both from /info.
  (defconst EPOCH:time (time "1970-01-01T00:00:00Z"))
  (defconst GENESIS:integer 1727521075)
  (defconst PERIOD:integer 3)

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; THE PUBLIC API ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  (defun round-at:integer (t:time)
    @doc "The drand round that is published at or before `t`. A consumer pins the \
    \round for a bet BEFORE it is published, so pass a time in the future."
    (let ((secs (floor (diff-time t EPOCH))))
      (enforce (>= secs GENESIS) "time precedes the drand chain genesis")
      (+ 1 (/ (- secs GENESIS) PERIOD))))

  (defun time-of-round:time (rnd:integer)
    @doc "When drand publishes `rnd`. The inverse of round-at."
    (enforce (>= rnd 1) "drand rounds start at 1")
    (add-time EPOCH (dec (+ GENESIS (* PERIOD (- rnd 1))))))

  (defun verified-seed:integer (rkey:string rnd:integer sig-hex:string)
    @doc "Verify the beacon for `rnd` against the pinned evmnet key and return a \
    \seed bound to `rkey`. ABORTS unless the signature verifies, so a caller \
    \cannot proceed on an unchecked beacon by ignoring a boolean."
    (let ((sig (g1-from-hex sig-hex)))
      ; pairing-check skips a pair containing the point at infinity, so state the
      ; refusal here rather than relying on the native to reject it.
      (enforce (not (and (= 0 (at 'x sig)) (= 0 (at 'y sig))))
        "the point at infinity is not a signature")
      (enforce (verify PK rnd sig) "drand signature does not verify")
      ; Seeded from the decoded coordinates REDUCED MOD P, never the hex. Two
      ; things must not change the seed: the hex case ("0A" vs "0a"), and a
      ; non-canonical encoding of the same point. g1-from-hex already refuses the
      ; latter; reducing here means a seed stays canonical even if it did not.
      (str-to-int 64 (hash (format "drand|{}|{}|{}|{}"
                                   [rkey rnd (mod (at 'x sig) P) (mod (at 'y sig) P)])))))
)
