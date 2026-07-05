# kip.token-manifest

> **Pre-deployed · Module · Audited**  
> The Kadena KIP standard for on-chain NFT metadata (manifests). Used by `marmalade-v2.ledger` to attach verifiable, content-addressed metadata to every token at creation time.

---

## Overview

`kip.token-manifest` provides the data structures and cryptographic verification functions for NFT manifests on KDA-CE. A **manifest** is a collection of typed data items (URIs + datums) that describes a token's content. The manifest hash is embedded in the token ID, making it immutable and content-addressed.

Every token created via `marmalade-v2.ledger.create-token` requires a valid manifest built with this module.

---

## On-Chain Identity

| Property | Value |
|----------|-------|
| Module name | `kip.token-manifest` |
| Namespace | `kip` |
| Chain(s) | 0–19 (all chains) |
| Network | `mainnet01`, `testnet06` |
| Source | [`kda-community/chainweb-node`](https://github.com/kda-community/chainweb-node) |

---

## Capabilities

| Capability | Description |
|-----------|-------------|
| `GOVERNANCE` | Module upgrade control (Kadena / KDA-CE admin) |

---

## Schemas

| Schema | Fields | Description |
|--------|--------|-------------|
| `mf-uri` | `scheme:string data:string` | A URI (scheme = MIME type, data = URL or inline data) |
| `mf-datum` | `uri:object{mf-uri} hash:string` | A manifest datum: a URI + its content hash |
| `manifest` | `uri:object{mf-uri} data:[object{mf-datum}]` | The full manifest: primary URI + list of datums |

---

## Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `uri` | `(scheme:string data:string) → object{mf-uri}` | Construct a `mf-uri` record |
| `create-datum` | `(uri:object{mf-uri} data:object) → object{mf-datum}` | Create a datum from a URI + arbitrary data (hashed) |
| `create-manifest` | `(uri:object{mf-uri} data:[object{mf-datum}]) → object{manifest}` | Assemble a manifest from a primary URI and datum list |
| `hash-contents` | `(data:object) → string` | Hash arbitrary data using BLAKE2b (used internally by `create-datum`) |
| `verify-manifest` | `(manifest:object{manifest}) → bool` | Verify datum hashes are consistent with content |
| `enforce-verify-manifest` | `(manifest:object{manifest}) → bool` | Enforce manifest integrity; throws if invalid |

---

## Dependency Graph

```
kip.token-manifest  (module — no interface dependencies)
 └── used by  marmalade-v2.ledger  (create-token requires a manifest)
 └── used by  marmalade-v2.util-v1  (manifest utility helpers)
```

---

## Usage Example

```pact
;; Build a manifest for an image NFT
(let* (
  ;; Primary URI: points to the token's main content
  (primary-uri (kip.token-manifest.uri "image/png" "https://example.com/nft/1.png"))

  ;; Datum: a text datum describing the NFT
  (description-datum
    (kip.token-manifest.create-datum
      (kip.token-manifest.uri "text/plain" "My NFT description")
      { "name": "My NFT #1", "description": "A unique digital collectible" }))

  ;; Assemble the manifest
  (manifest
    (kip.token-manifest.create-manifest primary-uri [description-datum]))
  )

  ;; Verify the manifest before use (optional — ledger enforces this)
  (kip.token-manifest.enforce-verify-manifest manifest)

  ;; Use in token creation
  (let ((token-id (marmalade-v2.ledger.create-token-id manifest "free")))
    (marmalade-v2.ledger.create-token token-id 0 manifest
      marmalade-v2.guard-policy-v1))
)
```

---

## Token ID Derivation

The token ID is derived deterministically from the manifest hash, ensuring:
- Each unique NFT content maps to a unique token ID
- Token IDs are content-addressed and independent of deployer
- Duplicate content cannot produce separate token IDs (deduplication)

```
token-id = "<namespace>:" + hash(manifest)
```

---

## Related Modules

- [`marmalade-v2.ledger`](../../marmalade/ledger/README.md) — uses manifests for `create-token`
- [`kip.token-policy-v2`](../token-policy-v2/README.md) — `token-info` schema includes the token URI derived from the manifest
- [`marmalade-v2.policy-manager`](../../marmalade/policy-manager/README.md) — policy context references manifest data
