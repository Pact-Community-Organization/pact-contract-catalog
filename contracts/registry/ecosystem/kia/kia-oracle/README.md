# KIA Oracle

**Module:** `n_40c883decc192e1e3214898f04656b2e9ea7b74e.kia-oracle`
**Project:** KIA Oracle | **Category:** Oracle | **Layer:** ecosystem
**Chain:** 1 | **Network:** mainnet01

> Ranked **#1** by function call frequency in the 90-day KDA-CE mainnet census (30 calls).

## Overview

KIA Oracle is a key/value price oracle that stores timestamped decimal values for arbitrary
keys. It supports batching multiple data-point updates into a single transaction, reducing
gas overhead for high-frequency price feeds.

## Capability Model

| Capability  | Guard            | Purpose                              |
|-------------|------------------|--------------------------------------|
| `GOVERNANCE`| admin keyset     | Module upgrade control               |
| `ADMIN`     | admin keyset     | Composes GOVERNANCE + STORAGE        |
| `STORAGE`   | internal (`true`)| Guards table writes from REPORT path |

Write path for reporters: `require-capability (STORAGE)` — reporters can update values
without holding GOVERNANCE, using the REPORT keyset only.

## Key Functions

| Function        | Description                                              |
|-----------------|----------------------------------------------------------|
| `set-value`     | Write a single key/value pair with current timestamp     |
| `set-values`    | Batch-write multiple key/value pairs in one transaction  |
| `get-value`     | Read current value and timestamp for a key               |

## Dependencies

- `free.util-time` — provides the `GENESIS` constant and time utilities

## On-Chain Provenance

Source fetched via `(describe-module "n_40c883decc192e1e3214898f04656b2e9ea7b74e.kia-oracle")`
on chain 1, mainnet01. `blockchain_hash` in `metadata.yaml` matches the module hash
returned by the node.

## Security Notes

- Two keysets: ADMIN (admin ns) and REPORT (report ns) — least-privilege write access
- STORAGE capability is composed by ADMIN, isolating oracle data writes
- No @event on data writes — off-chain indexers must poll to detect updates
