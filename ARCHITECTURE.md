# Repository architecture — Pact Smart Contracts Catalog

## Purpose

Define a clear structure to store contract metadata, audits, usage examples, and automated validation for the Pact ecosystem.

## Top-level layout

• `README.md` — repository overview, mission & vision.
• `ARCHITECTURE.md` — this file.
• `CONTRIBUTING.md` — how to contribute contract entries and audits.
• `CODE_OF_CONDUCT.md` — community guidelines.
• `LICENSE` — project license (MIT by default).
• `contracts/` — contract entries and metadata.
  ◦ `<contract-slug>/` — a folder per contract containing:
   ■ `README.md` — human-friendly description, API, examples.
   ■ `metadata.yaml` — machine-readable metadata (version, authors, repo, license, audit-status).
   ■ `examples/` — deployment or REPL examples.
   ■ `AUDIT.md` — audit notes or links to external audit reports.
• `scripts/` — helper scripts (validation, index generation).
• `docs/` — onboarding and public guidance (short public-safe `docs/ONBOARDING.md`).

## Automation

• `scripts/generate_index.sh` — build an index (JSON/Markdown) from `contracts/*/metadata.yaml`.
• CI: run `scripts/validate_contract.sh` for each contract to ensure metadata correctness and run basic static checks.

## Metadata schema (example for `metadata.yaml`)

```yaml
name: 'My Contract'
slug: 'my-contract'
version: '1.0.0'
repository: 'https://github.com/Pact-Community-Organization/<repo>'
license: 'MIT'
authors:
  - name: 'Alice'
    email: 'alice@example.org'
audit_status: 'audited' # audited | in-review | not-audited
tags: ['token','finance']
keywords: ['pact','smart-contract']
```

## Governance notes

All additions should be made via PR. Audits and external reports must be linked in `AUDIT.md` and referenced in `metadata.yaml`.