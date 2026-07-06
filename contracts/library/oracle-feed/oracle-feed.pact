(module oracle-feed GOV

  @doc "PCO library template: a median price/data feed with staleness-guarded  \
  \consumption.                                                                \
  \                                                                              \
  \A governed set of PUBLISHER accounts posts observations (positive decimal   \
  \values) per feed. Consumers read an aggregate that is robust by             \
  \construction:                                                               \
  \  - the MEDIAN of observations: with n fresh answers, fewer than n/2       \
  \    rogue publishers cannot move the answer beyond the honest range.       \
  \    That guarantee needs n >= 3 (n >= 2f+1): a 1-answer read is one        \
  \    publisher's word, and a 2-answer read averages - giving either         \
  \    publisher unbounded pull. Set MIN-ANSWERS >= 3 for adversarial         \
  \    robustness;                                                             \
  \  - only observations FRESHER than the caller-supplied max-age count       \
  \    (timestamps are assigned by the chain at post time - publishers        \
  \    cannot backdate or forward-date);                                       \
  \  - only observations from CURRENTLY enrolled publishers count             \
  \    (rotating a compromised publisher out immediately revokes their        \
  \    standing observation);                                                  \
  \  - at least the feed's MIN-ANSWERS fresh observations must exist, or      \
  \    the read aborts - consumers fail closed, never on stale/thin data.     \
  \                                                                              \
  \Governance curates the publisher set and creates feeds; it cannot post     \
  \or alter observations. NOTE: unlike this library's custody templates,      \
  \an oracle's governance is OPERATIONALLY trusted - it chooses who may       \
  \publish. Put it under a multi-sig.                                          \
  \                                                                              \
  \Deployment checklist (see README.md):                                        \
  \  1. Wrap in your namespace; replace the 'oracle-feed-gov' keyset.           \
  \  2. Deploy, create-table, (init publishers guards), (create-feed ...).     \
  \  3. Validate on devnet before mainnet."

  ;; -----------------------------
  ;; Governance
  ;; -----------------------------

  (defconst GOV_KEYSET:string "oracle-feed-gov"
    @doc "Governance keyset name. Replace with your deployed, namespace- \
         \qualified keyset (multi-sig recommended). Governance enrolls and \
         \rotates publishers, creates feeds, and upgrades the module. It \
         \cannot post or alter observations.")

  (defcap GOV ()
    @doc "Module governance: publisher set, feed creation, upgrade."
    (enforce-guard (keyset-ref-guard GOV_KEYSET)))

  ;; -----------------------------
  ;; Schemas & tables
  ;; -----------------------------

  (defschema config-row
    @doc "Singleton publisher-set config."
    publishers:[string])

  (deftable config:{config-row})

  (defschema publisher-row
    @doc "Row-level guard for a publisher account, captured at enrollment."
    guard:guard)

  (deftable publisher-guards:{publisher-row})

  (defschema feed-row
    @doc "A feed and its read quorum."
    description:string
    min-answers:integer)  ;; fresh observations required for a read

  (deftable feeds:{feed-row})

  (defschema observation-row
    @doc "A publisher's LATEST observation for a feed (upserted on post). \
         \UPDATED is assigned from chain time at post - never caller-supplied."
    feed:string
    publisher:string
    value:decimal
    updated:time)

  (deftable observations:{observation-row})

  (defconst CONFIG_KEY:string "config")

  (defconst MAX_PUBLISHERS:integer 20
    @doc "Upper bound on the publisher set. Reads map over all publishers \
         \and sort their fresh values - bounded and cheap at 20; real-world \
         \oracle sets are small and curated.")

  (defconst EPOCH:time (time "1970-01-01T00:00:00Z"))

  ;; -----------------------------
  ;; Events
  ;; -----------------------------

  (defcap FEED_CREATED (feed:string description:string min-answers:integer)
    @event true)

  (defcap POSTED (feed:string publisher:string value:decimal)
    @event true)

  (defcap PUBLISHERS_ROTATED (publishers:[string])
    @event true)

  ;; -----------------------------
  ;; Internal helpers
  ;; -----------------------------

  (defun chain-time:time ()
    @doc "Current block time (the PARENT block's timestamp on Chainweb - \
         \about one block behind wall-clock; factor that into max-age)."
    (at 'block-time (chain-data)))

  (defun get-config:object{config-row} ()
    (read config CONFIG_KEY))

  (defun is-publisher:bool (account:string)
    (contains account (at 'publishers (get-config))))

  (defcap PUBLISH-AUTH (account:string)
    @doc "Authenticate ACCOUNT as a current publisher: it must be enrolled \
         \AND the caller must satisfy its enrolled guard. As a capability, a \
         \publisher scopes their signature to \
         \(oracle-feed.PUBLISH-AUTH \"node-1\"), so a posting signature does \
         \NOT also authorize other operations the same key could satisfy. \
         \The scope is per-PUBLISHER, not per-feed: one signature covers \
         \posts to any number of feeds in the transaction (publishers are \
         \module-wide by design)."
    ; NODE-SAFETY: bind the table read to a local FIRST, then enforce - a
    ; table read inside an enforce condition passes in the REPL but FAILS on
    ; the KDA-CE node.
    (let ((publisher-ok (is-publisher account)))
      (enforce publisher-ok "not an enrolled publisher"))
    (with-read publisher-guards account { 'guard := g }
      (enforce-guard g)))

  (defun enforce-valid-publishers:bool (publishers:[string] guards:[guard])
    @doc "Shared validation for the publisher set."
    (enforce (> (length publishers) 0) "at least one publisher required")
    (enforce (<= (length publishers) MAX_PUBLISHERS)
      (format "publisher count exceeds maximum of {}" [MAX_PUBLISHERS]))
    (enforce (= (length publishers) (length guards))
      "publishers/guards length mismatch")
    (enforce (= (length (distinct publishers)) (length publishers))
      "duplicate publishers")
    ; ':' is the observation-key separator (obs-key); allowing it in names
    ; would let distinct (feed, publisher) pairs alias the same row
    (map (lambda (p:string)
           (enforce (and (!= p "") (not (contains ":" p)))
             "publisher names must be non-empty and must not contain ':'"))
         publishers)
    true)

  (defun obs-key:string (feed:string publisher:string)
    @doc "Injective because ':' is banned in both feed ids and publisher \
         \names (enforced at create-feed / enforce-valid-publishers)."
    (format "{}:{}" [feed publisher]))

  (defun median:decimal (values:[decimal])
    @doc "Median of a non-empty list. Even count averages the two middle \
         \values - the result may carry one decimal place more than the \
         \inputs; round to your token's precision before money math."
    (let* ((sorted (sort values))
           (n (length sorted))
           (mid (/ n 2)))
      (if (= 1 (mod n 2))
        (at mid sorted)
        (/ (+ (at (- mid 1) sorted) (at mid sorted)) 2.0))))

  ;; -----------------------------
  ;; Lifecycle & governance
  ;; -----------------------------

  (defun init:string (publishers:[string] guards:[guard])
    @doc "One-time setup: enroll the publisher set (guards align \
         \positionally). The config insert enforces one-time setup."
    (with-capability (GOV)
      (enforce-valid-publishers publishers guards)
      (insert config CONFIG_KEY { 'publishers: publishers })
      (zip (lambda (p:string g:guard) (write publisher-guards p { 'guard: g }))
           publishers guards)
      (emit-event (PUBLISHERS_ROTATED publishers))
      "initialized"))

  (defun rotate-publishers:string (publishers:[string] guards:[guard])
    @doc "Governance: replace the publisher set. Observations from \
         \rotated-out publishers stop counting IMMEDIATELY (reads only \
         \aggregate current publishers). Respond to a publisher key \
         \compromise by enrolling a FRESH NAME, never by re-enrolling the \
         \same name with a new guard: observation rows are never deleted, so \
         \a re-enrolled name instantly revives that name's last posted - \
         \possibly poisoned - value, under its OLD timestamp (which may \
         \still pass a generous max-age)."
    (with-capability (GOV)
      (enforce-valid-publishers publishers guards)
      (update config CONFIG_KEY { 'publishers: publishers })
      (zip (lambda (p:string g:guard) (write publisher-guards p { 'guard: g }))
           publishers guards)
      (emit-event (PUBLISHERS_ROTATED publishers))
      "rotated"))

  (defun create-feed:string (feed:string description:string min-answers:integer)
    @doc "Governance creates a feed with a read quorum. MIN-ANSWERS >= 1, \
         \but understand the trust each value buys: 1 = a single publisher's \
         \word; 2 = an average either publisher can pull without bound; \
         \>= 3 = a true median that bounds any minority. A quorum above the \
         \current publisher count simply makes the feed unreadable until \
         \enough publishers post (fail closed). Feed ids must not contain \
         \':' (the observation-key separator)."
    (with-capability (GOV)
      (enforce (!= feed "") "feed id required")
      (enforce (not (contains ":" feed)) "feed id must not contain ':'")
      (enforce (>= min-answers 1) "min-answers must be >= 1")
      (insert feeds feed { 'description: description, 'min-answers: min-answers })
      (emit-event (FEED_CREATED feed description min-answers))
      feed))

  ;; -----------------------------
  ;; Publishing
  ;; -----------------------------

  (defun post:string (feed:string publisher:string value:decimal)
    @doc "A publisher posts (upserts) their latest observation for FEED. The \
         \timestamp is the chain's, not the caller's. The publisher signs \
         \scoped to PUBLISH-AUTH."
    (with-capability (PUBLISH-AUTH publisher)
      (enforce (> value 0.0) "value must be positive")
      ; feed must exist (bind the read; aborts on a missing feed)
      (let ((feed-exists (at 'min-answers (read feeds feed))))
        (write observations (obs-key feed publisher)
          { 'feed: feed
          , 'publisher: publisher
          , 'value: value
          , 'updated: (chain-time) }))
      (emit-event (POSTED feed publisher value))
      feed))

  ;; -----------------------------
  ;; Consumption
  ;; -----------------------------

  (defun fresh-values:[decimal] (feed:string max-age:decimal)
    @doc "Values from CURRENT publishers whose observation for FEED is no \
         \older than MAX-AGE seconds. Missing observations are excluded (the \
         \sentinel default can never satisfy the value>0 filter)."
    (let* ((publishers (at 'publishers (get-config)))
           (now (chain-time))
           (raw (map (lambda (p:string)
                       (with-default-read observations (obs-key feed p)
                         { 'value: -1.0, 'updated: EPOCH }
                         { 'value := v, 'updated := ts }
                         (if (<= (diff-time now ts) max-age) v -1.0)))
                     publishers)))
      (filter (lambda (v:decimal) (> v 0.0)) raw)))

  (defun get-price:decimal (feed:string max-age:decimal)
    @doc "The median of fresh, current-publisher observations for FEED. \
         \Aborts (fails closed) unless at least the feed's MIN-ANSWERS fresh \
         \observations exist. MAX-AGE (seconds) is the consumer's staleness \
         \tolerance - choose it for your use case; remember block-time is \
         \the parent block's timestamp."
    (enforce (> max-age 0.0) "max-age must be positive")
    (with-read feeds feed { 'min-answers := min-answers }
      (let* ((values (fresh-values feed max-age))
             (answers (length values)))
        (enforce (>= answers min-answers)
          (format "insufficient fresh answers: {} of {} required"
                  [answers min-answers]))
        (median values))))

  ;; -----------------------------
  ;; Views
  ;; -----------------------------

  (defun get-feed:object{feed-row} (feed:string)
    (read feeds feed))

  (defun get-observation:object{observation-row} (feed:string publisher:string)
    (read observations (obs-key feed publisher)))

  (defun answer-count:integer (feed:string max-age:decimal)
    @doc "How many fresh, current-publisher observations FEED has right now."
    (length (fresh-values feed max-age)))
)
