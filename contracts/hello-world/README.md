# Hello World Contract

A simple Pact smart contract demonstrating basic functionality for the Pact ecosystem.

## Overview

This contract provides basic greeting functions and message storage capabilities, serving as an entry point for developers learning Pact.

## API

### Functions

#### `hello-world`
Returns a personalized hello message.

**Parameters:**
- `name` (string): The name to greet

**Returns:** string

**Example:**
```pact
(hello-world "Alice")
;; Returns: "Hello, Alice! Welcome to Pact."
```

#### `store-message`
Stores a message with a timestamp.

**Parameters:**
- `message` (string): The message to store

**Returns:** string (hash of the stored message)

**Example:**
```pact
(store-message "My first Pact message")
;; Returns: "msg-hash-123"
```

#### `get-message`
Retrieves a stored message by its hash.

**Parameters:**
- `msg-hash` (string): The hash of the message to retrieve

**Returns:** string

**Example:**
```pact
(get-message "msg-hash-123")
;; Returns: "My first Pact message"
```

## Deployment

This contract requires a keyset named `hello-world-admin` for administrative operations. Deploy with:

```pact
(define-keyset 'hello-world-admin (read-keyset "admin-keyset"))
```

Administrative functions require the ADMIN capability. In production, use a secure keyset with proper access controls.

## Testing

See `examples/hello-world-test.repl` for REPL-based testing examples.

## License

Apache-2.0