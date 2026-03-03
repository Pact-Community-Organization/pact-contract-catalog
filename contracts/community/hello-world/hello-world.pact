(module hello-world ADMIN

  (defcap ADMIN () (enforce-guard (keyset-ref-guard "hello-world-admin")))

  (defschema message-schema
    message:string
    timestamp:time)

  (deftable messages:{message-schema})

  (defun hello-world (name:string)
    "Returns a personalized hello message."
    (format "Hello, {}! Welcome to Pact." [name]))

  (defun store-message (message:string)
    "Stores a message with timestamp."
    (with-capability (ADMIN)
      (insert messages (hash message) {
        "message": message,
        "timestamp": (at 'block-time (chain-data))
      })))

  (defun get-message (msg-hash:string)
    "Retrieves a stored message."
    (with-read messages msg-hash {
      "message":= msg,
      "timestamp":= ts
    }
    (format "Message: {} at {}" [msg ts])))
)