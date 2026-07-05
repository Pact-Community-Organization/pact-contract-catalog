# Heron Token

**Module:** `n_e309f0fa7cf3a13f93a8da5325cdad32790d2070.heron`
**Project:** Heron | **Category:** Fungible Token | **Layer:** ecosystem
**Chain:** 1 | **Network:** mainnet01

## Overview

Heron is a community token described by the module itself as "a fun community driven
utility memecoin." Despite the casual description, the module (524 lines) is engineered
to production standards with formal verification properties asserting:

- `conserves-mass` — `column-delta coin-table 'balance` equals 0 (no supply inflation)
- `valid-account` — account strings are 3–256 characters

Implements `fungible-v2` and `fungible-xchain-v1` for full KDA standard compliance
and cross-chain transfer support.

## Formal Verification

```pact
@model
  [ (defproperty conserves-mass
      (= (column-delta coin-table 'balance) 0.0))
    (defproperty valid-account (account:string)
      (and (>= (length account) 3) (<= (length account) 256)))
  ]
```

## Dependencies

- `fungible-v2` — standard token interface
- `fungible-xchain-v1` — cross-chain transfer support

## On-Chain Provenance

Source fetched via `(describe-module "n_e309f0fa7cf3a13f93a8da5325cdad32790d2070.heron")` on chain 1, mainnet01.
