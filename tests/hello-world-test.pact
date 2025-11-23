(begin-tx)

(load "contracts/hello-world/hello-world.pact")

(commit-tx)

(begin-tx)

; Test hello-world function
(expect "Hello, Alice! Welcome to Pact." (hello-world "Alice"))

; Test store-message
(store-message "Test message")

; Test get-message
(expect "Message: Test message at " (take 25 (get-message (hash "Test message"))))

(commit-tx)