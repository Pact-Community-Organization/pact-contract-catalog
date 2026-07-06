# AUDIT — library/dao-voting

## Summary

| Field | Value |
|---|---|
| **Module** | `dao-voting` (namespace: project-specific) |
| **Version** | 1.0.0 |
| **Audit Status** | self-reviewed |
| **Category** | PCO Library Template |
| **Source** | PCO-authored reference implementation |
| **Last review** | 2026-07-05 |

## Purpose

Deployable template for membership-based on-chain voting: a governed member
set votes yes/no/abstain on deadline-bounded proposals; settlement checks a
quorum (participation vs. current members) and an approval threshold (yes vs.
yes+no). Custodies no funds — it produces an auditable decision record,
intended to pair with the multisig-treasury template.

## Audit history: findings and fixes

An independent `pact-auditor` pass returned **GO with required dispositions**
(zero CRITICAL/HIGH; one MEDIUM, two LOW, three INFO). All required items
were implemented:

| # | Severity | Finding | Fix |
|---|----------|---------|-----|
| M-1 | **MEDIUM** | `close` read quorum/threshold from **live config**, so governance could rotate the percentages after votes were cast on an open proposal and move the passage bar — including **force-passing a motion the members rejected** (reproduced: 1-yes/2-no at threshold 60 → governance drops threshold to 1 → close returns "passed"). Especially serious because this module's output is meant to authorize treasury actions. | Quorum/threshold are now **snapshotted into the proposal row at propose time**; `close` settles against the snapshot. The member *set* deliberately stays live (that is what lets rotation revoke a compromised member's votes); the residual governance influence via the member list is documented and event-audited. Regression-tested (`close-p8-snapshot-holds`: governance lowering the bar to 1/1 does not flip an open proposal; `new-proposal-uses-new-bar`: future proposals use the new bar). |
| L-1 | LOW | No upper bound on the member count. `close` is O(members × voters); the docs claimed "bounded by member count" with no tested ceiling. | `MAX_MEMBERS = 200` enforced in the shared config validation, backed by the auditor's gas measurements (344 / 858 / 2,693 gas at 50 / 100 / 200 all-voting members — quadratic, but ~2 orders of magnitude under the 150k ceiling at the cap). Regression-tested (201 members rejected). |
| L-2 | LOW | Coverage gaps: the shipped suite did not exercise the M-1 vector, the in-place re-key sharp edge, exact-at-threshold boundaries, or single-member edges. | All folded into the shipped suite: snapshot regression, re-key revival (documented sharp edge, asserted), inclusive quorum+threshold exact boundaries, single-member 100/100 (sole-yes passes, silence fails quorum). |

**Informational (confirmed, accepted):**

- **Re-key revival.** Re-enrolling a compromised member under the *same name*
  with a new guard revives the old key's votes on still-open proposals — the
  unavoidable dual of keying votes by name (which is what makes
  rotation-revocation work). The compromise response is to **remove the
  name**; documented in module doc + README and *proven* in the suite
  (`close-p10-rekey-revives`).
- **MEMBER-AUTH scope.** The capability is per-account (not per-proposal): one
  scoped signature lets a member act on multiple proposals in one transaction,
  but cannot double-vote any single proposal and cannot authorize anything
  outside this module. Sound design, verified by probe.
- **Proposal-id squatting.** A member can front-run another member's intended
  id (insert collision; retry with a fresh id). Member-gated griefing only.

## Threat model & defenses

| Vector | Defense | Test |
|---|---|---|
| Non-member proposes/votes | `MEMBER-AUTH` checks current membership | `propose-non-member`, `vote-non-member` |
| Impersonate a member by name | `MEMBER-AUTH` enforces the enrolled guard | `propose-wrong-key`, `vote-wrong-key` |
| Vote twice (any choice combination) | member checked against all three choice lists | `vote-p1` double-vote case |
| Alter/remove a cast vote | append-only lists; no mutation path exists | capability sweep |
| Vote after the deadline / on settled | strict `< deadline` + `status = open` gates | `vote-at-deadline`, `close-settled`, `cancelled-is-dead` |
| Settle early / re-settle | `>= deadline` + `status = open`; status settles before event | `close-before-deadline`, re-close case |
| Governance moves the bar on an open proposal | per-proposal quorum/threshold snapshot | `close-p8-snapshot-holds` |
| Rotated-out member's vote counts | `close` filters votes to current members | `close-p6-stale-vote-dropped` |
| Zero-yes passage (all-abstain quorum) | `yes > 0` required to pass | `close-outcome-matrix` p4 |
| Quorum/threshold math manipulation | integer-only products (no division/rounding) | `exact-boundaries`, `single-member-dao` |
| Gas-exhaustion via giant member set | `MAX_MEMBERS = 200` (measured ~2.7k gas at cap) | `member-cap` |
| Governance votes or flips outcomes | `GOV` has no vote path; settled proposals immutable | capability sweep + re-close case |

