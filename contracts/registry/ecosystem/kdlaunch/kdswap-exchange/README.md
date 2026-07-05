# KDSwap Exchange

**Module:** `kdlaunch.kdswap-exchange`
**Project:** KDLaunch | **Category:** DEX / AMM | **Layer:** ecosystem
**Chain:** 1 | **Network:** mainnet01

> Ranked **#5** by function call frequency in the 90-day KDA-CE mainnet census (3 calls).

## Overview

KDSwap Exchange is the Automated Market Maker (AMM) DEX module from KDLaunch.
It implements constant-product swap mechanics with on-chain formal verification
properties verifying that pair guards are enforced on every write.

## Key Functions

| Function            | Description                                           |
|---------------------|-------------------------------------------------------|
| `create-pair`       | Initialize a new liquidity pair (insert, unguarded)   |
| `add-liquidity`     | Deposit into a pair, receive LP tokens                |
| `remove-liquidity`  | Burn LP tokens, receive underlying assets             |
| `swap-exact-in`     | Swap a fixed input amount for minimum output          |
| `swap-exact-out`    | Swap for a fixed output amount with maximum input     |
| `swap`              | Core swap with reserve update                         |

## Formal Verification

The module includes `@model` properties:
- `prop-pairs-write-guard` — every write to the pairs table is guard-enforced
(except `create-pair` which uses insert semantics, and internal private functions)

## On-Chain Provenance

Source fetched via `(describe-module "kdlaunch.kdswap-exchange")` on chain 1, mainnet01.
