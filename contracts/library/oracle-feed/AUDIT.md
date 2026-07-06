# AUDIT — library/oracle-feed

## Summary

| Field | Value |
|---|---|
| **Module** | `oracle-feed` (namespace: project-specific) |
| **Version** | 1.0.0 |
| **Audit Status** | self-reviewed |
| **Category** | PCO Library Template |
| **Source** | PCO-authored reference implementation |
| **Last review** | 2026-07-06 |

## Purpose

Deployable median data/price feed with fail-closed consumption: a governed
publisher set posts chain-timestamped observations; consumers read the median
of fresh, currently-enrolled publishers' values, aborting below a per-feed
quorum. Custodies no funds.

## Audit history: findings and fixes

An independent `pact-auditor` pass returned **GO conditional on two LOW
dispositions** (zero CRITICAL/HIGH/MEDIUM). Both were implemented, plus the
INFO recommendations:

| # | Severity | Finding | Fix |
|---|----------|---------|-----|
| F1 | LOW | `obs-key` (`"{feed}:{publisher}"`) was **not injective** when names contain `":"` — reproduced: `obs-key("A:B","n1") == obs-key("A","B:n1")`, letting two distinct (feed, publisher) pairs silently alias one observation row and corrupt the median. Especially dangerous for a template, since `"KDA:USD"` is a natural feed-id choice. | `":"` (and empty publisher names) are now **rejected** at `create-feed`, `init`, and `rotate-publishers`, making the key injective by construction. Regression-tested (both rejection paths). |
| F2 | LOW | The module doc claimed median robustness **unconditionally**, but the guarantee needs `n ≥ 2f+1`: a 1-answer read is one publisher's word, and a 2-answer read *averages* — either publisher has unbounded pull (reproduced: honest 1.00 + malicious 1,000,000 → answer 500,000.5). | Docs corrected everywhere the claim appears (module doc, `create-feed` doc, README): the median bounds a minority only at `n ≥ 3`; `min-answers ≥ 3` recommended for adversarial robustness; 1- and 2-answer semantics stated plainly. |

**INFO items (confirmed, dispositioned):**

- **Re-key revival** — re-enrolling a rotated-out publisher *name* revives its
  last posted (possibly poisoned) observation under its old timestamp. Docs
  now instruct: respond to a compromise with a **fresh name**, never an
  in-place re-key (observation rows are never deleted).
- **Non-monotonic block-time** — a future-dated observation counts as fresh
  (`diff-time` negative). Safe direction (very-recent data); publishers cannot
  manipulate freshness either way since timestamps are chain-assigned.
- **Even-median precision** — averaging can carry one extra decimal place;
  documented (consumers round to token precision before money math).
- **`PUBLISH-AUTH` scope** — per-publisher, not per-feed (one signature covers
  posts to multiple feeds in a transaction); now stated in the cap's doc.
- **Unbounded `min-answers`** — a quorum above the publisher count makes the
  feed unreadable; that is the documented fail-closed behavior.
- **`median []`** — aborts on an out-of-bounds index if called directly with
  an empty list; unreachable via `get-price` (quorum ≥ 1 checked first).
- **Suite gap** — the outlier test only proved a *high* outlier; a
  low-outlier regression was added (the auditor verified both directions and
  unsorted inputs independently).

## Threat model & defenses

| Vector | Defense | Test |
|---|---|---|
| Non-publisher posts | `PUBLISH-AUTH` checks enrollment | `post-non-publisher` |
| Impersonate a publisher by name | `PUBLISH-AUTH` enforces the enrolled guard | `post-wrong-key` |
| Backdate/forward-date an observation | timestamps assigned from chain block-time only | `post-node1-node2` timestamp assert |
| Minority manipulation of the answer | median over ≥3 fresh answers bounds any minority | high + low outlier regressions |
| Stale data served | caller's `max-age` excludes old observations; below-quorum reads abort | `staleness`, `quorum-fail-closed` |
| Rotated-out publisher still counts | reads aggregate current publishers only | `rotate-out-revokes-observation` |
| Observation-row aliasing via `":"` names | `":"` banned in feed ids and publisher names (F1) | colon-rejection cases |
| Zero/negative values (incl. sentinel collision) | `value > 0` enforced at post; nothing else writes observations | `post-validation` |
| Feed spoofing / rogue feed creation | `create-feed` is governance-gated, ids unique | `create-feed-requires-gov`, dup case |
| Whole-set repointing (majority/market event) | consumer-side deviation breaker (worked example shipped) | `consumer-rejects-jump` / `consumer-accepts-drift` |
| Governance posts or alters data | no such path; governance = enrollment + feeds + upgrade | capability sweep |

