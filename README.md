# Pact Contract Catalog

Welcome to the Pact Contract Catalog, the central repository for reusable, trusted Pact smart contracts. This repository is maintained by the Pact Community Organization (PCO) to ensure the safety, quality, and accessibility of Pact contracts.

## Mission Alignment

In alignment with the PCO mission to "Make it easy and safe for businesses to start building with smart contracts," the catalog ships two clearly separated products (see [ADR-001](docs/adr/ADR-001-registry-library-split.md)):

- **[`contracts/library/`](contracts/library/) — the Library.** PCO-authored, deployable contract templates. This is where you start a project: copy a template, adapt it, deploy it. Every library entry ships with a co-located REPL test suite and a documented audit record at `self-reviewed` or better.
- **[`contracts/registry/`](contracts/registry/) — the Registry.** An observatory of contracts that already exist: the KIP standard interfaces, the pre-deployed chain infrastructure, the Marmalade NFT framework, and census-selected third-party mainnet modules. Read-only reference for integration, education, and due diligence — these are verbatim snapshots, not starting points.

## Repository Structure

- `contracts/library/` — deployable templates (the product). Strict quality gate.
- `contracts/registry/` — observed contracts, grouped by dependency layer (`kip/`, `core/`, `marmalade/`, `ecosystem/`, `community/`). See [ARCHITECTURE.md](ARCHITECTURE.md) for the layer model and dependency graph.
- `docs/` — documentation, the generated [contract index](docs/index.md), [onboarding](docs/ONBOARDING.md), [contract policies](docs/CONTRACT_POLICIES.md), and [ADRs](docs/adr/).
- `scripts/` — validation and index-generation tooling.

## Starting a Project (Library)

1. Browse [`contracts/library/`](contracts/library/) or the [contract index](docs/index.md).
2. Copy the template directory into your project and adapt it (namespace, keysets, business rules).
3. Run its co-located `.repl` test suite (see Testing below) and extend the tests for your changes.
4. Review the entry's `AUDIT.md` for known considerations before deploying.

## Testing Contracts

To test Pact contracts locally, use a Pact REPL environment:

1. Go to the repository: https://github.com/CryptoPascal31/kadena_repl_sandbox
2. Follow the instructions in its README to set up the local REPL environment.
3. Clone the sandbox repository and use it to run `.repl` test files from this catalog.

For example, to test the hello-world template:
- Navigate to `contracts/library/hello-world/`
- Run the test using the sandbox environment as per the kadena_repl_sandbox instructions.

This ensures contracts are tested in a proper Pact environment before submission.

## Contributing a Contract

- **Library templates** (deployable, PCO-reviewed): follow [docs/ONBOARDING.md](docs/ONBOARDING.md). Library entries must pass the quality gate: schema-A metadata, co-located `.repl` tests, `AUDIT.md` at `self-reviewed` or better.
- **Registry entries** (observed on-chain modules): require deployment evidence (module hash, `describe-module` output, or block-explorer link) matching the census methodology in [contracts/registry/ecosystem/README.md](contracts/registry/ecosystem/README.md).

All submissions run the CI validation gate (`scripts/validate_contract.sh`). See [CONTRIBUTING.md](CONTRIBUTING.md) for the full workflow.

## Governance

This repository follows the governance model defined in the [PCO Foundation](https://github.com/Pact-Community-Organization/foundation). For contract-specific policies, see [docs/CONTRACT_POLICIES.md](docs/CONTRACT_POLICIES.md). Architecture decisions are recorded in [docs/adr/](docs/adr/). Security disclosures: [SECURITY.md](SECURITY.md).

## License

This repository is licensed under the Apache-2.0 License. See the [LICENSE](LICENSE) file for details.
