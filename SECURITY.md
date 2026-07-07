# Security Policy

The Pact Contract Catalog is maintained by the Pact Community Organization (PCO)
under the mission to make it *easy and safe* for businesses to start building with
smart contracts. Security reporting is central to that promise.

## Scope

This policy covers:

- The catalog tooling (`scripts/`, CI workflows, validation logic).
- Contracts **authored by PCO**: the `contracts/library/` templates, the NFT
  interface standard (`contracts/standards/`), and the NFT Framework
  (`contracts/nft/`).

Contract entries under `contracts/registry/` are catalogued
**verbatim** from upstream or on-chain sources and carry the `reference` or
`community-reviewed` audit status. PCO does not control their source. If you find a
vulnerability in one of those, please **also** report it to the originating project;
we will coordinate and annotate the affected entry's `AUDIT.md`.

## Reporting a vulnerability

**Do not open a public issue for a security vulnerability.**

Report privately through one of:

1. **GitHub private vulnerability reporting** (preferred) — use the
   "Report a vulnerability" button under this repository's **Security** tab. This
   opens a private advisory visible only to maintainers.
2. **Email** — `security@pact-community.org` (or `info@pact-community.org` if the
   security alias is unavailable). PGP key on request.

Please include:

- The affected contract entry or tooling path.
- A description of the issue and its impact.
- Steps to reproduce, or a proof-of-concept (a `.repl` reproduction is ideal).
- Any suggested remediation.

## What to expect

| Stage | Target |
|-------|--------|
| Acknowledgement of report | within **3 business days** |
| Initial severity assessment | within **7 business days** |
| Remediation plan communicated | within **14 business days** of confirmation |
| Public disclosure | coordinated with the reporter after a fix is available |

Severity is classified using the categories in
[docs/CONTRACT_POLICIES.md](docs/CONTRACT_POLICIES.md). Contracts found to carry a
confirmed critical finding are downgraded to `unaudited`, flagged in their
`AUDIT.md`, and — for the `library/` tree — may be moved out of the deployable
templates until remediated.

## Safe harbor

We will not pursue or support legal action against researchers who:

- Make a good-faith effort to comply with this policy,
- Avoid privacy violations, data destruction, and service disruption, and
- Give us reasonable time to remediate before public disclosure.

## Recognition

With your permission, we credit reporters in the affected entry's `AUDIT.md` and in
release notes. Thank you for helping keep the Pact ecosystem safe.