## Capability model

| Capability | Type | Guard | Notes |
|---|---|---|---|
| `GOV` | governance | `keyset-ref-guard GOV_KEYSET` | init / rotate / create-feed / upgrade; **cannot post** — but enrollment is the feed's root of trust (operationally trusted; multi-sig it) |
| `PUBLISH-AUTH (account)` | authentication | enrollment + enrolled guard (reads let-bound, then enforced) | per-publisher scope (module-wide, all feeds) |
| `FEED_CREATED` / `POSTED` / `PUBLISHERS_ROTATED` | `@event` | — | emit-only; `POSTED` stream is the feed's full history |

Reads (`get-price`, `fresh-values`, `answer-count`, views) take no capability:
they are deterministic aggregations of recorded state.

## Node-safety

Every `enforce` operates on arguments or let/with-read-bound locals
(`PUBLISH-AUTH` binds the enrollment read; `get-price` enforces a bound
count). The whole read pipeline (`map`/`with-default-read`/`filter`/`sort`)
runs outside any enforce. Swept clean by author and auditor. This class is
REPL-invisible on KDA-CE, so **devnet validation of enroll → post → read is
the required evidence** before production use.

## Risk profile

| Risk | Level | Notes |
|---|---|---|
| Unauthorized posting | Low | scoped cap over enrolled guards, regression-tested |
| Answer manipulation | Low at `min-answers ≥ 3` | median bounds minorities; 1–2 answer feeds documented as single-opinion |
| Stale/thin reads | Low | fail-closed quorum + caller staleness window |
| State corruption | Low | injective keys (F1 fix); only `post` writes observations |
| Publisher-set capture | **Inherent** | whoever controls enrollment controls the feed — multi-sig governance mandatory in spirit |
| Governance dependency | Medium | upgrade power: pin the module hash, multi-sig the keyset |

## Static analysis note

`pact-static-check.sh` reports **PASS, 0 violations** — including a clean
Tier-1 standalone load (no dependencies). The three Tier-2 `enforce-guard`
WARNs are dispositioned SAFE — all sit inside defcaps (`GOV`, `PUBLISH-AUTH`,
and the suite consumer's governance cap).

## What self-reviewed means here

Reviewed by the template's maintainers against the PCO checklist, with the
data-integrity model encoded as runnable regression tests, plus an independent
`pact-auditor` pass (automated, fresh-context) whose required dispositions are
implemented. **Not independent human review.** Promotion requires a second
reviewer (`community-reviewed`) or a third-party report with a matching source
hash (`independently-audited`) — see `docs/CONTRACT_POLICIES.md` §3.1.

## Devnet validation (on-node evidence)

**Validated on a live KDA-CE devnet (recap-development) node, 2026-07-06.** The template was deployed under the
`free` namespace (governance keyset namespaced, per the deployment checklist)
and its critical paths were driven to mined confirmation with `@kadena/client`
— the required evidence for the REPL-invisible read-in-enforce class.

| | |
|---|---|
| Deployed module | `free.oracle-feed-v2` |
| Source hash | `rp1fc5wsax1zxQvkf-bCT4ajtdn0wOkBn6LAMJQITLQ` |
| Confirmed transactions | 13 |

Proven on-node: `PUBLISH-AUTH` (config-read bound before `enforce`); the `get-price` median pipeline ran both via `/local` and **inside a mined consumer transaction**; staleness failed closed against real block timestamps, and publisher rotation revoked the outlier's standing observation on-node.

Reproduce: `scripts/devnet-validate` → `npm run oracle-feed` (see that directory's README).

## Reproduce the review

```bash
cd contracts/library/oracle-feed/examples
pact oracle-feed-test.repl   # 51 assertions
```
