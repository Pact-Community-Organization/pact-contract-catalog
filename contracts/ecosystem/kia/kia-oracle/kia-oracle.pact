(module kia-oracle GOVERNANCE
  @doc "KIA key/value oracle with support for multiple updates in a single tx"
  (use free.util-time [GENESIS])

  (defconst ADMIN_KEYSET "n_40c883decc192e1e3214898f04656b2e9ea7b74e.admin")
  (defconst REPORT_KEYSET "n_40c883decc192e1e3214898f04656b2e9ea7b74e.report")

  (defschema value-schema
    timestamp:time
    value:decimal)

  (deftable storage:{value-schema})

  (defcap GOVERNANCE ()
    "Module governance capability that only allows the admin to update this oracle"
    (enforce-keyset ADMIN_KEYSET))

  (defcap STORAGE ()
    "Magic capability to protect oracle data storage"
    true)

  (defcap ADMIN ()
    "Capability that only allows the module admin to update oracle storage"
    (compose-capability (GOVERNANCE))
    (compose-capability (STORAGE))
  )

  (defcap REPORT ()
    "Capability that only allows the module to update oracle storage"
    (enforce-keyset REPORT_KEYSET)
    (compose-capability (STORAGE))
  )

  (defcap UPDATE (key:string timestamp:time value:decimal)
    "Event that indicates an update in oracle data"
    @event true
  )

  (defun get-value:object{value-schema} (key:string)
    "Read a value stored at key"

    (with-default-read storage key
      { "timestamp": GENESIS, "value": 0.0 }
      { "timestamp" := t, "value" := v }
      { "timestamp": t, "value": v }
    )
  )

  (defun set-value (key:string timestamp:time value:decimal)
    (with-capability (REPORT)
      (update-value key timestamp value))
  )

  (defun set-multiple-values (_keys:[string] timestamps:[time] values:[decimal])
    "Update multiple oracle values"

    (enforce (and
      (= (length _keys) (length timestamps))
      (= (length _keys) (length values)))
      "Input lengths should be equal")

    (with-capability (REPORT)
      (map
        (lambda (i) (update-value (at i _keys) (at i timestamps) (at i values)))
        (enumerate 0 (- (length _keys) 1)))
    )
  )

  (defun update-value (key:string timestamp:time value:decimal)
    "Update the value stored at key. Can only be used from within the module."

    (require-capability (STORAGE))
    (enforce
      (>= (diff-time timestamp GENESIS) 0.0)
      "Timestamp should be positive")

    (write storage key { "timestamp": timestamp, "value": value })
    (emit-event (UPDATE key timestamp value))
  ))