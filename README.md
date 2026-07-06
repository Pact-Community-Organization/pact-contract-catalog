# Pact Contract Catalog

Reusable, trusted Pact smart contracts, maintained by the Pact Community Organization (PCO) in service of one mission: **make it easy and safe for businesses to start building with smart contracts.**

The catalog ships two clearly separated products (see [ADR-001](docs/adr/ADR-001-registry-library-split.md)):

- **[`contracts/library/`](contracts/library/) — the Library**: PCO-authored, deployable templates. Start here.
- **[`contracts/registry/`](contracts/registry/) — the Registry**: an observatory of contracts that already exist on-chain, catalogued verbatim for reference.

## The Library

Eight production-grade templates covering the foundations most projects need. Every one shipped through the same three gates: a **blocking CI test suite**, a **static-analysis pass**, and an **independent adversarial security review** whose findings and fixes are documented in the entry's `AUDIT.md` — including the attacks that were tried and defeated.

| Template | What it is |
|---|---|
| [token-fungible](contracts/library/token-fungible/) | A hardened `fungible-v2` + `fungible-xchain-v1` token: coin-pattern guard enforcement, governed mint, reserved-name protection, cross-chain step semantics. |
| [gas-station](contracts/library/gas-station/) | Drain-defended gas sponsorship: bounds and accounting against *actual* chain gas (never signer-supplied values), per-user on-chain allowlist. |
| [multisig-treasury](contracts/library/multisig-treasury/) | M-of-N treasury: KDA in a capability-guarded vault, asynchronous propose/approve/execute, rotation that revokes stale approvals. |
| [vesting](contracts/library/vesting/) | Cliff + linear vesting, escrowed upfront: the beneficiary never depends on the funder's solvency; revoke returns only the unvested part; governance has zero fund paths. |
| [dao-voting](contracts/library/dao-voting/) | Membership voting with quorum + threshold: per-proposal snapshot of the passage bar, rotation revokes a compromised member's in-flight votes. Pairs with the treasury. |
| [nft-collection-policy](contracts/library/nft-collection-policy/) | A marmalade-v2 concrete policy: creator-gated collections with size caps and a strict one-of-one NFT invariant, tested against the real marmalade ledger. |
| [oracle-feed](contracts/library/oracle-feed/) | Median data/price feed with fail-closed consumption: chain-assigned timestamps, staleness windows, publisher rotation as instant revocation, plus a worked consumer pattern. |
| [hello-world](contracts/library/hello-world/) | The minimal starter: module shape, governance, a real test suite. |

All entries currently carry `audit_status: self-reviewed` — a defined claim, not a vibe: see the [audit-status ladder](docs/CONTRACT_POLICIES.md) (§3.1) for exactly what each level means and what evidence it requires. Nothing in this catalog calls itself "audited" without naming who audited it.

### Starting a project

1. Browse the table above or the generated [contract index](docs/index.md).
2. Copy the template directory into your project; adapt the namespace, keysets, and business rules.
3. Read the entry's `README.md` (usage, deployment checklist, known limits) and `AUDIT.md` (threat model, findings history) — they are short and written to be read.
4. Run and extend the co-located test suite (below).
5. **Validate on devnet before mainnet.** Every entry's README says this because it is load-bearing: one class of KDA-CE bug (table reads inside `enforce` conditions) is invisible in the REPL. The templates are written to the node-safe pattern, but your adaptations need the same proof.

### Testing

Library test suites are **self-contained** — they load their dependencies (coin, kip interfaces, marmalade) from this repo's registry tree. With a [Pact 5 binary](https://github.com/kadena-io/pact-5) on your PATH:

```bash
cd contracts/library/multisig-treasury/examples
pact treasury-test.repl
```

CI runs every library suite as a blocking check on every PR, plus the catalog validator and an index-freshness gate.

## The Registry

[`contracts/registry/`](contracts/registry/) catalogues contracts that already exist, grouped by dependency layer: `kip/` (standard interfaces), `core/` (pre-deployed chain infrastructure), `marmalade/` (the NFT framework), `ecosystem/` (census-selected third-party mainnet modules), and `community/`. These are **verbatim snapshots** — read-only reference for integration, education, and due diligence, not starting points. See [ARCHITECTURE.md](ARCHITECTURE.md) for the layer model and the census methodology.

## Contributing

- **Library templates** (deployable, PCO-reviewed): follow [docs/ONBOARDING.md](docs/ONBOARDING.md). The quality gate requires schema-A metadata, a co-located `.repl` suite, a `README.md`, and an `AUDIT.md` at `self-reviewed` or better.
- **Registry entries** (observed on-chain modules): require deployment evidence (module hash, `describe-module` output, or block-explorer link) matching the census methodology.
- **Reviews**: the fastest way to raise the whole catalog's trust level is to review an existing template — see "Reviewing a library template" in [CONTRIBUTING.md](CONTRIBUTING.md). A qualifying independent review promotes an entry to `community-reviewed`.

All submissions run the CI validation gate (`scripts/validate_contract.sh`). See [CONTRIBUTING.md](CONTRIBUTING.md) for the full workflow.

## Governance

This repository follows the governance model defined in the [PCO Foundation](https://github.com/Pact-Community-Organization/foundation). Contract policies: [docs/CONTRACT_POLICIES.md](docs/CONTRACT_POLICIES.md). Architecture decisions: [docs/adr/](docs/adr/). Security disclosures: [SECURITY.md](SECURITY.md).

## License

Apache-2.0 — see [LICENSE](LICENSE).
