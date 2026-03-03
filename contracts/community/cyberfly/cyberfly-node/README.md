# CyberFly Node Registry

**Module:** `free.cyberfly_node`
**Project:** CyberFly | **Category:** DePIN | **Layer:** community
**Chain:** 1 | **Network:** mainnet01

> Ranked **#2** by function call frequency in the 90-day KDA-CE mainnet census (28 calls).

## Overview

CyberFly Node is the on-chain registry for the CyberFly DePIN (Decentralized Physical
Infrastructure Network). Each physical node operator registers their node's `peer_id`
and `multiaddr` and stakes CFLY tokens as collateral. The module manages the full
lifecycle of node staking: registration, stake updates, reward claims, and de-registration.

## Schemas

| Schema          | Key Fields                                                     |
|-----------------|----------------------------------------------------------------|
| `node-schema`   | `peer_id`, `status`, `multiaddr`, `account`, `guard`, timestamps |
| `stake-schema`  | `peer_id`, staked amounts and lock state                       |

## Vault Accounts

| Account                  | Purpose                            |
|--------------------------|------------------------------------|
| `cyberfly-staking-bank`  | Holds staked CFLY tokens           |
| `cyberfly-reward-bank`   | Holds CFLY reward pool             |

## Dependencies

- `coin` — KDA for gas/transaction fees
- `free.cyberfly_token` — CFLY token for staking and rewards

## Governance

Controlled by `(enforce-keyset "free.cyberfly_team")` — team multi-sig.