## Capability model

| Capability | Type | Guard | Notes |
|---|---|---|---|
| `GOV` | governance | `keyset-ref-guard GOV_KEYSET` | init / rotate-members / cancel / upgrade; cannot vote |
| `MEMBER-AUTH (account)` | authentication | current membership + enrolled guard (reads let-bound, then enforced) | acquired by `propose`/`vote`; members sign scoped |
| `PROPOSED`/`VOTED`/`CLOSED`/`CANCELLED`/`MEMBERS_ROTATED` | `@event` | — | emit-only audit trail |

`close` and the views take no capability: settlement is deterministic from
recorded state, and the recorded votes are the authorization. There are no
managed caps, no weak-body caps on any public path, and no external module
calls anywhere (not even coin).

## Node-safety

Every `enforce` operates on arguments or let/with-read-bound locals;
`MEMBER-AUTH` uses the bind-before-enforce pattern for both the membership
read and the guard read. This class is REPL-invisible on KDA-CE, so **devnet
validation of a full `propose → vote → close` cycle is the required
evidence** before production use — see the README deployment checklist.

## Risk profile

| Risk | Level | Notes |
|---|---|---|
| Unauthorized/duplicate voting | Low | scoped caps over enrolled guards + counts-once, regression-tested |
| Outcome manipulation | Low | snapshot bar + integer math + zero-yes rule; settled proposals immutable |
| Rotation abuse | Medium | member list stays live by design (revocation feature); governance influence over open proposals is inherent and event-audited — use a multi-sig |
| Denial of service | Low | O(1) transactional paths; close bounded by `MAX_MEMBERS`; id-squat is member-gated griefing |
| Governance dependency | Medium | upgrade power is ultimate power: pin the module hash, multi-sig the keyset |

## Static analysis note

`pact-static-check.sh` reports **PASS, 0 violations** — including a clean
Tier-1 standalone load (this module has no upstream dependencies). The two
Tier-2 `enforce-guard` WARNs are dispositioned SAFE — both sit inside defcaps
(`GOV`, `MEMBER-AUTH`).

## What self-reviewed means here

Reviewed by the template's maintainers against the PCO checklist, with the
decision-integrity model encoded as runnable regression tests, plus an
independent `pact-auditor` pass (automated, fresh-context) whose required
dispositions are all implemented. **Not independent human review.** Promotion
requires a second reviewer (`community-reviewed`) or a third-party report with
a matching source hash (`independently-audited`) — see
`docs/CONTRACT_POLICIES.md` §3.1.

## Devnet validation (on-node evidence)

**Validated on a live KDA-CE devnet (recap-development) node, 2026-07-06.** The template was deployed under the
`free` namespace (governance keyset namespaced, per the deployment checklist)
and its critical paths were driven to mined confirmation with `@kadena/client`
— the required evidence for the REPL-invisible read-in-enforce class.

| | |
|---|---|
| Deployed module | `free.dao-voting` |
| Source hash | `V01qREMpESX4M8vEf-iplX-9CILUfUPvTmgPJTEjX9U` |
| Confirmed transactions | 13 |

Proven on-node: `MEMBER-AUTH` (config-read bound before `enforce`); propose → vote → **close after a real ~90-second deadline** (chain time polled, not slept), settling `passed` on-node, with non-member and double votes rejected.

Reproduce: `scripts/devnet-validate` → `npm run dao-voting` (see that directory's README).

## Reproduce the review

```bash
cd contracts/library/dao-voting/examples
pact dao-voting-test.repl   # 60 assertions
```
