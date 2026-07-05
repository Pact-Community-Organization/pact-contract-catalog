# ADR-001: Split the catalog into a Registry (observatory) and a Library (deployable templates)

Status: Proposed
Date: 2026-07-05

## Context

The PCO mission is "make it easy and safe for businesses to start building with
smart contracts." The catalog is where that promise is delivered — but today it
conflates two fundamentally different artifact classes under one `contracts/` tree:

1. **Observed contracts** (~29 of 34 entries): verbatim snapshots of code that
   already exists — upstream Kadena LLC standards and infrastructure (`kip/`,
   `core/`, `marmalade/`), and census-selected third-party mainnet modules
   (`ecosystem/`, plus census-sourced entries currently filed under `community/`
   such as cyberfly and p2p-escrow). These are read-only documentation: nobody
   "starts a project" from `kaddex.kdx`. Their value is education, integration
   reference, and due diligence.
2. **Deployable templates** (~3 entries): PCO-authored contracts a builder copies,
   adapts, and deploys (`hello-world`, `token-fungible`). This is the artifact
   class the mission actually promises — and it is nearly empty while appearing
   to be backed by a 34-entry catalog.

The conflation causes concrete problems:

- **Messaging**: an enterprise evaluator cannot answer "what here can I actually
  use?" without reading every README. The catalog looks substantial; the usable
  surface is 2–3 entries.
- **Metadata**: two incompatible schemas already coexist (schema A:
  slug/repository/license for curated entries; schema B: namespace/module/
  layer/census for observed entries) because the two artifact classes genuinely
  need different fields. The current tree mixes them within `community/`.
- **Safety**: `community/p2p-escrow` — an *observed* on-chain module with an open
  CRITICAL finding (`(defcap GOVERNANCE () true)`) — sits directly beside the
  templates builders are told to copy.
- **Audit economics**: the `independently-audited` bar (CONTRACT_POLICIES §3.1)
  is only worth paying for on templates PCO ships; observed modules can never
  rise above `reference`/`community-reviewed` because PCO does not control them.

Doing this restructure now is cheap: the repository has minimal external
deep-linking today. Every month of delay raises the cost of moving paths.

## Options considered

1. **Status quo** — keep one mixed tree. Rejected: the mission-vs-content gap
   compounds as both cohorts grow, and the p2p-escrow class of hazard recurs.
2. **Two repositories** (`pact-contract-registry` + `pact-contract-library`).
   Cleanest separation and independent release cadence, but doubles CI/docs/
   governance maintenance for a one-maintainer organization and breaks the
   single-clone experience. Rejected for now; re-evaluate if the library reaches
   ~15+ entries or gains its own release process.
3. **Two top-level trees inside `contracts/` in this repository** — chosen.

## Decision

Restructure `contracts/` into two explicitly-named product trees:

```
contracts/
  registry/                 — what exists on-chain / upstream (observatory; read-only)
    kip/                    — KIP standard interfaces            (schema A, status: reference)
    core/                   — genesis chain infrastructure       (schema A, status: reference)
    marmalade/              — Marmalade v2 NFT stack             (schema A, status: reference)
    ecosystem/              — census-selected third-party mainnet modules (schema B)
    community/              — census-observed free-namespace community modules
                              (cyberfly-node, cyberfly-token, p2p-escrow)   (schema B)
  library/                  — PCO-authored deployable templates (the product)
    hello-world/            — tutorial entry point               (schema A)
    token-fungible/         — fungible-v2 reference token        (schema A)
    <future templates>      — gas-station, nft-collection, multisig-treasury,
                              vesting-escrow, dao-voting, oracle-consumer
```

Rules that follow from the split:

1. **Slugs and entry-directory contents do not change** — only the path prefix
   moves (git mv, history preserved). No contract source is modified by this ADR.
2. **Schema by tree**: `library/` entries MUST use schema A (slug, repository,
   license, authors, audit_status, tags); `registry/` entries use schema A with
   `audit_status: reference` (upstream layers) or schema B (census layers).
   `validate_contract.sh` enforces the correct schema from the path.
3. **Library quality gate** (enforced by CI for `library/` only): co-located
   `examples/*.repl` test suite required; `AUDIT.md` at `self-reviewed` minimum
   on entry; the CONTRACT_POLICIES §2 coverage requirement applies to library
   entries specifically. Registry entries are exempt (verbatim snapshots).
4. **Safety placement**: any entry with an open CRITICAL finding lives in
   `registry/`, never `library/`, regardless of authorship. p2p-escrow therefore
   moves to `registry/community/`.
5. **Documentation split**: README leads with the two products ("browse the
   library to start a project; browse the registry to understand the chain");
   `docs/index.md` gains Registry and Library top-level sections; ARCHITECTURE.md
   dependency-layer model is unchanged but re-rooted under `registry/`, with
   `library/` consuming `registry/kip` + `registry/core` interfaces.
6. **Index generator**: reworked for the two-tree layout; also fixes the ragged
   trailing chains column emitted for schema-B entries in five-column tables.

## Consequences

Positive:
- The enterprise call-to-action becomes one sentence: "start from `library/`."
  Claims become honest per tree — the registry documents, the library ships.
- Audit budget (the path to `independently-audited`) concentrates where PCO
  controls the source and users deploy it.
- The two metadata schemas each get a home and a validator mode instead of
  coexisting ambiguously.
- Known-hazardous observed modules can no longer sit beside templates.

Negative / costs:
- One-time path breakage for any existing external deep links (accepted: minimal
  today; GitHub does not redirect moved paths).
- README, ARCHITECTURE, five tier READMEs, `generate_index.sh`,
  `validate_contract.sh`, and CI need coordinated updates in the same PR.
- `library/` starts visibly small (2 entries). This is deliberate honesty and
  creates the backlog pressure to build WS3 templates.

Follow-ups (out of scope for this ADR):
- WS3: populate `library/` (hardened fungible token first — its current
  `@managed true` ROTATE and missing sender-guard enforcement in DEBIT are
  remediated as part of template hardening, tracked separately).
- Marketing/website updates on pact-community.org to mirror the two-product story.
