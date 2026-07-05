# P2P Escrow

**Module:** `free.p2p-escrow`
**Project:** P2P Escrow | **Category:** Utility | **Layer:** community
**Chain:** 1 | **Network:** mainnet01

> ⚠️ **Status: experimental** — Contains a critical governance issue. See Security Notes.

> Ranked **#10** by function call frequency in the 90-day KDA-CE mainnet census (1 call).

## Overview

P2P Escrow implements a three-party peer-to-peer escrow flow with on-chain reputation
tracking. The escrow state machine transitions through: `open → funded → accepted → paid`
(or `disputed`). Configurable timeout windows (T1/T2/T3 seconds) govern each phase.

## Escrow Schema

| Field         | Type     | Description                          |
|---------------|----------|--------------------------------------|
| `creator`     | string   | Seller / service provider account    |
| `buyer`       | string   | Buyer account                        |
| `arbiter`     | string   | Dispute arbiter (default: PLATFORM)  |
| `amount`      | decimal  | KDA escrow amount                    |
| `state`       | string   | Current state machine state          |
| `side`        | string   | Transaction side indicator           |

## Reputation Tracking

Each account accumulates `totalTrades`, `successfulTrades`, and `disputesCount`
on-chain, providing a public credibility signal.

## Security Notes

⚠️ **Critical:** `(defcap GOVERNANCE () true)` — the governance capability has **no
keyset guard**. This means any account can call governance-gated functions, including
module upgrades. **Do not use this module in production without forking and fixing
the governance capability.**

Platform arbiter is hardcoded to a fixed account address. The escrow is non-custodial
(funds held in `p2p-escrow-vault`), but the unguarded governance is a deployment risk.
