(module hello-world GOVERNANCE

  "A simple hello world Pact smart contract for demonstration purposes."

  (defcap GOVERNANCE ()
    "Only the admin can update this contract."
    (enforce-guard (keyset-ref-guard "admin-keyset")))

  (defschema message-schema
    message:string
    timestamp:time)

  (deftable messages:{message-schema})

  (defun hello-world (name:string)
    "Returns a personalized hello message."
    (format "Hello, {}! Welcome to Pact." [name]))

  (defun store-message (message:string)
    "Stores a message with timestamp."
    (insert messages (hash message) {
      "message": message,
      "timestamp": (at 'block-time (chain-data))
    }))

  (defun get-message (msg-hash:string)
    "Retrieves a stored message."
    (with-read messages msg-hash {
      "message":= msg,
      "timestamp":= ts
    }
    (format "Message: {} at {}" [msg ts])))
)